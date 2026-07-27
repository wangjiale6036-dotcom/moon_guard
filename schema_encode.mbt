///|
fn kind_schema_name(value : ValueKind) -> String {
  match value {
    AnyValue => "any"
    NullValue => "null"
    BooleanValue => "boolean"
    NumberValue => "number"
    IntegerValue => "integer"
    StringValue => "string"
    ArrayValue => "array"
    ObjectValue => "object"
  }
}

///|
fn object_copy(source : Map[String, Json]) -> Map[String, Json] {
  let result : Map[String, Json] = Map([])
  for key, value in source {
    result[key] = value
  }
  result
}

///|
fn schema_with_field(schema : Json, key : String, value : Json) -> Json {
  match schema {
    Object(object) => {
      let result = object_copy(object)
      result[key] = value
      Json::object(result)
    }
    _ => {
      let result : Map[String, Json] = { "allOf": Json::array([schema]) }
      result[key] = value
      Json::object(result)
    }
  }
}

///|
fn add_optional_string(
  object : Map[String, Json],
  key : String,
  value : String?,
) -> Unit {
  match value {
    Some(text) => object[key] = text.to_json()
    None => ()
  }
}

///|
fn add_optional_int(
  object : Map[String, Json],
  key : String,
  value : Int?,
) -> Unit {
  match value {
    Some(number) => object[key] = number.to_json()
    None => ()
  }
}

///|
fn add_optional_number(
  object : Map[String, Json],
  key : String,
  value : Double?,
) -> Unit {
  match value {
    Some(number) => object[key] = number.to_json()
    None => ()
  }
}

///|
fn encode_string_policy(policy : StringPolicy) -> Json {
  let object : Map[String, Json] = { "type": "string".to_json() }
  add_optional_int(object, "minLength", policy.min_length)
  add_optional_int(object, "maxLength", policy.max_length)
  add_optional_int(object, "length", policy.exact_length)
  add_optional_string(object, "prefix", policy.prefix)
  add_optional_string(object, "suffix", policy.suffix)
  add_optional_string(object, "containsText", policy.contains)
  add_optional_string(object, "pattern", policy.pattern)
  add_optional_string(object, "format", policy.format)
  if !policy.allowed.is_empty() {
    object["allowed"] = policy.allowed.to_json()
  }
  if !policy.forbidden.is_empty() {
    object["forbidden"] = policy.forbidden.to_json()
  }
  if policy.ascii_only {
    object["asciiOnly"] = true.to_json()
  }
  if policy.non_blank {
    object["nonBlank"] = true.to_json()
  }
  if !policy.case_sensitive {
    object["caseSensitive"] = false.to_json()
  }
  Json::object(object)
}

///|
fn encode_number_policy(policy : NumberPolicy) -> Json {
  let object : Map[String, Json] = {
    "type": if policy.integer_only {
      "integer".to_json()
    } else {
      "number".to_json()
    },
  }
  add_optional_number(object, "minimum", policy.minimum)
  add_optional_number(object, "maximum", policy.maximum)
  add_optional_number(object, "exclusiveMinimum", policy.exclusive_minimum)
  add_optional_number(object, "exclusiveMaximum", policy.exclusive_maximum)
  add_optional_number(object, "multipleOf", policy.multiple_of)
  if policy.non_zero {
    object["nonZero"] = true.to_json()
  }
  if policy.positive {
    object["positive"] = true.to_json()
  }
  if policy.negative {
    object["negative"] = true.to_json()
  }
  Json::object(object)
}

///|
fn encode_array_policy(policy : ArrayPolicy) -> Json {
  let object : Map[String, Json] = { "type": "array".to_json() }
  match policy.items {
    Some(rule) => object["items"] = encode_rule_value(rule)
    None => ()
  }
  if !policy.prefix_items.is_empty() {
    object["prefixItems"] = Json::array(
      policy.prefix_items.map(encode_rule_value),
    )
  }
  add_optional_int(object, "minItems", policy.min_items)
  add_optional_int(object, "maxItems", policy.max_items)
  if policy.unique_items {
    object["uniqueItems"] = true.to_json()
  }
  match policy.contains {
    Some(rule) => {
      object["contains"] = encode_rule_value(rule)
      if policy.min_contains != 1 {
        object["minContains"] = policy.min_contains.to_json()
      }
      add_optional_int(object, "maxContains", policy.max_contains)
    }
    None => ()
  }
  Json::object(object)
}

///|
fn encode_string_groups(groups : Array[Array[String]]) -> Json {
  Json::array(groups.map(group => group.to_json()))
}

