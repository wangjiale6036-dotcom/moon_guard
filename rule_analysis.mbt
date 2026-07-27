///|
priv struct AnalysisAccumulator {
  mut node_count : Int
  mut maximum_depth : Int
  mut object_property_count : Int
  mut conditional_count : Int
  named_rules : Array[String]
  warnings : Array[String]
}

///|
fn add_analysis_warning(
  accumulator : AnalysisAccumulator,
  message : String,
) -> Unit {
  if !accumulator.warnings.contains(message) {
    accumulator.warnings.push(message)
  }
}

///|
fn analyze_string_policy(
  accumulator : AnalysisAccumulator,
  policy : StringPolicy,
) -> Unit {
  match (policy.min_length, policy.max_length) {
    (Some(minimum), Some(maximum)) =>
      if minimum > maximum {
        add_analysis_warning(accumulator, "string minLength exceeds maxLength")
      }
    _ => ()
  }
  match policy.exact_length {
    Some(length) =>
      if length < 0 {
        add_analysis_warning(accumulator, "string length must not be negative")
      }
    None => ()
  }
  match policy.format {
    Some(format) =>
      if !supported_formats().contains(format) {
        add_analysis_warning(accumulator, "unknown string format: \{format}")
      }
    None => ()
  }
  if policy.allowed.is_empty() && !policy.forbidden.is_empty() {
    ()
  }
  for value in policy.allowed {
    if policy.forbidden.contains(value) {
      add_analysis_warning(
        accumulator, "a string appears in both allowed and forbidden sets",
      )
    }
  }
}

///|
fn analyze_number_policy(
  accumulator : AnalysisAccumulator,
  policy : NumberPolicy,
) -> Unit {
  match (policy.minimum, policy.maximum) {
    (Some(minimum), Some(maximum)) =>
      if minimum > maximum {
        add_analysis_warning(accumulator, "number minimum exceeds maximum")
      }
    _ => ()
  }
  match (policy.exclusive_minimum, policy.exclusive_maximum) {
    (Some(minimum), Some(maximum)) =>
      if minimum >= maximum {
        add_analysis_warning(accumulator, "exclusive numeric range is empty")
      }
    _ => ()
  }
  match policy.multiple_of {
    Some(value) =>
      if value == 0.0 {
        add_analysis_warning(accumulator, "multipleOf must not be zero")
      }
    None => ()
  }
  if policy.positive && policy.negative {
    add_analysis_warning(
      accumulator, "number cannot be both positive and negative",
    )
  }
}

///|
fn analyze_predicate(
  accumulator : AnalysisAccumulator,
  predicate : Predicate,
  depth : Int,
) -> Unit {
  accumulator.node_count += 1
  accumulator.maximum_depth = accumulator.maximum_depth.max(depth)
  match predicate {
    Validates(_, rule) => analyze_rule_node(accumulator, rule, depth + 1)
    AllPredicates(values) | AnyPredicate(values) =>
      for value in values {
        analyze_predicate(accumulator, value, depth + 1)
      }
    NotPredicate(value) => analyze_predicate(accumulator, value, depth + 1)
    _ => ()
  }
}

///|
fn analyze_object_policy(
  accumulator : AnalysisAccumulator,
  policy : ObjectPolicy,
  depth : Int,
) -> Unit {
  accumulator.object_property_count += policy.properties.length()
  match (policy.min_properties, policy.max_properties) {
    (Some(minimum), Some(maximum)) =>
      if minimum > maximum {
        add_analysis_warning(
          accumulator, "object minProperties exceeds maxProperties",
        )
      }
    _ => ()
  }
  let names : Map[String, Bool] = Map([])
  for property in policy.properties {
    if names.contains(property.name) {
      add_analysis_warning(
        accumulator,
        "duplicate object property: \{property.name}",
      )
    } else {
      names[property.name] = true
    }
    analyze_rule_node(accumulator, property.rule, depth + 1)
  }
  match policy.additional_rule {
    Some(rule) => analyze_rule_node(accumulator, rule, depth + 1)
    None => ()
  }
  for group in policy.mutually_exclusive {
    if group.length() < 2 {
      add_analysis_warning(
        accumulator, "mutuallyExclusive group should contain at least two names",
      )
    }
  }
  for group in policy.at_least_one {
    if group.is_empty() {
      add_analysis_warning(accumulator, "atLeastOne group must not be empty")
    }
  }
}

