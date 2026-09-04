///|
fn json_string_field(object : Map[String, Json], key : String) -> String? {
  match object.get(key) {
    Some(String(value)) => Some(value)
    _ => None
  }
}

///|
fn json_bool_field(object : Map[String, Json], key : String) -> Bool? {
  match object.get(key) {
    Some(True) => Some(true)
    Some(False) => Some(false)
    _ => None
  }
}

///|
fn json_number_field(object : Map[String, Json], key : String) -> Double? {
  match object.get(key) {
    Some(Number(value, ..)) => Some(value)
    _ => None
  }
}

///|
fn json_int_field(object : Map[String, Json], key : String) -> Int? {
  match json_number_field(object, key) {
    Some(value) =>
      if value == value.round() {
        Some(value.to_int())
      } else {
        None
      }
    None => None
  }
}

///|
fn json_string_array(value : Json) -> Array[String]? {
  match value {
    Array(values) => {
      let result : Array[String] = []
      for item in values {
        match item {
          String(text) => result.push(text)
          _ => return None
        }
      }
      Some(result)
    }
    _ => None
  }
}

///|
fn json_string_groups(value : Json) -> Array[Array[String]]? {
  match value {
    Array(groups) => {
      let result : Array[Array[String]] = []
      for group in groups {
        match json_string_array(group) {
          Some(names) => result.push(names)
          None => return None
        }
      }
      Some(result)
    }
    _ => None
  }
}

///|
fn kind_from_name(value : String) -> ValueKind? {
  match value {
    "any" => Some(AnyValue)
    "null" => Some(NullValue)
    "boolean" | "bool" => Some(BooleanValue)
    "number" => Some(NumberValue)
    "integer" | "int" => Some(IntegerValue)
    "string" => Some(StringValue)
    "array" => Some(ArrayValue)
    "object" => Some(ObjectValue)
    _ => None
  }
}

///|
fn parse_rule_array(
  value : Json,
  path : String,
  errors : Array[String],
  warnings : Array[String],
  depth : Int,
) -> Array[Rule]? {
  match value {
    Array(values) => {
      let result : Array[Rule] = []
      for index = 0; index < values.length(); index = index + 1 {
        match
          parse_rule_value(
            values[index],
            "\{path}/\{index}",
            errors,
            warnings,
            depth + 1,
          ) {
          Some(rule) => result.push(rule)
          None => ()
        }
      }
      if result.length() == values.length() {
        Some(result)
      } else {
        None
      }
    }
    _ => {
      errors.push("\{path}: expected an array of rules")
      None
    }
  }
}

///|
fn parse_predicate_value(
  value : Json,
  path : String,
  errors : Array[String],
  warnings : Array[String],
  depth : Int,
) -> Predicate? {
  if depth > 64 {
    errors.push("\{path}: predicate nesting is too deep")
    return None
  }
  let object = match value {
    Object(object) => object
    True => return Some(Always)
    False => return Some(Never)
    _ => {
      errors.push("\{path}: predicate must be an object or boolean")
      return None
    }
  }
  match object.get("all") {
    Some(Array(values)) => {
      let predicates : Array[Predicate] = []
      for index = 0; index < values.length(); index = index + 1 {
        match
          parse_predicate_value(
            values[index],
            "\{path}/all/\{index}",
            errors,
            warnings,
            depth + 1,
          ) {
          Some(predicate) => predicates.push(predicate)
          None => ()
        }
      }
      return Some(AllPredicates(predicates))
    }
    _ => ()
  }
  match object.get("any") {
    Some(Array(values)) => {
      let predicates : Array[Predicate] = []
      for index = 0; index < values.length(); index = index + 1 {
        match
          parse_predicate_value(
            values[index],
            "\{path}/any/\{index}",
            errors,
            warnings,
            depth + 1,
          ) {
          Some(predicate) => predicates.push(predicate)
          None => ()
        }
      }
      return Some(AnyPredicate(predicates))
    }
    _ => ()
  }
  match object.get("not") {
    Some(child) =>
      return parse_predicate_value(
        child,
        "\{path}/not",
        errors,
        warnings,
        depth + 1,
      ).map(predicate => NotPredicate(predicate))
    None => ()
  }
  let target = json_string_field(object, "path").unwrap_or("")
  match object.get("exists") {
    Some(True) => return Some(Exists(target))
    Some(False) => return Some(Missing(target))
    _ => ()
  }
  match object.get("equals") {
    Some(expected) => return Some(Equals(target, expected))
    None => ()
  }
  match json_string_field(object, "kind") {
    Some(name) =>
      match kind_from_name(name) {
        Some(expected) => return Some(KindIs(target, expected))
        None => errors.push("\{path}/kind: unknown value kind \{name}")
      }
    None => ()
  }
  match object.get("validates") {
    Some(schema) =>
      match
        parse_rule_value(
          schema,
          "\{path}/validates",
          errors,
          warnings,
          depth + 1,
        ) {
        Some(rule) => return Some(Validates(target, rule))
        None => ()
      }
    None => ()
  }
  errors.push("\{path}: predicate has no supported operator")
  None
}

