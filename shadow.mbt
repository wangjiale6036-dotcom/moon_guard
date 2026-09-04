///|
fn diagnostics_equal(
  baseline : ValidationReport,
  candidate : ValidationReport,
) -> Bool {
  if baseline.issues.length() != candidate.issues.length() {
    return false
  }
  for index = 0; index < baseline.issues.length(); index = index + 1 {
    let old = baseline.issues[index]
    let next = candidate.issues[index]
    if old.path != next.path ||
      old.code != next.code ||
      old.severity != next.severity {
      return false
    }
  }
  true
}

///|
fn shadow_outcome(
  baseline : ValidationReport,
  candidate : ValidationReport,
) -> ShadowOutcome {
  if baseline.valid && candidate.valid {
    StableAccept
  } else if baseline.valid {
    CandidateRegression
  } else if candidate.valid {
    CandidateRelaxation
  } else if diagnostics_equal(baseline, candidate) {
    StableReject
  } else {
    DiagnosticShift
  }
}

///|
/// Shadow reports default to redacted issue values because replay inputs often
/// originate from production logs. Callers may opt back in explicitly.
pub fn default_shadow_options() -> ValidationOptions {
  default_validation_options().with_value_preview(false)
}

///|
/// Replay payloads through a baseline and candidate contract. This operation
/// is pure and does not mutate the registry, making it suitable for sampled
/// traffic and offline logs. Payload capture is opt-in and limited to observed
/// acceptance deltas so ordinary reports do not retain request bodies.
pub fn shadow_validate(
  baseline : Rule,
  candidate : Rule,
  cases : Array[ValidationCase],
  options? : ValidationOptions = default_shadow_options(),
  capture_witnesses? : Bool = false,
) -> ShadowReport {
  let case_reports : Array[ShadowCaseReport] = []
  let baseline_reports : Array[ValidationReport] = []
  let candidate_reports : Array[ValidationReport] = []
  let mut stable_accept = 0
  let mut stable_reject = 0
  let mut regressions = 0
  let mut relaxations = 0
  let mut diagnostic_shifts = 0
  let mut baseline_passed = 0
  let mut candidate_passed = 0
  let mut truncated_cases = 0
  for case in cases {
    let old_report = validate(baseline, case.value, options~)
    let next_report = validate(candidate, case.value, options~)
    let outcome = shadow_outcome(old_report, next_report)
    match outcome {
      StableAccept => stable_accept += 1
      StableReject => stable_reject += 1
      CandidateRegression => regressions += 1
      CandidateRelaxation => relaxations += 1
      DiagnosticShift => diagnostic_shifts += 1
    }
    if old_report.valid {
      baseline_passed += 1
    }
    if next_report.valid {
      candidate_passed += 1
    }
    if old_report.stats.truncated || next_report.stats.truncated {
      truncated_cases += 1
    }
    baseline_reports.push(old_report)
    candidate_reports.push(next_report)
    let witness_json = if capture_witnesses &&
      (outcome == CandidateRegression || outcome == CandidateRelaxation) {
      Some(case.value.stringify())
    } else {
      None
    }
    case_reports.push({
      id: case.id,
      witness_json,
      outcome,
      baseline: old_report,
      candidate: next_report,
    })
  }
  let disagreement_count = regressions + relaxations + diagnostic_shifts
  let regression_basis_points = if cases.is_empty() {
    0
  } else {
    regressions * 10000 / cases.length()
  }
  {
    metrics: {
      total: cases.length(),
      stable_accept,
      stable_reject,
      regressions,
      relaxations,
      diagnostic_shifts,
      disagreement_count,
      baseline_passed,
      candidate_passed,
      truncated_cases,
      regression_basis_points,
      baseline_issues: issue_histogram(merge_reports(baseline_reports)),
      candidate_issues: issue_histogram(merge_reports(candidate_reports)),
    },
    cases: case_reports,
  }
}

///|
/// Extract concrete, machine-replayable counterexamples where the baseline
/// accepted a payload and the candidate rejected it.
pub fn regression_witnesses(report : ShadowReport) -> Array[ValidationCase] {
  let result : Array[ValidationCase] = []
  for case in report.cases {
    if case.outcome == CandidateRegression {
      match case.witness_json {
        Some(text) => {
          let value = @json.parse(text) catch { _ => continue }
          result.push({ id: case.id, value, })
        }
        None => ()
      }
    }
  }
  result
}

///|
/// Extract payloads newly accepted by the candidate. These are compatibility
/// relaxations but may also represent a security-policy regression.
pub fn relaxation_witnesses(report : ShadowReport) -> Array[ValidationCase] {
  let result : Array[ValidationCase] = []
  for case in report.cases {
    if case.outcome == CandidateRelaxation {
      match case.witness_json {
        Some(text) => {
          let value = @json.parse(text) catch { _ => continue }
          result.push({ id: case.id, value, })
        }
        None => ()
      }
    }
  }
  result
}

///|
pub fn shadow_to_json(report : ShadowReport) -> String {
  ToJson::to_json(report).stringify(indent=2)
}

///|
pub fn RuleRegistry::shadow_versions(
  self : RuleRegistry,
  channel : String,
  baseline_version : Int,
  candidate_version : Int,
  cases : Array[ValidationCase],
  options? : ValidationOptions = default_shadow_options(),
  capture_witnesses? : Bool = false,
) -> RegistryShadowResult {
  match
    (
      self.get_revision(channel, baseline_version),
      self.get_revision(channel, candidate_version),
    ) {
    (Some(baseline), Some(candidate)) =>
      {
        found: true,
        channel,
        baseline_version: Some(baseline_version),
        candidate_version: Some(candidate_version),
        report: Some(
          shadow_validate(
            baseline.rule,
            candidate.rule,
            cases,
            options~,
            capture_witnesses~,
          ),
        ),
      }
    _ =>
      {
        found: false,
        channel,
        baseline_version: None,
        candidate_version: None,
        report: None,
      }
  }
}

///|
pub fn RuleRegistry::shadow_with_active(
  self : RuleRegistry,
  channel : String,
  candidate_version : Int,
  cases : Array[ValidationCase],
  options? : ValidationOptions = default_shadow_options(),
  capture_witnesses? : Bool = false,
) -> RegistryShadowResult {
  match self.active_version(channel) {
    None =>
      {
        found: false,
        channel,
        baseline_version: None,
        candidate_version: None,
        report: None,
      }
    Some(active) =>
      self.shadow_versions(
        channel,
        active,
        candidate_version,
        cases,
        options~,
        capture_witnesses~,
      )
  }
}
