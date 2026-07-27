///|
priv struct ValidationContext {
  options : ValidationOptions
  issues : Array[ValidationIssue]
  mut rule_visits : Int
  mut values_checked : Int
  mut maximum_depth : Int
  mut error_count : Int
  mut warning_count : Int
  mut info_count : Int
  mut truncated : Bool
}

///|
fn new_context(options : ValidationOptions) -> ValidationContext {
  {
    options,
    issues: [],
    rule_visits: 0,
    values_checked: 0,
    maximum_depth: 0,
    error_count: 0,
    warning_count: 0,
    info_count: 0,
    truncated: false,
  }
}

///|
fn context_should_stop(context : ValidationContext) -> Bool {
  context.truncated ||
  (context.options.fail_fast && context.error_count > 0) ||
  context.issues.length() >= context.options.max_issues
}

///|
fn add_issue(
  context : ValidationContext,
  path : String,
  code : String,
  keyword : String,
  message : String,
  severity : Severity,
  rule_name : String,
  value : Json,
) -> Unit {
  if severity == Warning && !context.options.include_warnings {
    return
  }
  if context.issues.length() >= context.options.max_issues {
    context.truncated = true
    return
  }
  let preview = if context.options.include_value_preview {
    json_preview(value)
  } else {
    ""
  }
  context.issues.push({
    path,
    code,
    keyword,
    message,
    severity,
    rule_name,
    value_preview: preview,
  })
  match severity {
    Error => context.error_count += 1
    Warning => context.warning_count += 1
    Info => context.info_count += 1
  }
}

///|
fn visit_rule(
  context : ValidationContext,
  value : Json,
  path : String,
  depth : Int,
  rule_name : String,
) -> Bool {
  context.rule_visits += 1
  context.values_checked += 1
  context.maximum_depth = context.maximum_depth.max(depth)
  if depth > context.options.max_depth {
    add_issue(
      context,
      path,
      "limit.depth",
      "maxDepth",
      "validation depth exceeds configured maximum",
      Error,
      rule_name,
      value,
    )
    context.truncated = true
    return false
  }
  if context.rule_visits > context.options.max_rule_visits {
    add_issue(
      context,
      path,
      "limit.rule_visits",
      "maxRuleVisits",
      "validation rule-visit budget was exhausted",
      Error,
      rule_name,
      value,
    )
    context.truncated = true
    return false
  }
  true
}

///|
fn report_from_context(context : ValidationContext) -> ValidationReport {
  {
    valid: context.error_count == 0,
    issues: context.issues,
    stats: {
      rule_visits: context.rule_visits,
      values_checked: context.values_checked,
      maximum_depth: context.maximum_depth,
      error_count: context.error_count,
      warning_count: context.warning_count,
      info_count: context.info_count,
      truncated: context.truncated,
    },
  }
}

///|
fn silent_match(
  root : Json,
  value : Json,
  rule : Rule,
  options : ValidationOptions,
  depth : Int,
) -> Bool {
  let quiet = {
    ..options,
    fail_fast: false,
    max_issues: options.max_issues.max(32),
    include_warnings: false,
  }
  let context = new_context(quiet)
  ignore(
    validate_rule(
      context,
      root,
      value,
      rule,
      root_path(options.path_style),
      depth,
      "",
    ),
  )
  context.error_count == 0 && !context.truncated
}

///|
fn validate_kind_rule(
  context : ValidationContext,
  value : Json,
  expected : ValueKind,
  path : String,
  rule_name : String,
) -> Bool {
  if value_matches_kind(value, expected) {
    true
  } else {
    add_issue(
      context,
      path,
      "type.mismatch",
      "type",
      "expected \{kind_name(expected)}, got \{kind_name(json_kind(value))}",
      Error,
      rule_name,
      value,
    )
    false
  }
}

///|
fn string_in_list(
  value : String,
  values : Array[String],
  case_sensitive : Bool,
) -> Bool {
  for candidate in values {
    if text_equal(value, candidate, case_sensitive) {
      return true
    }
  }
  false
}