///|
fn parse_string_policy(
  object : Map[String, Json],
  path : String,
  errors : Array[String],
) -> StringPolicy {
  let allowed = match object.get("allowed") {
    Some(value) =>
      json_string_array(value).unwrap_or_else(() => {
        errors.push("\{path}/allowed: expected an array of strings")
        []
      })
    None => []
  }
  let forbidden = match object.get("forbidden") {
    Some(value) =>
      json_string_array(value).unwrap_or_else(() => {
        errors.push("\{path}/forbidden: expected an array of strings")
        []
      })
    None => []
  }
  {
    min_length: json_int_field(object, "minLength"),
    max_length: json_int_field(object, "maxLength"),
    exact_length: json_int_field(object, "length"),
    prefix: json_string_field(object, "prefix"),
    suffix: json_string_field(object, "suffix"),
    contains: json_string_field(object, "containsText"),
    pattern: json_string_field(object, "pattern"),
    format: json_string_field(object, "format"),
    allowed,
    forbidden,
    ascii_only: json_bool_field(object, "asciiOnly").unwrap_or(false),
    non_blank: json_bool_field(object, "nonBlank").unwrap_or(false),
    case_sensitive: json_bool_field(object, "caseSensitive").unwrap_or(true),
  }
}

///|
fn has_string_keywords(object : Map[String, Json]) -> Bool {
  for
    key in [
      "minLength", "maxLength", "length", "prefix", "suffix", "containsText", "pattern",
      "format", "allowed", "forbidden", "asciiOnly", "nonBlank", "caseSensitive",
    ] {
    if object.contains(key) {
      return true
    }
  }
  false
}

///|
fn parse_number_policy(object : Map[String, Json]) -> NumberPolicy {
  {
    minimum: json_number_field(object, "minimum"),
    maximum: json_number_field(object, "maximum"),
    exclusive_minimum: json_number_field(object, "exclusiveMinimum"),
    exclusive_maximum: json_number_field(object, "exclusiveMaximum"),
    multiple_of: json_number_field(object, "multipleOf"),
    integer_only: json_bool_field(object, "integer").unwrap_or(false),
    non_zero: json_bool_field(object, "nonZero").unwrap_or(false),
    positive: json_bool_field(object, "positive").unwrap_or(false),
    negative: json_bool_field(object, "negative").unwrap_or(false),
  }
}

///|
fn has_number_keywords(object : Map[String, Json]) -> Bool {
  for
    key in [
      "minimum", "maximum", "exclusiveMinimum", "exclusiveMaximum", "multipleOf",
      "integer", "nonZero", "positive", "negative",
    ] {
    if object.contains(key) {
      return true
    }
  }
  false
}

///|
fn parse_array_policy(
  object : Map[String, Json],
  path : String,
  errors : Array[String],
  warnings : Array[String],
  depth : Int,
) -> ArrayPolicy {
  let items = match object.get("items") {
    Some(value) =>
      parse_rule_value(value, "\{path}/items", errors, warnings, depth + 1)
    None => None
  }
  let prefix_items = match object.get("prefixItems") {
    Some(value) =>
      parse_rule_array(
        value,
        "\{path}/prefixItems",
        errors,
        warnings,
        depth + 1,
      ).unwrap_or([])
    None => []
  }
  let contains = match object.get("contains") {
    Some(value) =>
      parse_rule_value(value, "\{path}/contains", errors, warnings, depth + 1)
    None => None
  }
  {
    items,
    prefix_items,
    min_items: json_int_field(object, "minItems"),
    max_items: json_int_field(object, "maxItems"),
    unique_items: json_bool_field(object, "uniqueItems").unwrap_or(false),
    contains,
    min_contains: json_int_field(object, "minContains").unwrap_or(1),
    max_contains: json_int_field(object, "maxContains"),
  }
}

///|
fn has_array_keywords(object : Map[String, Json]) -> Bool {
  for
    key in [
      "items", "prefixItems", "minItems", "maxItems", "uniqueItems", "contains",
      "minContains", "maxContains",
    ] {
    if object.contains(key) {
      return true
    }
  }
  false
}