///|
fn analyze_array_policy(
  accumulator : AnalysisAccumulator,
  policy : ArrayPolicy,
  depth : Int,
) -> Unit {
  match (policy.min_items, policy.max_items) {
    (Some(minimum), Some(maximum)) =>
      if minimum > maximum {
        add_analysis_warning(accumulator, "array minItems exceeds maxItems")
      }
    _ => ()
  }
  match (policy.max_contains, policy.contains) {
    (Some(_), None) =>
      add_analysis_warning(accumulator, "maxContains has no contains rule")
    _ => ()
  }
  if policy.min_contains < 0 {
    add_analysis_warning(accumulator, "minContains must not be negative")
  }
  match policy.items {
    Some(rule) => analyze_rule_node(accumulator, rule, depth + 1)
    None => ()
  }
  for rule in policy.prefix_items {
    analyze_rule_node(accumulator, rule, depth + 1)
  }
  match policy.contains {
    Some(rule) => analyze_rule_node(accumulator, rule, depth + 1)
    None => ()
  }
}

///|
fn analyze_rule_node(
  accumulator : AnalysisAccumulator,
  rule : Rule,
  depth : Int,
) -> Unit {
  accumulator.node_count += 1
  accumulator.maximum_depth = accumulator.maximum_depth.max(depth)
  match rule {
    StringMatches(policy) => analyze_string_policy(accumulator, policy)
    NumberMatches(policy) => analyze_number_policy(accumulator, policy)
    ArrayMatches(policy) => analyze_array_policy(accumulator, policy, depth)
    ObjectMatches(policy) => analyze_object_policy(accumulator, policy, depth)
    AllOf(values) | AnyOf(values) | OneOf(values) | NoneOf(values) => {
      if values.is_empty() {
        add_analysis_warning(accumulator, "empty rule combinator")
      }
      for value in values {
        analyze_rule_node(accumulator, value, depth + 1)
      }
    }
    NotRule(value)
    | Nullable(value)
    | Optional(value)
    | AtPath(_, value)
    | WarningRule(_, value) => analyze_rule_node(accumulator, value, depth + 1)
    When(predicate, then_rule, else_rule) => {
      accumulator.conditional_count += 1
      analyze_predicate(accumulator, predicate, depth + 1)
      analyze_rule_node(accumulator, then_rule, depth + 1)
      match else_rule {
        Some(value) => analyze_rule_node(accumulator, value, depth + 1)
        None => ()
      }
    }
    Named(name, _, value) => {
      if accumulator.named_rules.contains(name) {
        add_analysis_warning(accumulator, "duplicate named rule: \{name}")
      } else {
        accumulator.named_rules.push(name)
      }
      analyze_rule_node(accumulator, value, depth + 1)
    }
    _ => ()
  }
}

///|
/// Inspect a rule tree without executing it.
pub fn analyze_rule(rule : Rule) -> RuleAnalysis {
  let accumulator : AnalysisAccumulator = {
    node_count: 0,
    maximum_depth: 0,
    object_property_count: 0,
    conditional_count: 0,
    named_rules: [],
    warnings: [],
  }
  analyze_rule_node(accumulator, rule, 0)
  {
    node_count: accumulator.node_count,
    maximum_depth: accumulator.maximum_depth,
    object_property_count: accumulator.object_property_count,
    conditional_count: accumulator.conditional_count,
    named_rules: accumulator.named_rules,
    warnings: accumulator.warnings,
  }
}

///|
pub fn rule_node_count(rule : Rule) -> Int {
  analyze_rule(rule).node_count
}

///|
pub fn rule_is_well_formed(rule : Rule) -> Bool {
  analyze_rule(rule).warnings.is_empty()
}

///|
fn indent_text(depth : Int) -> String {
  let builder = StringBuilder()
  for _index = 0; _index < depth; _index = _index + 1 {
    builder.write_string("  ")
  }
  builder.to_string()
}