///|
fn validate_string_policy(
  context : ValidationContext,
  value : Json,
  policy : StringPolicy,
  path : String,
  rule_name : String,
) -> Bool {
  let text = match value {
    String(text) => text
    _ => {
      ignore(validate_kind_rule(context, value, StringValue, path, rule_name))
      return false
    }
  }
  let mut valid = true
  let length = text.char_length()
  match policy.min_length {
    Some(minimum) =>
      if length < minimum {
        add_issue(
          context,
          path,
          "string.too_short",
          "minLength",
          "string length \{length} is below \{minimum}",
          Error,
          rule_name,
          value,
        )
        valid = false
      }
    None => ()
  }
  match policy.max_length {
    Some(maximum) =>
      if length > maximum {
        add_issue(
          context,
          path,
          "string.too_long",
          "maxLength",
          "string length \{length} exceeds \{maximum}",
          Error,
          rule_name,
          value,
        )
        valid = false
      }
    None => ()
  }
  match policy.exact_length {
    Some(expected) =>
      if length != expected {
        add_issue(
          context,
          path,
          "string.length",
          "length",
          "string length must be exactly \{expected}",
          Error,
          rule_name,
          value,
        )
        valid = false
      }
    None => ()
  }
  match policy.prefix {
    Some(prefix) =>
      if !text_has_prefix(text, prefix, policy.case_sensitive) {
        add_issue(
          context,
          path,
          "string.prefix",
          "prefix",
          "string must start with \{prefix}",
          Error,
          rule_name,
          value,
        )
        valid = false
      }
    None => ()
  }
  match policy.suffix {
    Some(suffix) =>
      if !text_has_suffix(text, suffix, policy.case_sensitive) {
        add_issue(
          context,
          path,
          "string.suffix",
          "suffix",
          "string must end with \{suffix}",
          Error,
          rule_name,
          value,
        )
        valid = false
      }
    None => ()
  }
  match policy.contains {
    Some(needle) =>
      if !text_contains(text, needle, policy.case_sensitive) {
        add_issue(
          context,
          path,
          "string.contains",
          "contains",
          "string must contain \{needle}",
          Error,
          rule_name,
          value,
        )
        valid = false
      }
    None => ()
  }
  match policy.pattern {
    Some(pattern) =>
      if !glob_matches(pattern, text, case_sensitive=policy.case_sensitive) {
        add_issue(
          context,
          path,
          "string.pattern",
          "pattern",
          "string does not match glob pattern \{pattern}",
          Error,
          rule_name,
          value,
        )
        valid = false
      }
    None => ()
  }
  match policy.format {
    Some(format) =>
      if !validate_format(text, format) {
        add_issue(
          context,
          path,
          "string.format",
          "format",
          "string is not a valid \{format}",
          Error,
          rule_name,
          value,
        )
        valid = false
      }
    None => ()
  }
  if !policy.allowed.is_empty() &&
    !string_in_list(text, policy.allowed, policy.case_sensitive) {
    add_issue(
      context,
      path,
      "string.not_allowed",
      "allowed",
      "string is not in the allowed set",
      Error,
      rule_name,
      value,
    )
    valid = false
  }
  if string_in_list(text, policy.forbidden, policy.case_sensitive) {
    add_issue(
      context,
      path,
      "string.forbidden",
      "forbidden",
      "string is in the forbidden set",
      Error,
      rule_name,
      value,
    )
    valid = false
  }
  if policy.ascii_only {
    for char in text {
      if char.to_int() > 127 {
        add_issue(
          context,
          path,
          "string.non_ascii",
          "asciiOnly",
          "string must contain ASCII characters only",
          Error,
          rule_name,
          value,
        )
        valid = false
        break
      }
    }
  }
  if policy.non_blank && text.trim().is_empty() {
    add_issue(
      context,
      path,
      "string.blank",
      "nonBlank",
      "string must contain a non-whitespace character",
      Error,
      rule_name,
      value,
    )
    valid = false
  }
  valid
}

///|
fn multiple_matches(value : Double, divisor : Double) -> Bool {
  if divisor == 0.0 {
    return false
  }
  let quotient = value / divisor
  (quotient - quotient.round()).abs() <= 0.000000001
}