///|
fn parse_dependencies(
  value : Json,
  path : String,
  errors : Array[String],
) -> Array[PropertyDependency] {
  let object = match value {
    Object(object) => object
    _ => {
      errors.push("\{path}: expected an object")
      return []
    }
  }
  let result : Array[PropertyDependency] = []
  for key, child in object {
    match json_string_array(child) {
      Some(required) => result.push(dependency(key, required))
      None =>
        errors.push(
          "\{path}/\{escape_pointer_segment(key)}: expected an array of strings",
        )
    }
  }
  result
}

///|
fn parse_object_policy(
  object : Map[String, Json],
  path : String,
  errors : Array[String],
  warnings : Array[String],
  depth : Int,
) -> ObjectPolicy {
  let required = match object.get("required") {
    Some(value) =>
      json_string_array(value).unwrap_or_else(() => {
        errors.push("\{path}/required: expected an array of strings")
        []
      })
    None => []
  }
  let deprecated = match object.get("deprecatedProperties") {
    Some(value) => json_string_array(value).unwrap_or([])
    None => []
  }
  let properties : Array[PropertyRule] = []
  match object.get("properties") {
    Some(Object(values)) =>
      for key, schema in values {
        match
          parse_rule_value(
            schema,
            "\{path}/properties/\{escape_pointer_segment(key)}",
            errors,
            warnings,
            depth + 1,
          ) {
          Some(rule) =>
            properties.push(
              property(
                key,
                rule,
                required=required.contains(key),
                deprecated=deprecated.contains(key),
              ),
            )
          None => ()
        }
      }
    Some(_) => errors.push("\{path}/properties: expected an object")
    None => ()
  }
  for name in required {
    let mut found = false
    for property in properties {
      if property.name == name {
        found = true
      }
    }
    if !found {
      warnings.push("\{path}/required: \{name} has no property schema")
      properties.push(property(name, any_value()))
    }
  }
  let mut allow_additional = true
  let mut additional_rule : Rule? = None
  match object.get("additionalProperties") {
    Some(True) => allow_additional = true
    Some(False) => allow_additional = false
    Some(schema) => {
      allow_additional = true
      additional_rule = parse_rule_value(
        schema,
        "\{path}/additionalProperties",
        errors,
        warnings,
        depth + 1,
      )
    }
    None => ()
  }
  let dependencies = match object.get("dependentRequired") {
    Some(value) =>
      parse_dependencies(value, "\{path}/dependentRequired", errors)
    None => []
  }
  let mutually_exclusive = match object.get("mutuallyExclusive") {
    Some(value) =>
      json_string_groups(value).unwrap_or_else(() => {
        errors.push(
          "\{path}/mutuallyExclusive: expected an array of string arrays",
        )
        []
      })
    None => []
  }
  let at_least_one = match object.get("atLeastOne") {
    Some(value) =>
      json_string_groups(value).unwrap_or_else(() => {
        errors.push("\{path}/atLeastOne: expected an array of string arrays")
        []
      })
    None => []
  }
  {
    properties,
    allow_additional,
    additional_rule,
    min_properties: json_int_field(object, "minProperties"),
    max_properties: json_int_field(object, "maxProperties"),
    dependencies,
    mutually_exclusive,
    at_least_one,
  }
}

///|
fn has_object_keywords(object : Map[String, Json]) -> Bool {
  for
    key in [
      "properties", "required", "deprecatedProperties", "additionalProperties", "minProperties",
      "maxProperties", "dependentRequired", "mutuallyExclusive", "atLeastOne",
    ] {
    if object.contains(key) {
      return true
    }
  }
  false
}

///|
fn combine_rules(rules : Array[Rule]) -> Rule {
  if rules.is_empty() {
    Accept
  } else if rules.length() == 1 {
    rules[0]
  } else {
    AllOf(rules)
  }
}