///|
fn outline_label(rule : Rule) -> String {
  match rule {
    Accept => "accept"
    Reject(_) => "reject"
    Kind(value) => "kind: \{kind_name(value)}"
    StringMatches(_) => "string"
    NumberMatches(_) => "number"
    ArrayMatches(_) => "array"
    ObjectMatches(_) => "object"
    EqualsValue(_) => "const"
    InValues(values) => "enum (\{values.length()})"
    AllOf(values) => "allOf (\{values.length()})"
    AnyOf(values) => "anyOf (\{values.length()})"
    OneOf(values) => "oneOf (\{values.length()})"
    NoneOf(values) => "noneOf (\{values.length()})"
    NotRule(_) => "not"
    Nullable(_) => "nullable"
    Optional(_) => "optional"
    When(_, _, _) => "when"
    AtPath(path, _) => "atPath: \{path}"
    Named(name, _, _) => "named: \{name}"
    WarningRule(message, _) => "warning: \{message}"
  }
}

///|
fn write_rule_outline(
  builder : StringBuilder,
  rule : Rule,
  depth : Int,
) -> Unit {
  builder.write_string("\{indent_text(depth)}- \{outline_label(rule)}\n")
  match rule {
    ArrayMatches(policy) => {
      for child in policy.prefix_items {
        write_rule_outline(builder, child, depth + 1)
      }
      match policy.items {
        Some(child) => write_rule_outline(builder, child, depth + 1)
        None => ()
      }
      match policy.contains {
        Some(child) => write_rule_outline(builder, child, depth + 1)
        None => ()
      }
    }
    ObjectMatches(policy) =>
      for property in policy.properties {
        builder.write_string(
          "\{indent_text(depth + 1)}property \{property.name}\n",
        )
        write_rule_outline(builder, property.rule, depth + 2)
      }
    AllOf(values) | AnyOf(values) | OneOf(values) | NoneOf(values) =>
      for child in values {
        write_rule_outline(builder, child, depth + 1)
      }
    NotRule(child)
    | Nullable(child)
    | Optional(child)
    | AtPath(_, child)
    | Named(_, _, child)
    | WarningRule(_, child) => write_rule_outline(builder, child, depth + 1)
    When(_, then_rule, else_rule) => {
      write_rule_outline(builder, then_rule, depth + 1)
      match else_rule {
        Some(child) => write_rule_outline(builder, child, depth + 1)
        None => ()
      }
    }
    _ => ()
  }
}

///|
/// Produce a compact tree outline for documentation and CLI diagnostics.
pub fn rule_outline(rule : Rule) -> String {
  let builder = StringBuilder()
  write_rule_outline(builder, rule, 0)
  builder.to_string()
}

///|
fn optimize_children(rules : Array[Rule], all : Bool) -> Array[Rule] {
  let result : Array[Rule] = []
  for child in rules {
    let optimized = optimize_rule(child)
    match optimized {
      Accept => if all { () } else { result.push(Accept) }
      AllOf(nested) =>
        if all {
          result.push_iter(nested.iter())
        } else {
          result.push(optimized)
        }
      AnyOf(nested) =>
        if !all {
          result.push_iter(nested.iter())
        } else {
          result.push(optimized)
        }
      _ => result.push(optimized)
    }
  }
  result
}

///|
/// Simplify nested combinators without changing validation meaning.
pub fn optimize_rule(rule : Rule) -> Rule {
  match rule {
    AllOf(values) => combine_rules(optimize_children(values, true))
    AnyOf(values) => {
      let children = optimize_children(values, false)
      if children.length() == 1 {
        children[0]
      } else {
        AnyOf(children)
      }
    }
    OneOf(values) => OneOf(values.map(optimize_rule))
    NoneOf(values) => NoneOf(values.map(optimize_rule))
    NotRule(child) => NotRule(optimize_rule(child))
    Nullable(child) => Nullable(optimize_rule(child))
    Optional(child) => Optional(optimize_rule(child))
    AtPath(path, child) => AtPath(path, optimize_rule(child))
    Named(name, description, child) =>
      Named(name, description, optimize_rule(child))
    WarningRule(message, child) => WarningRule(message, optimize_rule(child))
    When(predicate, then_rule, else_rule) =>
      When(predicate, optimize_rule(then_rule), else_rule.map(optimize_rule))
    ArrayMatches(policy) =>
      ArrayMatches({
        ..policy,
        items: policy.items.map(optimize_rule),
        prefix_items: policy.prefix_items.map(optimize_rule),
        contains: policy.contains.map(optimize_rule),
      })
    ObjectMatches(policy) =>
      ObjectMatches({
        ..policy,
        properties: policy.properties.map(property => {
          ..property,
          rule: optimize_rule(property.rule),
        }),
        additional_rule: policy.additional_rule.map(optimize_rule),
      })
    _ => rule
  }
}
