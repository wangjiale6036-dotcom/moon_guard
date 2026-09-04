///|
/// Behavioral delta observed when one payload is evaluated by two contract
/// versions. A diagnostic shift keeps the rejection decision but changes its
/// machine-readable path, code or severity.
pub(all) enum ShadowOutcome {
  StableAccept
  StableReject
  CandidateRegression
  CandidateRelaxation
  DiagnosticShift
} derive(Eq, ToJson, FromJson, Debug)

///|
pub(all) struct ShadowCaseReport {
  id : String
  /// Canonical payload snapshot for behavior deltas only. Redacted by default
  /// and populated only when callers explicitly enable witness capture.
  witness_json : String?
  outcome : ShadowOutcome
  baseline : ValidationReport
  candidate : ValidationReport
} derive(Eq, ToJson, FromJson, Debug)

///|
/// Aggregate production-replay evidence. Rates use basis points to remain
/// deterministic across backends and avoid floating-point threshold drift.
pub(all) struct ShadowMetrics {
  total : Int
  stable_accept : Int
  stable_reject : Int
  regressions : Int
  relaxations : Int
  diagnostic_shifts : Int
  disagreement_count : Int
  baseline_passed : Int
  candidate_passed : Int
  truncated_cases : Int
  regression_basis_points : Int
  baseline_issues : Array[IssueCount]
  candidate_issues : Array[IssueCount]
} derive(Eq, ToJson, FromJson, Debug)

///|
pub(all) struct ShadowReport {
  metrics : ShadowMetrics
  cases : Array[ShadowCaseReport]
} derive(Eq, ToJson, FromJson, Debug)

///|
pub(all) struct RegistryShadowResult {
  found : Bool
  channel : String
  baseline_version : Int?
  candidate_version : Int?
  report : ShadowReport?
} derive(Eq, ToJson, FromJson, Debug)