///|
fn parse_rule_value(
  value : Json,
  path : String,
  errors : Array[String],
  warnings : Array[String],
  depth : Int,
) -> Rule? {
  if depth > 64 {
    errors.push("\{path}: rule nesting is too deep")
    return None
  }
  match value {
    True => return Some(Accept)
    False => return Some(Reject("boolean false schema rejects every value"))
    _ => ()
  }
  let object = match value {
    Object(object) => object
    _ => {
      errors.push("\{path}: rule must be an object or boolean")
      return None
    }
  }
  let rules : Array[Rule] = []
  match json_string_field(object, "reject") {
    Some(message) => rules.push(Reject(message))
    None => ()
  }
  match json_string_field(object, "type") {
    Some(name) =>
      match kind_from_name(name) {
        Some(expected) => rules.push(Kind(expected))
        None => errors.push("\{path}/type: unsupported type \{name}")
      }
    None => ()
  }
  match object.get("const") {
    Some(expected) => rules.push(EqualsValue(expected))
    None => ()
  }
  match object.get("enum") {
    Some(Array(values)) => rules.push(InValues(values))
    Some(_) => errors.push("\{path}/enum: expected an array")
    None => ()
  }
  if has_string_keywords(object) {
    rules.push(StringMatches(parse_string_policy(object, path, errors)))
  }
  if has_number_keywords(object) {
    rules.push(NumberMatches(parse_number_policy(object)))
  }
  if has_array_keywords(object) {
    rules.push(
      ArrayMatches(parse_array_policy(object, path, errors, warnings, depth)),
    )
  }
  if has_object_keywords(object) {
    rules.push(
      ObjectMatches(parse_object_policy(object, path, errors, warnings, depth)),
    )
  }
  match object.get("allOf") {
    Some(child) =>
      match
        parse_rule_array(child, "\{path}/allOf", errors, warnings, depth + 1) {
        Some(children) => rules.push(AllOf(children))
        None => ()
      }
    None => ()
  }
  match object.get("anyOf") {
    Some(child) =>
      match
        parse_rule_array(child, "\{path}/anyOf", errors, warnings, depth + 1) {
        Some(children) => rules.push(AnyOf(children))
        None => ()
      }
    None => ()
  }
  match object.get("oneOf") {
    Some(child) =>
      match
        parse_rule_array(child, "\{path}/oneOf", errors, warnings, depth + 1) {
        Some(children) => rules.push(OneOf(children))
        None => ()
      }
    None => ()
  }
  match object.get("noneOf") {
    Some(child) =>
      match
        parse_rule_array(child, "\{path}/noneOf", errors, warnings, depth + 1) {
        Some(children) => rules.push(NoneOf(children))
        None => ()
      }
    None => ()
  }
  match object.get("not") {
    Some(child) =>
      match
        parse_rule_value(child, "\{path}/not", errors, warnings, depth + 1) {
        Some(rule) => rules.push(NotRule(rule))
        None => ()
      }
    None => ()
  }
  match object.get("optional") {
    Some(child) =>
      match
        parse_rule_value(child, "\{path}/optional", errors, warnings, depth + 1) {
        Some(rule) => rules.push(Optional(rule))
        None => ()
      }
    None => ()
  }
  match object.get("when") {
    Some(predicate_value) => {
      let predicate = parse_predicate_value(
        predicate_value,
        "\{path}/when",
        errors,
        warnings,
        depth + 1,
      )
      let then_rule = match object.get("then") {
        Some(child) =>
          parse_rule_value(child, "\{path}/then", errors, warnings, depth + 1)
        None => {
          errors.push("\{path}/then: conditional schema requires then")
          None
        }
      }
      let else_rule = match object.get("else") {
        Some(child) =>
          parse_rule_value(child, "\{path}/else", errors, warnings, depth + 1)
        None => None
      }
      match (predicate, then_rule) {
        (Some(predicate), Some(then_rule)) =>
          rules.push(When(predicate, then_rule, else_rule))
        _ => ()
      }
    }
    None => ()
  }
  let mut result = combine_rules(rules)
  if json_bool_field(object, "nullable").unwrap_or(false) {
    result = Nullable(result)
  }
  match json_string_field(object, "atPath") {
    Some(target) => result = AtPath(target, result)
    None => ()
  }
  match json_string_field(object, "warning") {
    Some(message) => result = WarningRule(message, result)
    None => ()
  }
  match json_string_field(object, "$name") {
    Some(name) =>
      result = Named(
        name,
        json_string_field(object, "description").unwrap_or(""),
        result,
      )
    None => ()
  }
  Some(result)
}

///|
/// Parse one dynamic JSON rule document. The accepted format resembles a
/// practical JSON Schema subset with MoonGuard extensions for `when`,
/// `atPath`, `warning`, dependencies and property groups.
pub fn parse_rule_document(text : String) -> RuleParseResult {
  let value = @json.parse(text) catch {
    _ =>
      return {
        rule: None,
        errors: ["document is not valid JSON"],
        warnings: [],
      }
  }
  let errors : Array[String] = []
  let warnings : Array[String] = []
  let rule = parse_rule_value(value, "", errors, warnings, 0)
  { rule: if errors.is_empty() { rule } else { None }, errors, warnings, }
}

///|
pub fn rule_from_json(text : String) -> Rule? {
  parse_rule_document(text).rule
}