///|
fn validate_number_policy(
  context : ValidationContext,
  value : Json,
  policy : NumberPolicy,
  path : String,
  rule_name : String,
) -> Bool {
  let number = match value {
    Number(number, ..) => number
    _ => {
      ignore(validate_kind_rule(context, value, NumberValue, path, rule_name))
      return false
    }
  }
  let mut valid = true
  match policy.minimum {
    Some(minimum) =>
      if number < minimum {
        add_issue(
          context,
          path,
          "number.minimum",
          "minimum",
          "number must be at least \{minimum}",
          Error,
          rule_name,
          value,
        )
        valid = false
      }
    None => ()
  }
  match policy.maximum {
    Some(maximum) =>
      if number > maximum {
        add_issue(
          context,
          path,
          "number.maximum",
          "maximum",
          "number must be at most \{maximum}",
          Error,
          rule_name,
          value,
        )
        valid = false
      }
    None => ()
  }
  match policy.exclusive_minimum {
    Some(minimum) =>
      if number <= minimum {
        add_issue(
          context,
          path,
          "number.exclusive_minimum",
          "exclusiveMinimum",
          "number must be greater than \{minimum}",
          Error,
          rule_name,
          value,
        )
        valid = false
      }
    None => ()
  }
  match policy.exclusive_maximum {
    Some(maximum) =>
      if number >= maximum {
        add_issue(
          context,
          path,
          "number.exclusive_maximum",
          "exclusiveMaximum",
          "number must be less than \{maximum}",
          Error,
          rule_name,
          value,
        )
        valid = false
      }
    None => ()
  }
  match policy.multiple_of {
    Some(divisor) =>
      if !multiple_matches(number, divisor) {
        add_issue(
          context,
          path,
          "number.multiple_of",
          "multipleOf",
          "number must be a multiple of \{divisor}",
          Error,
          rule_name,
          value,
        )
        valid = false
      }
    None => ()
  }
  if policy.integer_only && number != number.round() {
    add_issue(
      context,
      path,
      "number.integer",
      "integer",
      "number must be an integer",
      Error,
      rule_name,
      value,
    )
    valid = false
  }
  if policy.non_zero && number == 0.0 {
    add_issue(
      context,
      path,
      "number.zero",
      "nonZero",
      "number must not be zero",
      Error,
      rule_name,
      value,
    )
    valid = false
  }
  if policy.positive && number <= 0.0 {
    add_issue(
      context,
      path,
      "number.positive",
      "positive",
      "number must be positive",
      Error,
      rule_name,
      value,
    )
    valid = false
  }
  if policy.negative && number >= 0.0 {
    add_issue(
      context,
      path,
      "number.negative",
      "negative",
      "number must be negative",
      Error,
      rule_name,
      value,
    )
    valid = false
  }
  valid
}

///|
fn validate_array_policy(
  context : ValidationContext,
  root : Json,
  value : Json,
  policy : ArrayPolicy,
  path : String,
  depth : Int,
  rule_name : String,
) -> Bool {
  let values = match value {
    Array(values) => values
    _ => {
      ignore(validate_kind_rule(context, value, ArrayValue, path, rule_name))
      return false
    }
  }
  let mut valid = true
  match policy.min_items {
    Some(minimum) =>
      if values.length() < minimum {
        add_issue(
          context,
          path,
          "array.too_short",
          "minItems",
          "array must contain at least \{minimum} items",
          Error,
          rule_name,
          value,
        )
        valid = false
      }
    None => ()
  }
  match policy.max_items {
    Some(maximum) =>
      if values.length() > maximum {
        add_issue(
          context,
          path,
          "array.too_long",
          "maxItems",
          "array must contain at most \{maximum} items",
          Error,
          rule_name,
          value,
        )
        valid = false
      }
    None => ()
  }
  if policy.unique_items {
    for left = 0; left < values.length(); left = left + 1 {
      for right = left + 1; right < values.length(); right = right + 1 {
        if values[left] == values[right] {
          let duplicate_path = child_path(
            path,
            right.to_string(),
            context.options.path_style,
          )
          add_issue(
            context,
            duplicate_path,
            "array.duplicate",
            "uniqueItems",
            "array item duplicates index \{left}",
            Error,
            rule_name,
            values[right],
          )
          valid = false
          if context_should_stop(context) {
            return false
          }
        }
      }
    }
  }
  let prefix_count = policy.prefix_items.length().min(values.length())
  for index = 0; index < prefix_count; index = index + 1 {
    let item_path = child_path(
      path,
      index.to_string(),
      context.options.path_style,
    )
    if !validate_rule(
        context,
        root,
        values[index],
        policy.prefix_items[index],
        item_path,
        depth + 1,
        rule_name,
      ) {
      valid = false
    }
    if context_should_stop(context) {
      return false
    }
  }
  match policy.items {
    Some(item_rule) =>
      for index = prefix_count; index < values.length(); index = index + 1 {
        let item_path = child_path(
          path,
          index.to_string(),
          context.options.path_style,
        )
        if !validate_rule(
            context,
            root,
            values[index],
            item_rule,
            item_path,
            depth + 1,
            rule_name,
          ) {
          valid = false
        }
        if context_should_stop(context) {
          return false
        }
      }
    None => ()
  }
  match policy.contains {
    Some(contained_rule) => {
      let mut matches = 0
      for item in values {
        if silent_match(root, item, contained_rule, context.options, depth + 1) {
          matches += 1
        }
      }
      if matches < policy.min_contains {
        add_issue(
          context,
          path,
          "array.contains_min",
          "minContains",
          "array contains \{matches} matching items; expected at least \{policy.min_contains}",
          Error,
          rule_name,
          value,
        )
        valid = false
      }
      match policy.max_contains {
        Some(maximum) =>
          if matches > maximum {
            add_issue(
              context,
              path,
              "array.contains_max",
              "maxContains",
              "array contains \{matches} matching items; expected at most \{maximum}",
              Error,
              rule_name,
              value,
            )
            valid = false
          }
        None => ()
      }
    }
    None => ()
  }
  valid
}