///|
fn encode_object_policy(policy : ObjectPolicy) -> Json {
  let object : Map[String, Json] = { "type": "object".to_json() }
  let properties : Map[String, Json] = Map([])
  let required : Array[String] = []
  let deprecated : Array[String] = []
  for property in policy.properties {
    properties[property.name] = encode_rule_value(property.rule)
    if property.required {
      required.push(property.name)
    }
    if property.deprecated {
      deprecated.push(property.name)
    }
  }
  if !properties.is_empty() {
    object["properties"] = Json::object(properties)
  }
  if !required.is_empty() {
    object["required"] = required.to_json()
  }
  if !deprecated.is_empty() {
    object["deprecatedProperties"] = deprecated.to_json()
  }
  match policy.additional_rule {
    Some(rule) => object["additionalProperties"] = encode_rule_value(rule)
    None =>
      if !policy.allow_additional {
        object["additionalProperties"] = false.to_json()
      }
  }
  add_optional_int(object, "minProperties", policy.min_properties)
  add_optional_int(object, "maxProperties", policy.max_properties)
  if !policy.dependencies.is_empty() {
    let dependencies : Map[String, Json] = Map([])
    for dependency in policy.dependencies {
      dependencies[dependency.property] = dependency.requires.to_json()
    }
    object["dependentRequired"] = Json::object(dependencies)
  }
  if !policy.mutually_exclusive.is_empty() {
    object["mutuallyExclusive"] = encode_string_groups(
      policy.mutually_exclusive,
    )
  }
  if !policy.at_least_one.is_empty() {
    object["atLeastOne"] = encode_string_groups(policy.at_least_one)
  }
  Json::object(object)
}

///|
fn encode_predicate(predicate : Predicate) -> Json {
  match predicate {
    Always => true.to_json()
    Never => false.to_json()
    Exists(path) =>
      Json::object({ "path": path.to_json(), "exists": true.to_json() })
    Missing(path) =>
      Json::object({ "path": path.to_json(), "exists": false.to_json() })
    Equals(path, value) =>
      Json::object({ "path": path.to_json(), "equals": value })
    KindIs(path, value) =>
      Json::object({
        "path": path.to_json(),
        "kind": kind_schema_name(value).to_json(),
      })
    Validates(path, rule) =>
      Json::object({
        "path": path.to_json(),
        "validates": encode_rule_value(rule),
      })
    AllPredicates(values) =>
      Json::object({ "all": Json::array(values.map(encode_predicate)) })
    AnyPredicate(values) =>
      Json::object({ "any": Json::array(values.map(encode_predicate)) })
    NotPredicate(value) => Json::object({ "not": encode_predicate(value) })
  }
}

///|
fn encode_combinator(keyword : String, rules : Array[Rule]) -> Json {
  let object : Map[String, Json] = Map([])
  object[keyword] = Json::array(rules.map(encode_rule_value))
  Json::object(object)
}

///|
fn encode_rule_value(rule : Rule) -> Json {
  match rule {
    Accept => true.to_json()
    Reject(message) => Json::object({ "reject": message.to_json() })
    Kind(value) => Json::object({ "type": kind_schema_name(value).to_json() })
    StringMatches(policy) => encode_string_policy(policy)
    NumberMatches(policy) => encode_number_policy(policy)
    ArrayMatches(policy) => encode_array_policy(policy)
    ObjectMatches(policy) => encode_object_policy(policy)
    EqualsValue(value) => Json::object({ "const": value })
    InValues(values) => Json::object({ "enum": Json::array(values) })
    AllOf(rules) => encode_combinator("allOf", rules)
    AnyOf(rules) => encode_combinator("anyOf", rules)
    OneOf(rules) => encode_combinator("oneOf", rules)
    NoneOf(rules) => encode_combinator("noneOf", rules)
    NotRule(child) => Json::object({ "not": encode_rule_value(child) })
    Nullable(child) =>
      schema_with_field(encode_rule_value(child), "nullable", true.to_json())
    Optional(child) => Json::object({ "optional": encode_rule_value(child) })
    When(predicate, then_rule, else_rule) => {
      let object : Map[String, Json] = {
        "when": encode_predicate(predicate),
        "then": encode_rule_value(then_rule),
      }
      match else_rule {
        Some(child) => object["else"] = encode_rule_value(child)
        None => ()
      }
      Json::object(object)
    }
    AtPath(path, child) =>
      schema_with_field(encode_rule_value(child), "atPath", path.to_json())
    Named(name, description, child) => {
      let result = schema_with_field(
        encode_rule_value(child),
        "$name",
        name.to_json(),
      )
      if description.is_empty() {
        result
      } else {
        schema_with_field(result, "description", description.to_json())
      }
    }
    WarningRule(message, child) =>
      schema_with_field(encode_rule_value(child), "warning", message.to_json())
  }
}

///|
/// Export a rule using MoonGuard's dynamic JSON schema format.
pub fn rule_to_json(rule : Rule, indent? : Int = 2) -> String {
  encode_rule_value(rule).stringify(indent~)
}

///|
/// Verify that a rule survives the supported JSON round trip.
pub fn rule_round_trip(rule : Rule) -> Rule? {
  rule_from_json(rule_to_json(rule))
}
