///|
/// Safe runtime defaults for API validation.
pub fn default_validation_options() -> ValidationOptions {
  {
    fail_fast: false,
    max_issues: 100,
    max_depth: 64,
    max_rule_visits: 100000,
    include_value_preview: true,
    include_warnings: true,
    path_style: "json-pointer",
  }
}

///|
pub fn new_validator(
  rule : Rule,
  options? : ValidationOptions = default_validation_options(),
) -> Validator {
  { rule, options, }
}

///|
/// A rule that accepts every JSON value.
pub fn any_value() -> Rule {
  Accept
}

///|
/// A rule that always emits an error with the supplied message.
pub fn reject(message? : String = "value is rejected") -> Rule {
  Reject(message)
}

///|
/// Require one JSON value category.
pub fn kind(value : ValueKind) -> Rule {
  Kind(value)
}

///|
pub fn null_value() -> Rule {
  Kind(NullValue)
}

///|
pub fn boolean() -> Rule {
  Kind(BooleanValue)
}

///|
pub fn integer() -> Rule {
  NumberMatches({ ..default_number_policy(), integer_only: true, })
}

///|
pub fn number() -> Rule {
  NumberMatches(default_number_policy())
}

///|
pub fn string() -> Rule {
  StringMatches(default_string_policy())
}

///|
pub fn array() -> Rule {
  ArrayMatches(default_array_policy())
}

///|
pub fn object() -> Rule {
  ObjectMatches(default_object_policy())
}

///|
pub fn default_string_policy() -> StringPolicy {
  {
    min_length: None,
    max_length: None,
    exact_length: None,
    prefix: None,
    suffix: None,
    contains: None,
    pattern: None,
    format: None,
    allowed: [],
    forbidden: [],
    ascii_only: false,
    non_blank: false,
    case_sensitive: true,
  }
}

///|
pub fn string_rule(
  min_length? : Int? = None,
  max_length? : Int? = None,
  exact_length? : Int? = None,
  prefix? : String? = None,
  suffix? : String? = None,
  contains? : String? = None,
  pattern? : String? = None,
  format? : String? = None,
  allowed? : Array[String] = [],
  forbidden? : Array[String] = [],
  ascii_only? : Bool = false,
  non_blank? : Bool = false,
  case_sensitive? : Bool = true,
) -> Rule {
  StringMatches({
    min_length,
    max_length,
    exact_length,
    prefix,
    suffix,
    contains,
    pattern,
    format,
    allowed,
    forbidden,
    ascii_only,
    non_blank,
    case_sensitive,
  })
}

///|
pub fn default_number_policy() -> NumberPolicy {
  {
    minimum: None,
    maximum: None,
    exclusive_minimum: None,
    exclusive_maximum: None,
    multiple_of: None,
    integer_only: false,
    non_zero: false,
    positive: false,
    negative: false,
  }
}

///|
pub fn number_rule(
  minimum? : Double? = None,
  maximum? : Double? = None,
  exclusive_minimum? : Double? = None,
  exclusive_maximum? : Double? = None,
  multiple_of? : Double? = None,
  integer_only? : Bool = false,
  non_zero? : Bool = false,
  positive? : Bool = false,
  negative? : Bool = false,
) -> Rule {
  NumberMatches({
    minimum,
    maximum,
    exclusive_minimum,
    exclusive_maximum,
    multiple_of,
    integer_only,
    non_zero,
    positive,
    negative,
  })
}

///|
pub fn positive_number() -> Rule {
  number_rule(positive=true)
}

///|
pub fn negative_number() -> Rule {
  number_rule(negative=true)
}

///|
pub fn range(minimum : Double, maximum : Double) -> Rule {
  number_rule(minimum=Some(minimum), maximum=Some(maximum))
}

///|
pub fn default_array_policy() -> ArrayPolicy {
  {
    items: None,
    prefix_items: [],
    min_items: None,
    max_items: None,
    unique_items: false,
    contains: None,
    min_contains: 1,
    max_contains: None,
  }
}

///|
pub fn array_rule(
  items? : Rule? = None,
  prefix_items? : Array[Rule] = [],
  min_items? : Int? = None,
  max_items? : Int? = None,
  unique_items? : Bool = false,
  contains? : Rule? = None,
  min_contains? : Int = 1,
  max_contains? : Int? = None,
) -> Rule {
  ArrayMatches({
    items,
    prefix_items,
    min_items,
    max_items,
    unique_items,
    contains,
    min_contains,
    max_contains,
  })
}

///|
pub fn list_of(item_rule : Rule) -> Rule {
  array_rule(items=Some(item_rule))
}

///|
pub fn non_empty_list(item_rule : Rule) -> Rule {
  array_rule(items=Some(item_rule), min_items=Some(1))
}

///|
pub fn tuple(items : Array[Rule]) -> Rule {
  array_rule(
    prefix_items=items,
    min_items=Some(items.length()),
    max_items=Some(items.length()),
  )
}

