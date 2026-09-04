///|
/// Conservative defaults: require 100 samples and tolerate no known behavior
/// regression, security relaxation, diagnostic drift or truncated evidence.
pub fn default_rollout_policy() -> RolloutPolicy {
  {
    min_samples: 100,
    max_regressions: 0,
    max_regression_basis_points: 0,
    max_relaxations: 0,
    max_diagnostic_shifts: 0,
    max_truncated_cases: 0,
    require_static_compatibility: true,
    allow_static_review: false,
  }
}

///|
pub fn rollout_policy(
  min_samples? : Int = 100,
  max_regressions? : Int = 0,
  max_regression_basis_points? : Int = 0,
  max_relaxations? : Int = 0,
  max_diagnostic_shifts? : Int = 0,
  max_truncated_cases? : Int = 0,
  require_static_compatibility? : Bool = true,
  allow_static_review? : Bool = false,
) -> RolloutPolicy {
  {
    min_samples: min_samples.max(0),
    max_regressions: max_regressions.max(0),
    max_regression_basis_points: max_regression_basis_points.max(0).min(10000),
    max_relaxations: max_relaxations.max(0),
    max_diagnostic_shifts: max_diagnostic_shifts.max(0),
    max_truncated_cases: max_truncated_cases.max(0),
    require_static_compatibility,
    allow_static_review,
  }
}

///|
/// Combine conservative static inference and replayed traffic evidence into a
/// transparent recommendation. Every failed policy predicate becomes a reason
/// rather than being hidden behind a boolean.
pub fn assess_rollout(
  static_report : CompatibilityReport?,
  shadow_report : ShadowReport,
  policy? : RolloutPolicy = default_rollout_policy(),
) -> RolloutAssessment {
  let reasons : Array[String] = []
  let metrics = shadow_report.metrics
  if metrics.total < policy.min_samples {
    reasons.push(
      "sample count \{metrics.total} is below required \{policy.min_samples}",
    )
    return {
      recommendation: InsufficientEvidence,
      reasons,
      static_report,
      shadow_metrics: metrics,
    }
  }
  if metrics.regressions > policy.max_regressions {
    reasons.push(
      "candidate regressions \{metrics.regressions} exceed limit \{policy.max_regressions}",
    )
  }
  if metrics.regression_basis_points > policy.max_regression_basis_points {
    reasons.push(
      "regression rate \{metrics.regression_basis_points}bp exceeds limit \{policy.max_regression_basis_points}bp",
    )
  }
  if !reasons.is_empty() {
    return {
      recommendation: RollbackCandidate,
      reasons,
      static_report,
      shadow_metrics: metrics,
    }
  }
  match static_report {
    Some(report) => {
      if policy.require_static_compatibility && report.breaking_count > 0 {
        reasons.push(
          "static radar found \{report.breaking_count} breaking change(s)",
        )
      }
      if !policy.allow_static_review && report.review_count > 0 {
        reasons.push(
          "static radar found \{report.review_count} change(s) requiring review",
        )
      }
    }
    None =>
      if policy.require_static_compatibility {
        reasons.push("static compatibility evidence is missing")
      }
  }
  if metrics.relaxations > policy.max_relaxations {
    reasons.push(
      "candidate relaxations \{metrics.relaxations} exceed limit \{policy.max_relaxations}",
    )
  }
  if metrics.diagnostic_shifts > policy.max_diagnostic_shifts {
    reasons.push(
      "diagnostic shifts \{metrics.diagnostic_shifts} exceed limit \{policy.max_diagnostic_shifts}",
    )
  }
  if metrics.truncated_cases > policy.max_truncated_cases {
    reasons.push(
      "truncated cases \{metrics.truncated_cases} exceed limit \{policy.max_truncated_cases}",
    )
  }
  if reasons.is_empty() {
    reasons.push("all rollout evidence satisfies policy")
    {
      recommendation: PromoteCandidate,
      reasons,
      static_report,
      shadow_metrics: metrics,
    }
  } else {
    {
      recommendation: HoldCandidate,
      reasons,
      static_report,
      shadow_metrics: metrics,
    }
  }
}

///|
pub fn rollout_assessment_to_json(report : RolloutAssessment) -> String {
  report.to_json().stringify(indent=2)
}

///|
pub fn RuleRegistry::assess_candidate(
  self : RuleRegistry,
  channel : String,
  candidate_version : Int,
  cases : Array[ValidationCase],
  policy? : RolloutPolicy = default_rollout_policy(),
  options? : ValidationOptions = default_validation_options(),
) -> RegistryRolloutAssessment {
  let static_result = self.compare_with_active(channel, candidate_version)
  let shadow_result = self.shadow_with_active(
    channel,
    candidate_version,
    cases,
    options~,
  )
  if !static_result.found || !shadow_result.found {
    return {
      found: false,
      channel,
      baseline_version: None,
      candidate_version: None,
      assessment: None,
    }
  }
  {
    found: true,
    channel,
    baseline_version: static_result.baseline_version,
    candidate_version: Some(candidate_version),
    assessment: Some(
      assess_rollout(
        static_result.report,
        shadow_result.report.unwrap(),
        policy~,
      ),
    ),
  }
}

///|
/// Stable, allocation-free routing bucket. Modulo is applied at every step so
/// the arithmetic stays bounded and matches across JS, Wasm and native targets.
pub fn stable_rollout_bucket(key : String, buckets? : Int = 10000) -> Int {
  let bucket_count = buckets.max(1).min(1000000)
  let mut hash = 17 % bucket_count
  for char in key {
    hash = (hash * 131 + char.to_int()) % bucket_count
  }
  hash
}

///|
pub fn is_canary_selected(key : String, candidate_basis_points : Int) -> Bool {
  let threshold = candidate_basis_points.max(0).min(10000)
  stable_rollout_bucket(key) < threshold
}

///|
/// Serve a deterministic percentage of routing keys with a candidate revision.
/// The active revision remains the baseline and registry state is not mutated.
pub fn RuleRegistry::validate_canary_json(
  self : RuleRegistry,
  channel : String,
  candidate_version : Int,
  routing_key : String,
  candidate_basis_points : Int,
  text : String,
  options? : ValidationOptions = default_validation_options(),
) -> CanaryValidationResult {
  let baseline = self.active_revision(channel)
  let candidate = self.get_revision(channel, candidate_version)
  match (baseline, candidate) {
    (Some(old), Some(next)) => {
      let bucket = stable_rollout_bucket(routing_key)
      let routed = bucket < candidate_basis_points.max(0).min(10000)
      let served = if routed { next } else { old }
      {
        found: true,
        channel,
        baseline_version: Some(old.version),
        candidate_version: Some(next.version),
        served_version: Some(served.version),
        routed_to_candidate: routed,
        bucket: Some(bucket),
        report: Some(validate_json(served.rule, text, options~)),
      }
    }
    _ =>
      {
        found: false,
        channel,
        baseline_version: None,
        candidate_version: None,
        served_version: None,
        routed_to_candidate: false,
        bucket: None,
        report: None,
      }
  }
}