///|
fn property_by_name(policy : ObjectPolicy, name : String) -> PropertyRule? {
  for property in policy.properties {
    if property.name == name {
      return Some(property)
    }
  }
  None
}

///|
fn count_present(values : Map[String, Json], names : Array[String]) -> Int {
  let mut count = 0
  for name in names {
    if values.contains(name) {
      count += 1
    }
  }
  count
}

///|
fn validate_object_policy(
  context : ValidationContext,
  root : Json,
  value : Json,
  policy : ObjectPolicy,
  path : String,
  depth : Int,
  rule_name : String,
) -> Bool {
  let values = match value {
    Object(values) => values
    _ => {
      ignore(validate_kind_rule(context, value, ObjectValue, path, rule_name))
      return false
    }
  }
  let mut valid = true
  match policy.min_properties {
    Some(minimum) =>
      if values.length() < minimum {
        add_issue(
          context,
          path,
          "object.too_small",
          "minProperties",
          "object must contain at least \{minimum} properties",
          Error,
          rule_name,
          value,
        )
        valid = false
      }
    None => ()
  }
  match policy.max_properties {
    Some(maximum) =>
      if values.length() > maximum {
        add_issue(
          context,
          path,
          "object.too_large",
          "maxProperties",
          "object must contain at most \{maximum} properties",
          Error,
          rule_name,
          value,
        )
        valid = false
      }
    None => ()
  }
  for property in policy.properties {
    let property_path = child_path(
      path,
      property.name,
      context.options.path_style,
    )
    match values.get(property.name) {
      Some(property_value) => {
        if property.deprecated {
          add_issue(
            context,
            property_path,
            "object.deprecated",
            "deprecated",
            "property \{property.name} is deprecated",
            Warning,
            rule_name,
            property_value,
          )
        }
        if !validate_rule(
            context,
            root,
            property_value,
            property.rule,
            property_path,
            depth + 1,
            rule_name,
          ) {
          valid = false
        }
      }
      None =>
        if property.required {
          add_issue(
            context,
            property_path,
            "object.required",
            "required",
            "required property \{property.name} is missing",
            Error,
            rule_name,
            value,
          )
          valid = false
        }
    }
    if context_should_stop(context) {
      return false
    }
  }
  for key, additional_value in values {
    if property_by_name(policy, key) is Some(_) {
      continue
    }
    let additional_path = child_path(path, key, context.options.path_style)
    match policy.additional_rule {
      Some(rule) =>
        if !validate_rule(
            context,
            root,
            additional_value,
            rule,
            additional_path,
            depth + 1,
            rule_name,
          ) {
          valid = false
        }
      None =>
        if !policy.allow_additional {
          add_issue(
            context,
            additional_path,
            "object.additional",
            "additionalProperties",
            "additional property \{key} is not allowed",
            Error,
            rule_name,
            additional_value,
          )
          valid = false
        }
    }
    if context_should_stop(context) {
      return false
    }
  }
  for dependency in policy.dependencies {
    if values.contains(dependency.property) {
      for required in dependency.requires {
        if !values.contains(required) {
          add_issue(
            context,
            child_path(path, required, context.options.path_style),
            "object.dependency",
            "dependentRequired",
            "property \{required} is required when \{dependency.property} is present",
            Error,
            rule_name,
            value,
          )
          valid = false
        }
      }
    }
  }
  for group in policy.mutually_exclusive {
    let present = count_present(values, group)
    if present > 1 {
      add_issue(
        context,
        path,
        "object.mutually_exclusive",
        "mutuallyExclusive",
        "at most one of the configured properties may be present",
        Error,
        rule_name,
        value,
      )
      valid = false
    }
  }
  for group in policy.at_least_one {
    if count_present(values, group) == 0 {
      add_issue(
        context,
        path,
        "object.at_least_one",
        "atLeastOne",
        "at least one configured property must be present",
        Error,
        rule_name,
        value,
      )
      valid = false
    }
  }
  valid
}