///|
pub fn default_object_policy() -> ObjectPolicy {
  {
    properties: [],
    allow_additional: true,
    additional_rule: None,
    min_properties: None,
    max_properties: None,
    dependencies: [],
    mutually_exclusive: [],
    at_least_one: [],
  }
}

///|
pub fn property(
  name : String,
  rule : Rule,
  required? : Bool = true,
  deprecated? : Bool = false,
  description? : String = "",
) -> PropertyRule {
  { name, rule, required, deprecated, description, }
}

///|
pub fn optional_property(
  name : String,
  rule : Rule,
  description? : String = "",
) -> PropertyRule {
  property(name, rule, required=false, description~)
}

///|
pub fn deprecated_property(
  name : String,
  rule : Rule,
  required? : Bool = false,
  description? : String = "",
) -> PropertyRule {
  property(name, rule, required~, deprecated=true, description~)
}

///|
pub fn dependency(
  property : String,
  requires : Array[String],
) -> PropertyDependency {
  { property, requires, }
}

///|
pub fn object_rule(
  properties? : Array[PropertyRule] = [],
  allow_additional? : Bool = true,
  additional_rule? : Rule? = None,
  min_properties? : Int? = None,
  max_properties? : Int? = None,
  dependencies? : Array[PropertyDependency] = [],
  mutually_exclusive? : Array[Array[String]] = [],
  at_least_one? : Array[Array[String]] = [],
) -> Rule {
  ObjectMatches({
    properties,
    allow_additional,
    additional_rule,
    min_properties,
    max_properties,
    dependencies,
    mutually_exclusive,
    at_least_one,
  })
}

///|
pub fn strict_object(properties : Array[PropertyRule]) -> Rule {
  object_rule(properties~, allow_additional=false)
}

///|
pub fn equals(expected : Json) -> Rule {
  EqualsValue(expected)
}

///|
pub fn literal_string(expected : String) -> Rule {
  EqualsValue(expected.to_json())
}

///|
pub fn literal_number(expected : Double) -> Rule {
  EqualsValue(expected.to_json())
}

///|
pub fn one_of_values(values : Array[Json]) -> Rule {
  InValues(values)
}

///|
pub fn one_of_strings(values : Array[String]) -> Rule {
  InValues(values.map(value => value.to_json()))
}

///|
pub fn all_of(rules : Array[Rule]) -> Rule {
  AllOf(rules)
}

///|
pub fn any_of(rules : Array[Rule]) -> Rule {
  AnyOf(rules)
}

///|
pub fn exactly_one_of(rules : Array[Rule]) -> Rule {
  OneOf(rules)
}

///|
pub fn none_of(rules : Array[Rule]) -> Rule {
  NoneOf(rules)
}

///|
pub fn not_rule(rule : Rule) -> Rule {
  NotRule(rule)
}

///|
pub fn nullable(rule : Rule) -> Rule {
  Nullable(rule)
}

///|
pub fn optional(rule : Rule) -> Rule {
  Optional(rule)
}

///|
pub fn when(
  predicate : Predicate,
  then_rule : Rule,
  else_rule? : Rule? = None,
) -> Rule {
  When(predicate, then_rule, else_rule)
}

///|
pub fn at_path(path : String, rule : Rule) -> Rule {
  AtPath(path, rule)
}

///|
pub fn named(name : String, rule : Rule, description? : String = "") -> Rule {
  Named(name, description, rule)
}

///|
pub fn warning(message : String, rule : Rule) -> Rule {
  WarningRule(message, rule)
}

///|
pub fn ValidationOptions::with_fail_fast(
  self : ValidationOptions,
  enabled : Bool,
) -> ValidationOptions {
  { ..self, fail_fast: enabled, }
}

///|
pub fn ValidationOptions::with_max_issues(
  self : ValidationOptions,
  count : Int,
) -> ValidationOptions {
  { ..self, max_issues: count.max(1), }
}

///|
pub fn ValidationOptions::with_max_depth(
  self : ValidationOptions,
  depth : Int,
) -> ValidationOptions {
  { ..self, max_depth: depth.max(1), }
}

///|
pub fn ValidationOptions::with_rule_budget(
  self : ValidationOptions,
  visits : Int,
) -> ValidationOptions {
  { ..self, max_rule_visits: visits.max(1), }
}

///|
pub fn ValidationOptions::with_value_preview(
  self : ValidationOptions,
  enabled : Bool,
) -> ValidationOptions {
  { ..self, include_value_preview: enabled, }
}

///|
pub fn ValidationOptions::with_warnings(
  self : ValidationOptions,
  enabled : Bool,
) -> ValidationOptions {
  { ..self, include_warnings: enabled, }
}

///|
pub fn ValidationOptions::with_path_style(
  self : ValidationOptions,
  style : String,
) -> ValidationOptions {
  { ..self, path_style: style, }
}
