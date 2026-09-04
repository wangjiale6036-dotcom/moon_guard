///|
/// How one candidate rule change affects payloads accepted by the previous
/// contract. `ReviewImpact` means the relationship cannot be proven from the
/// rule tree alone and should be checked with shadow traffic.
pub(all) enum ChangeImpact {
  BreakingImpact
  RelaxingImpact
  ReviewImpact
} derive(Eq, ToJson, FromJson, Debug)

///|
/// One explainable semantic difference between two rules.
pub(all) struct RuleChange {
  path : String
  keyword : String
  impact : ChangeImpact
  message : String
} derive(Eq, ToJson, FromJson, Debug)

///|
/// Static compatibility evidence for a candidate API contract.
pub(all) struct CompatibilityReport {
  backward_compatible : Bool
  score : Int
  breaking_count : Int
  relaxing_count : Int
  review_count : Int
  changes : Array[RuleChange]
} derive(Eq, ToJson, FromJson, Debug)

///|
/// Parse-aware wrapper used by CLIs and control planes comparing two JSON rule
/// documents.
pub(all) struct CompatibilityParseResult {
  ok : Bool
  errors : Array[String]
  report : CompatibilityReport?
} derive(Eq, ToJson, FromJson, Debug)

///|
/// Registry version comparison with explicit lookup status.
pub(all) struct RegistryCompatibilityResult {
  found : Bool
  channel : String
  baseline_version : Int?
  candidate_version : Int?
  report : CompatibilityReport?
} derive(Eq, ToJson, FromJson, Debug)