///|
fn evaluate_predicate(
  root : Json,
  predicate : Predicate,
  options : ValidationOptions,
  depth : Int,
) -> Bool {
  match predicate {
    Always => true
    Never => false
    Exists(path) => path_exists(root, path)
    Missing(path) => !path_exists(root, path)
    Equals(path, expected) =>
      match json_at_path(root, path) {
        Some(value) => value == expected
        None => false
      }
    KindIs(path, expected) =>
      match json_at_path(root, path) {
        Some(value) => value_matches_kind(value, expected)
        None => false
      }
    Validates(path, rule) =>
      match json_at_path(root, path) {
        Some(value) => silent_match(root, value, rule, options, depth + 1)
        None => false
      }
    AllPredicates(predicates) => {
      for child in predicates {
        if !evaluate_predicate(root, child, options, depth + 1) {
          return false
        }
      }
      true
    }
    AnyPredicate(predicates) => {
      for child in predicates {
        if evaluate_predicate(root, child, options, depth + 1) {
          return true
        }
      }
      false
    }
    NotPredicate(child) => !evaluate_predicate(root, child, options, depth + 1)
  }
}

///|
fn validate_rule(
  context : ValidationContext,
  root : Json,
  value : Json,
  rule : Rule,
  path : String,
  depth : Int,
  rule_name : String,
) -> Bool {
  if context_should_stop(context) ||
    !visit_rule(context, value, path, depth, rule_name) {
    return false
  }
  match rule {
    Accept => true
    Reject(message) => {
      add_issue(
        context,
        path,
        "rule.rejected",
        "reject",
        message,
        Error,
        rule_name,
        value,
      )
      false
    }
    Kind(expected) =>
      validate_kind_rule(context, value, expected, path, rule_name)
    StringMatches(policy) =>
      validate_string_policy(context, value, policy, path, rule_name)
    NumberMatches(policy) =>
      validate_number_policy(context, value, policy, path, rule_name)
    ArrayMatches(policy) =>
      validate_array_policy(
        context, root, value, policy, path, depth, rule_name,
      )
    ObjectMatches(policy) =>
      validate_object_policy(
        context, root, value, policy, path, depth, rule_name,
      )
    EqualsValue(expected) =>
      if value == expected {
        true
      } else {
        add_issue(
          context,
          path,
          "value.const",
          "const",
          "value does not equal the required constant",
          Error,
          rule_name,
          value,
        )
        false
      }
    InValues(expected) => {
      for candidate in expected {
        if value == candidate {
          return true
        }
      }
      add_issue(
        context,
        path,
        "value.enum",
        "enum",
        "value is not in the allowed set",
        Error,
        rule_name,
        value,
      )
      false
    }
    AllOf(rules) => {
      let mut valid = true
      for child in rules {
        if !validate_rule(
            context,
            root,
            value,
            child,
            path,
            depth + 1,
            rule_name,
          ) {
          valid = false
        }
        if context_should_stop(context) {
          return false
        }
      }
      valid
    }
    AnyOf(rules) => {
      for child in rules {
        if silent_match(root, value, child, context.options, depth + 1) {
          return true
        }
      }
      add_issue(
        context,
        path,
        "combinator.any_of",
        "anyOf",
        "value does not satisfy any alternative",
        Error,
        rule_name,
        value,
      )
      false
    }
    OneOf(rules) => {
      let mut matches = 0
      for child in rules {
        if silent_match(root, value, child, context.options, depth + 1) {
          matches += 1
        }
      }
      if matches == 1 {
        true
      } else {
        add_issue(
          context,
          path,
          "combinator.one_of",
          "oneOf",
          "value satisfies \{matches} alternatives; expected exactly one",
          Error,
          rule_name,
          value,
        )
        false
      }
    }
    NoneOf(rules) => {
      for child in rules {
        if silent_match(root, value, child, context.options, depth + 1) {
          add_issue(
            context,
            path,
            "combinator.none_of",
            "noneOf",
            "value satisfies a forbidden alternative",
            Error,
            rule_name,
            value,
          )
          return false
        }
      }
      true
    }
    NotRule(child) =>
      if silent_match(root, value, child, context.options, depth + 1) {
        add_issue(
          context,
          path,
          "combinator.not",
          "not",
          "value satisfies a prohibited rule",
          Error,
          rule_name,
          value,
        )
        false
      } else {
        true
      }
    Nullable(child) | Optional(child) =>
      if value == Json::null() {
        true
      } else {
        validate_rule(context, root, value, child, path, depth + 1, rule_name)
      }
    When(predicate, then_rule, else_rule) =>
      if evaluate_predicate(root, predicate, context.options, depth + 1) {
        validate_rule(
          context,
          root,
          value,
          then_rule,
          path,
          depth + 1,
          rule_name,
        )
      } else {
        match else_rule {
          Some(child) =>
            validate_rule(
              context,
              root,
              value,
              child,
              path,
              depth + 1,
              rule_name,
            )
          None => true
        }
      }
    AtPath(target_path, child) =>
      match json_at_path(root, target_path) {
        Some(target) =>
          validate_rule(
            context,
            root,
            target,
            child,
            target_path,
            depth + 1,
            rule_name,
          )
        None => {
          add_issue(
            context,
            target_path,
            "path.missing",
            "atPath",
            "configured validation path does not exist",
            Error,
            rule_name,
            root,
          )
          false
        }
      }
    Named(name, _, child) =>
      validate_rule(context, root, value, child, path, depth + 1, name)
    WarningRule(message, child) =>
      if silent_match(root, value, child, context.options, depth + 1) {
        true
      } else {
        add_issue(
          context,
          path,
          "rule.warning",
          "warning",
          message,
          Warning,
          rule_name,
          value,
        )
        true
      }
  }
}

