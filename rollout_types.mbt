///|
/// Machine-readable action recommended from static and shadow evidence.
pub(all) enum RolloutRecommendation {
  PromoteCandidate
  HoldCandidate
  RollbackCandidate
  InsufficientEvidence
} derive(Eq, ToJson, FromJson, Debug)

///|
/// Evidence thresholds for a rollout. Rates are basis points (1/100 of one
/// percent) so policies behave identically on every backend.
pub(all) struct RolloutPolicy {
  min_samples : Int
  max_regressions : Int
  max_regression_basis_points : Int
  max_relaxations : Int
  max_diagnostic_shifts : Int
  max_truncated_cases : Int
  require_static_compatibility : Bool
  allow_static_review : Bool
} derive(Eq, ToJson, FromJson, Debug)

///|
pub(all) struct RolloutAssessment {
  recommendation : RolloutRecommendation
  reasons : Array[String]
  static_report : CompatibilityReport?
  shadow_metrics : ShadowMetrics
} derive(Eq, ToJson, FromJson, Debug)

///|
pub(all) struct RegistryRolloutAssessment {
  found : Bool
  channel : String
  baseline_version : Int?
  candidate_version : Int?
  assessment : RolloutAssessment?
} derive(Eq, ToJson, FromJson, Debug)

///|
/// Result of deterministic canary routing. Only the served rule is executed;
/// use shadow analysis separately when both reports are required.
pub(all) struct CanaryValidationResult {
  found : Bool
  channel : String
  baseline_version : Int?
  candidate_version : Int?
  served_version : Int?
  routed_to_candidate : Bool
  bucket : Int?
  report : ValidationReport?
} derive(Eq, ToJson, FromJson, Debug)
