///|
/// JSON value categories understood by the validation engine.
pub(all) enum ValueKind {
  AnyValue
  NullValue
  BooleanValue
  NumberValue
  IntegerValue
  StringValue
  ArrayValue
  ObjectValue
} derive(Eq, Debug)

///|
/// Severity allows one validation run to return both blocking errors and
/// advisory warnings.
pub(all) enum Severity {
  Error
  Warning
  Info
} derive(Eq, ToJson, FromJson, Debug)

///|
/// Policy for string values. An empty option means that constraint is disabled.
pub(all) struct StringPolicy {
  min_length : Int?
  max_length : Int?
  exact_length : Int?
  prefix : String?
  suffix : String?
  contains : String?
  pattern : String?
  format : String?
  allowed : Array[String]
  forbidden : Array[String]
  ascii_only : Bool
  non_blank : Bool
  case_sensitive : Bool
} derive(Eq, Debug)

///|
/// Policy for JSON numbers.
pub(all) struct NumberPolicy {
  minimum : Double?
  maximum : Double?
  exclusive_minimum : Double?
  exclusive_maximum : Double?
  multiple_of : Double?
  integer_only : Bool
  non_zero : Bool
  positive : Bool
  negative : Bool
} derive(Eq, Debug)

///|
/// A named object property and its nested rule.
pub(all) struct PropertyRule {
  name : String
  rule : Rule
  required : Bool
  deprecated : Bool
  description : String
} derive(Eq, Debug)

///|
/// Conditional property dependency. When `property` exists, all entries in
/// `requires` must also exist.
pub(all) struct PropertyDependency {
  property : String
  requires : Array[String]
} derive(Eq, Debug)

///|
/// Policy for object values.
pub(all) struct ObjectPolicy {
  properties : Array[PropertyRule]
  allow_additional : Bool
  additional_rule : Rule?
  min_properties : Int?
  max_properties : Int?
  dependencies : Array[PropertyDependency]
  mutually_exclusive : Array[Array[String]]
  at_least_one : Array[Array[String]]
} derive(Eq, Debug)

///|
/// Policy for array values.
pub(all) struct ArrayPolicy {
  items : Rule?
  prefix_items : Array[Rule]
  min_items : Int?
  max_items : Int?
  unique_items : Bool
  contains : Rule?
  min_contains : Int
  max_contains : Int?
} derive(Eq, Debug)

///|
/// A predicate used by dynamic conditional rules.
pub(all) enum Predicate {
  Always
  Never
  Exists(String)
  Missing(String)
  Equals(String, Json)
  KindIs(String, ValueKind)
  Validates(String, Rule)
  AllPredicates(Array[Predicate])
  AnyPredicate(Array[Predicate])
  NotPredicate(Predicate)
} derive(Eq, Debug)

///|
/// Composable validation rule tree. It deliberately contains no callbacks so
/// rules can be loaded dynamically from JSON, cached and executed on every
/// MoonBit backend.
pub(all) enum Rule {
  Accept
  Reject(String)
  Kind(ValueKind)
  StringMatches(StringPolicy)
  NumberMatches(NumberPolicy)
  ArrayMatches(ArrayPolicy)
  ObjectMatches(ObjectPolicy)
  EqualsValue(Json)
  InValues(Array[Json])
  AllOf(Array[Rule])
  AnyOf(Array[Rule])
  OneOf(Array[Rule])
  NoneOf(Array[Rule])
  NotRule(Rule)
  Nullable(Rule)
  Optional(Rule)
  When(Predicate, Rule, Rule?)
  AtPath(String, Rule)
  Named(String, String, Rule)
  WarningRule(String, Rule)
} derive(Eq, Debug)

///|
/// Runtime controls. Limits make externally supplied schemas safe to execute.
pub(all) struct ValidationOptions {
  fail_fast : Bool
  max_issues : Int
  max_depth : Int
  max_rule_visits : Int
  include_value_preview : Bool
  include_warnings : Bool
  path_style : String
} derive(Eq, Debug)

///|
/// One structured validation finding.
pub(all) struct ValidationIssue {
  path : String
  code : String
  keyword : String
  message : String
  severity : Severity
  rule_name : String
  value_preview : String
} derive(Eq, ToJson, FromJson, Debug)

///|
/// Stable execution counters useful in tests and production diagnostics.
pub(all) struct ValidationStats {
  rule_visits : Int
  values_checked : Int
  maximum_depth : Int
  error_count : Int
  warning_count : Int
  info_count : Int
  truncated : Bool
} derive(Eq, ToJson, FromJson, Debug)

///|
/// Complete validation report.
pub(all) struct ValidationReport {
  valid : Bool
  issues : Array[ValidationIssue]
  stats : ValidationStats
} derive(Eq, ToJson, FromJson, Debug)

///|
/// Compiled reusable validator facade.
pub struct Validator {
  rule : Rule
  options : ValidationOptions
}

///|
/// Result of parsing a dynamic rule document.
pub(all) struct RuleParseResult {
  rule : Rule?
  errors : Array[String]
  warnings : Array[String]
} derive(Eq, Debug)

///|
/// Static information about a rule tree.
pub(all) struct RuleAnalysis {
  node_count : Int
  maximum_depth : Int
  object_property_count : Int
  conditional_count : Int
  named_rules : Array[String]
  warnings : Array[String]
} derive(Eq, ToJson, FromJson, Debug)

///|
/// A single case for batch validation.
pub(all) struct ValidationCase {
  id : String
  value : Json
} derive(Eq, Debug)

///|
/// Per-case output for batch validation.
pub(all) struct CaseReport {
  id : String
  report : ValidationReport
} derive(Eq, ToJson, FromJson, Debug)

///|
/// Aggregate batch output.
pub(all) struct BatchReport {
  valid : Bool
  total : Int
  passed : Int
  failed : Int
  cases : Array[CaseReport]
} derive(Eq, ToJson, FromJson, Debug)

///|
/// Frequency of one issue code across a report or batch.
pub(all) struct IssueCount {
  code : String
  count : Int
} derive(Eq, ToJson, FromJson, Debug)

///|
/// One immutable rule version stored by the MVP registry. The executable rule
/// and its canonical JSON are kept together so callers can validate quickly
/// while still exposing an auditable representation.
pub(all) struct RuleRevision {
  channel : String
  version : Int
  rule : Rule
  schema_json : String
  note : String
  published_by : String
} derive(Eq, Debug)

///|
/// All revisions for one logical API contract. `active_version` is separate
/// from the append-only revision list so activation and rollback never rewrite
/// historical rule content.
pub(all) struct RuleChannel {
  name : String
  active_version : Int?
  revisions : Array[RuleRevision]
} derive(Eq, Debug)

///|
/// In-memory MVP registry. Arrays make ordering deterministic across every
/// MoonBit backend and are sufficient for embedding in an API process.
pub struct RuleRegistry {
  channels : Array[RuleChannel]
}

///|
/// Stable result returned by registry mutations.
pub(all) struct RegistryResult {
  ok : Bool
  code : String
  message : String
  channel : String
  version : Int?
} derive(Eq, ToJson, FromJson, Debug)