///|
/// Validate an already parsed JSON value.
pub fn validate(
  rule : Rule,
  value : Json,
  options? : ValidationOptions = default_validation_options(),
) -> ValidationReport {
  let context = new_context(options)
  ignore(
    validate_rule(
      context,
      value,
      value,
      rule,
      root_path(options.path_style),
      0,
      "",
    ),
  )
  report_from_context(context)
}

///|
/// Parse and validate JSON text. Syntax errors become structured issues rather
/// than exceptions crossing the API boundary.
pub fn validate_json(
  rule : Rule,
  text : String,
  options? : ValidationOptions = default_validation_options(),
) -> ValidationReport {
  let value = @json.parse(text) catch {
    _ => {
      let context = new_context(options)
      add_issue(
        context,
        root_path(options.path_style),
        "json.syntax",
        "parse",
        "input is not valid JSON",
        Error,
        "",
        Json::string(text),
      )
      return report_from_context(context)
    }
  }
  validate(rule, value, options~)
}

///|
pub fn Validator::validate(self : Validator, value : Json) -> ValidationReport {
  validate(self.rule, value, options=self.options)
}

///|
pub fn Validator::validate_json(
  self : Validator,
  text : String,
) -> ValidationReport {
  validate_json(self.rule, text, options=self.options)
}

///|
pub fn is_valid(rule : Rule, value : Json) -> Bool {
  validate(rule, value).valid
}

///|
pub fn first_issue(report : ValidationReport) -> ValidationIssue? {
  if report.issues.is_empty() {
    None
  } else {
    Some(report.issues[0])
  }
}

///|
pub fn issues_at(
  report : ValidationReport,
  path : String,
) -> Array[ValidationIssue] {
  report.issues.filter(issue => issue.path == path)
}

///|
pub fn error_issues(report : ValidationReport) -> Array[ValidationIssue] {
  report.issues.filter(issue => issue.severity == Error)
}

///|
pub fn warning_issues(report : ValidationReport) -> Array[ValidationIssue] {
  report.issues.filter(issue => issue.severity == Warning)
}

///|
pub fn report_to_json(report : ValidationReport) -> String {
  report.to_json().stringify(indent=2)
}
