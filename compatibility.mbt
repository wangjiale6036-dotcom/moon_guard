///|
priv struct CompatibilityAccumulator {
  changes : Array[RuleChange]
  mut breaking_count : Int
  mut relaxing_count : Int
  mut review_count : Int
}

///|
fn compatibility_path(parent : String, segment : String) -> String {
  let escaped = escape_pointer_segment(segment)
  if parent.is_empty() {
    "/\{escaped}"
  } else {
    "\{parent}/\{escaped}"
  }
}

///|
fn add_rule_change(
  accumulator : CompatibilityAccumulator,
  path : String,
  keyword : String,
  impact : ChangeImpact,
  message : String,
) -> Unit {
  accumulator.changes.push({
    path: if path.is_empty() {
      "/"
    } else {
      path
    },
    keyword,
    impact,
    message,
  })
  match impact {
    BreakingImpact => accumulator.breaking_count += 1
    RelaxingImpact => accumulator.relaxing_count += 1
    ReviewImpact => accumulator.review_count += 1
  }
}

///|
fn compare_minimum_int(
  accumulator : CompatibilityAccumulator,
  path : String,
  keyword : String,
  previous : Int?,
  candidate : Int?,
) -> Unit {
  match (previous, candidate) {
    (None, Some(_)) =>
      add_rule_change(
        accumulator,
        path,
        keyword,
        BreakingImpact,
        "minimum constraint added",
      )
    (Some(_), None) =>
      add_rule_change(
        accumulator,
        path,
        keyword,
        RelaxingImpact,
        "minimum constraint removed",
      )
    (Some(old), Some(next)) =>
      if next > old {
        add_rule_change(
          accumulator,
          path,
          keyword,
          BreakingImpact,
          "minimum increased from \{old} to \{next}",
        )
      } else if next < old {
        add_rule_change(
          accumulator,
          path,
          keyword,
          RelaxingImpact,
          "minimum decreased from \{old} to \{next}",
        )
      }
    _ => ()
  }
}

///|
fn compare_maximum_int(
  accumulator : CompatibilityAccumulator,
  path : String,
  keyword : String,
  previous : Int?,
  candidate : Int?,
) -> Unit {
  match (previous, candidate) {
    (None, Some(_)) =>
      add_rule_change(
        accumulator,
        path,
        keyword,
        BreakingImpact,
        "maximum constraint added",
      )
    (Some(_), None) =>
      add_rule_change(
        accumulator,
        path,
        keyword,
        RelaxingImpact,
        "maximum constraint removed",
      )
    (Some(old), Some(next)) =>
      if next < old {
        add_rule_change(
          accumulator,
          path,
          keyword,
          BreakingImpact,
          "maximum decreased from \{old} to \{next}",
        )
      } else if next > old {
        add_rule_change(
          accumulator,
          path,
          keyword,
          RelaxingImpact,
          "maximum increased from \{old} to \{next}",
        )
      }
    _ => ()
  }
}

///|
fn compare_minimum_double(
  accumulator : CompatibilityAccumulator,
  path : String,
  keyword : String,
  previous : Double?,
  candidate : Double?,
) -> Unit {
  match (previous, candidate) {
    (None, Some(_)) =>
      add_rule_change(
        accumulator,
        path,
        keyword,
        BreakingImpact,
        "minimum constraint added",
      )
    (Some(_), None) =>
      add_rule_change(
        accumulator,
        path,
        keyword,
        RelaxingImpact,
        "minimum constraint removed",
      )
    (Some(old), Some(next)) =>
      if next > old {
        add_rule_change(
          accumulator,
          path,
          keyword,
          BreakingImpact,
          "numeric minimum increased",
        )
      } else if next < old {
        add_rule_change(
          accumulator,
          path,
          keyword,
          RelaxingImpact,
          "numeric minimum decreased",
        )
      }
    _ => ()
  }
}

///|
fn compare_maximum_double(
  accumulator : CompatibilityAccumulator,
  path : String,
  keyword : String,
  previous : Double?,
  candidate : Double?,
) -> Unit {
  match (previous, candidate) {
    (None, Some(_)) =>
      add_rule_change(
        accumulator,
        path,
        keyword,
        BreakingImpact,
        "maximum constraint added",
      )
    (Some(_), None) =>
      add_rule_change(
        accumulator,
        path,
        keyword,
        RelaxingImpact,
        "maximum constraint removed",
      )
    (Some(old), Some(next)) =>
      if next < old {
        add_rule_change(
          accumulator,
          path,
          keyword,
          BreakingImpact,
          "numeric maximum decreased",
        )
      } else if next > old {
        add_rule_change(
          accumulator,
          path,
          keyword,
          RelaxingImpact,
          "numeric maximum increased",
        )
      }
    _ => ()
  }
}

///|
fn compare_optional_string_constraint(
  accumulator : CompatibilityAccumulator,
  path : String,
  keyword : String,
  previous : String?,
  candidate : String?,
) -> Unit {
  if previous == candidate {
    return
  }
  match (previous, candidate) {
    (None, Some(_)) =>
      add_rule_change(
        accumulator,
        path,
        keyword,
        BreakingImpact,
        "constraint added",
      )
    (Some(_), None) =>
      add_rule_change(
        accumulator,
        path,
        keyword,
        RelaxingImpact,
        "constraint removed",
      )
    _ =>
      add_rule_change(
        accumulator,
        path,
        keyword,
        BreakingImpact,
        "constraint value changed",
      )
  }
}

///|
fn compare_boolean_constraint(
  accumulator : CompatibilityAccumulator,
  path : String,
  keyword : String,
  previous : Bool,
  candidate : Bool,
) -> Unit {
  if previous == candidate {
    return
  }
  if candidate {
    add_rule_change(
      accumulator,
      path,
      keyword,
      BreakingImpact,
      "constraint enabled",
    )
  } else {
    add_rule_change(
      accumulator,
      path,
      keyword,
      RelaxingImpact,
      "constraint disabled",
    )
  }
}

///|
fn compare_string_set(
  accumulator : CompatibilityAccumulator,
  path : String,
  keyword : String,
  previous : Array[String],
  candidate : Array[String],
  candidate_removal_breaks : Bool,
) -> Unit {
  for value in previous {
    if !candidate.contains(value) {
      add_rule_change(
        accumulator,
        path,
        keyword,
        if candidate_removal_breaks {
          BreakingImpact
        } else {
          RelaxingImpact
        },
        "value removed: \{value}",
      )
    }
  }
  for value in candidate {
    if !previous.contains(value) {
      add_rule_change(
        accumulator,
        path,
        keyword,
        if candidate_removal_breaks {
          RelaxingImpact
        } else {
          BreakingImpact
        },
        "value added: \{value}",
      )
    }
  }
}

///|
/// `allowed=[]` disables the allow-list entirely, so the empty/non-empty
/// boundary has different semantics from an ordinary set delta.
fn compare_allowed_strings(
  accumulator : CompatibilityAccumulator,
  path : String,
  previous : Array[String],
  candidate : Array[String],
) -> Unit {
  if previous.is_empty() && candidate.is_empty() {
    return
  }
  if previous.is_empty() {
    add_rule_change(
      accumulator,
      path,
      "allowed",
      BreakingImpact,
      "allow-list enabled; previously accepted strings may be rejected",
    )
    return
  }
  if candidate.is_empty() {
    add_rule_change(
      accumulator,
      path,
      "allowed",
      RelaxingImpact,
      "allow-list disabled; every string is now allowed by this constraint",
    )
    return
  }
  compare_string_set(accumulator, path, "allowed", previous, candidate, true)
}

///|
fn compare_string_policies(
  accumulator : CompatibilityAccumulator,
  path : String,
  previous : StringPolicy,
  candidate : StringPolicy,
) -> Unit {
  compare_minimum_int(
    accumulator,
    compatibility_path(path, "minLength"),
    "minLength",
    previous.min_length,
    candidate.min_length,
  )
  compare_maximum_int(
    accumulator,
    compatibility_path(path, "maxLength"),
    "maxLength",
    previous.max_length,
    candidate.max_length,
  )
  compare_optional_string_constraint(
    accumulator,
    compatibility_path(path, "length"),
    "length",
    previous.exact_length.map(value => value.to_string()),
    candidate.exact_length.map(value => value.to_string()),
  )
  compare_optional_string_constraint(
    accumulator,
    compatibility_path(path, "prefix"),
    "prefix",
    previous.prefix,
    candidate.prefix,
  )
  compare_optional_string_constraint(
    accumulator,
    compatibility_path(path, "suffix"),
    "suffix",
    previous.suffix,
    candidate.suffix,
  )
  compare_optional_string_constraint(
    accumulator,
    compatibility_path(path, "contains"),
    "contains",
    previous.contains,
    candidate.contains,
  )
  compare_optional_string_constraint(
    accumulator,
    compatibility_path(path, "pattern"),
    "pattern",
    previous.pattern,
    candidate.pattern,
  )
  compare_optional_string_constraint(
    accumulator,
    compatibility_path(path, "format"),
    "format",
    previous.format,
    candidate.format,
  )
  compare_allowed_strings(
    accumulator,
    compatibility_path(path, "allowed"),
    previous.allowed,
    candidate.allowed,
  )
  compare_string_set(
    accumulator,
    compatibility_path(path, "forbidden"),
    "forbidden",
    previous.forbidden,
    candidate.forbidden,
    false,
  )
  compare_boolean_constraint(
    accumulator,
    compatibility_path(path, "asciiOnly"),
    "asciiOnly",
    previous.ascii_only,
    candidate.ascii_only,
  )
  compare_boolean_constraint(
    accumulator,
    compatibility_path(path, "nonBlank"),
    "nonBlank",
    previous.non_blank,
    candidate.non_blank,
  )
  if previous.case_sensitive != candidate.case_sensitive {
    add_rule_change(
      accumulator,
      compatibility_path(path, "caseSensitive"),
      "caseSensitive",
      ReviewImpact,
      "case-sensitivity changed; shadow evidence is required",
    )
  }
}

///|
fn compare_number_policies(
  accumulator : CompatibilityAccumulator,
  path : String,
  previous : NumberPolicy,
  candidate : NumberPolicy,
) -> Unit {
  compare_minimum_double(
    accumulator,
    compatibility_path(path, "minimum"),
    "minimum",
    previous.minimum,
    candidate.minimum,
  )
  compare_maximum_double(
    accumulator,
    compatibility_path(path, "maximum"),
    "maximum",
    previous.maximum,
    candidate.maximum,
  )
  compare_minimum_double(
    accumulator,
    compatibility_path(path, "exclusiveMinimum"),
    "exclusiveMinimum",
    previous.exclusive_minimum,
    candidate.exclusive_minimum,
  )
  compare_maximum_double(
    accumulator,
    compatibility_path(path, "exclusiveMaximum"),
    "exclusiveMaximum",
    previous.exclusive_maximum,
    candidate.exclusive_maximum,
  )
  if previous.multiple_of != candidate.multiple_of {
    match (previous.multiple_of, candidate.multiple_of) {
      (None, Some(_)) =>
        add_rule_change(
          accumulator,
          compatibility_path(path, "multipleOf"),
          "multipleOf",
          BreakingImpact,
          "multiple-of constraint added",
        )
      (Some(_), None) =>
        add_rule_change(
          accumulator,
          compatibility_path(path, "multipleOf"),
          "multipleOf",
          RelaxingImpact,
          "multiple-of constraint removed",
        )
      _ =>
        add_rule_change(
          accumulator,
          compatibility_path(path, "multipleOf"),
          "multipleOf",
          ReviewImpact,
          "multiple-of constraint changed; inclusion cannot be proven safely",
        )
    }
  }
  compare_boolean_constraint(
    accumulator,
    compatibility_path(path, "integerOnly"),
    "integerOnly",
    previous.integer_only,
    candidate.integer_only,
  )
  compare_boolean_constraint(
    accumulator,
    compatibility_path(path, "nonZero"),
    "nonZero",
    previous.non_zero,
    candidate.non_zero,
  )
  compare_boolean_constraint(
    accumulator,
    compatibility_path(path, "positive"),
    "positive",
    previous.positive,
    candidate.positive,
  )
  compare_boolean_constraint(
    accumulator,
    compatibility_path(path, "negative"),
    "negative",
    previous.negative,
    candidate.negative,
  )
}

///|
fn json_array_contains(values : Array[Json], expected : Json) -> Bool {
  for value in values {
    if value == expected {
      return true
    }
  }
  false
}

///|
fn compare_json_set(
  accumulator : CompatibilityAccumulator,
  path : String,
  previous : Array[Json],
  candidate : Array[Json],
) -> Unit {
  for value in previous {
    if !json_array_contains(candidate, value) {
      add_rule_change(
        accumulator,
        path,
        "enum",
        BreakingImpact,
        "accepted value removed: \{json_preview(value, maximum_length=48)}",
      )
    }
  }
  for value in candidate {
    if !json_array_contains(previous, value) {
      add_rule_change(
        accumulator,
        path,
        "enum",
        RelaxingImpact,
        "accepted value added: \{json_preview(value, maximum_length=48)}",
      )
    }
  }
}

///|
fn find_property(
  properties : Array[PropertyRule],
  name : String,
) -> PropertyRule? {
  for property in properties {
    if property.name == name {
      return Some(property)
    }
  }
  None
}

///|
fn compare_array_policies(
  accumulator : CompatibilityAccumulator,
  path : String,
  previous : ArrayPolicy,
  candidate : ArrayPolicy,
) -> Unit {
  compare_minimum_int(
    accumulator,
    compatibility_path(path, "minItems"),
    "minItems",
    previous.min_items,
    candidate.min_items,
  )
  compare_maximum_int(
    accumulator,
    compatibility_path(path, "maxItems"),
    "maxItems",
    previous.max_items,
    candidate.max_items,
  )
  compare_boolean_constraint(
    accumulator,
    compatibility_path(path, "uniqueItems"),
    "uniqueItems",
    previous.unique_items,
    candidate.unique_items,
  )
  match (previous.items, candidate.items) {
    (Some(old), Some(next)) =>
      compare_rule_node(
        accumulator,
        compatibility_path(path, "items"),
        old,
        next,
      )
    (None, Some(_)) =>
      add_rule_change(
        accumulator,
        compatibility_path(path, "items"),
        "items",
        BreakingImpact,
        "item constraint added",
      )
    (Some(_), None) =>
      add_rule_change(
        accumulator,
        compatibility_path(path, "items"),
        "items",
        RelaxingImpact,
        "item constraint removed",
      )
    _ => ()
  }
  let shared = previous.prefix_items
    .length()
    .min(candidate.prefix_items.length())
  for index = 0; index < shared; index = index + 1 {
    compare_rule_node(
      accumulator,
      compatibility_path(
        compatibility_path(path, "prefixItems"),
        index.to_string(),
      ),
      previous.prefix_items[index],
      candidate.prefix_items[index],
    )
  }
  if candidate.prefix_items.length() > previous.prefix_items.length() {
    add_rule_change(
      accumulator,
      compatibility_path(path, "prefixItems"),
      "prefixItems",
      ReviewImpact,
      "tuple prefix length increased; interaction with items requires replay",
    )
  } else if candidate.prefix_items.length() < previous.prefix_items.length() {
    add_rule_change(
      accumulator,
      compatibility_path(path, "prefixItems"),
      "prefixItems",
      ReviewImpact,
      "tuple prefix length decreased; interaction with items requires replay",
    )
  }
  if previous.contains != candidate.contains ||
    previous.min_contains != candidate.min_contains ||
    previous.max_contains != candidate.max_contains {
    add_rule_change(
      accumulator,
      compatibility_path(path, "contains"),
      "contains",
      ReviewImpact,
      "array contains semantics changed; shadow evidence is required",
    )
  }
}

///|
fn compare_object_policies(
  accumulator : CompatibilityAccumulator,
  path : String,
  previous : ObjectPolicy,
  candidate : ObjectPolicy,
) -> Unit {
  compare_minimum_int(
    accumulator,
    compatibility_path(path, "minProperties"),
    "minProperties",
    previous.min_properties,
    candidate.min_properties,
  )
  compare_maximum_int(
    accumulator,
    compatibility_path(path, "maxProperties"),
    "maxProperties",
    previous.max_properties,
    candidate.max_properties,
  )
  if previous.additional_rule is None &&
    candidate.additional_rule is None &&
    previous.allow_additional != candidate.allow_additional {
    add_rule_change(
      accumulator,
      compatibility_path(path, "additionalProperties"),
      "additionalProperties",
      if candidate.allow_additional {
        RelaxingImpact
      } else {
        BreakingImpact
      },
      if candidate.allow_additional {
        "additional properties are now accepted"
      } else {
        "additional properties are now rejected"
      },
    )
  }
  for old_property in previous.properties {
    let property_path = compatibility_path(
      compatibility_path(path, "properties"),
      old_property.name,
    )
    match find_property(candidate.properties, old_property.name) {
      Some(next_property) => {
        if old_property.required != next_property.required {
          add_rule_change(
            accumulator,
            compatibility_path(property_path, "required"),
            "required",
            if next_property.required {
              BreakingImpact
            } else {
              RelaxingImpact
            },
            if next_property.required {
              "optional property became required"
            } else {
              "required property became optional"
            },
          )
        }
        compare_rule_node(
          accumulator,
          property_path,
          old_property.rule,
          next_property.rule,
        )
      }
      None =>
        add_rule_change(
          accumulator,
          property_path,
          "properties",
          if candidate.additional_rule is Some(_) {
            ReviewImpact
          } else if candidate.allow_additional {
            RelaxingImpact
          } else {
            BreakingImpact
          },
          "declared property removed",
        )
    }
  }
  for next_property in candidate.properties {
    if find_property(previous.properties, next_property.name) is None {
      let property_path = compatibility_path(
        compatibility_path(path, "properties"),
        next_property.name,
      )
      let impact = if next_property.required {
        BreakingImpact
      } else if previous.additional_rule is Some(_) {
        ReviewImpact
      } else if previous.allow_additional {
        BreakingImpact
      } else {
        RelaxingImpact
      }
      add_rule_change(
        accumulator,
        property_path,
        "properties",
        impact,
        if next_property.required {
          "required property added"
        } else {
          "optional property added"
        },
      )
    }
  }
  match (previous.additional_rule, candidate.additional_rule) {
    (Some(old), Some(next)) =>
      compare_rule_node(
        accumulator,
        compatibility_path(path, "additionalProperties"),
        old,
        next,
      )
    (None, Some(_)) =>
      add_rule_change(
        accumulator,
        compatibility_path(path, "additionalProperties"),
        "additionalProperties",
        if previous.allow_additional {
          BreakingImpact
        } else {
          RelaxingImpact
        },
        "typed additional-property rule added",
      )
    (Some(_), None) =>
      add_rule_change(
        accumulator,
        compatibility_path(path, "additionalProperties"),
        "additionalProperties",
        if candidate.allow_additional {
          RelaxingImpact
        } else {
          BreakingImpact
        },
        "typed additional-property rule removed",
      )
    _ => ()
  }
  if previous.dependencies != candidate.dependencies {
    add_rule_change(
      accumulator,
      compatibility_path(path, "dependentRequired"),
      "dependentRequired",
      ReviewImpact,
      "property dependencies changed",
    )
  }
  if previous.mutually_exclusive != candidate.mutually_exclusive {
    add_rule_change(
      accumulator,
      compatibility_path(path, "mutuallyExclusive"),
      "mutuallyExclusive",
      ReviewImpact,
      "mutually exclusive groups changed",
    )
  }
  if previous.at_least_one != candidate.at_least_one {
    add_rule_change(
      accumulator,
      compatibility_path(path, "atLeastOne"),
      "atLeastOne",
      ReviewImpact,
      "at-least-one groups changed",
    )
  }
}

///|
fn compare_same_combinator(
  accumulator : CompatibilityAccumulator,
  path : String,
  keyword : String,
  previous : Array[Rule],
  candidate : Array[Rule],
  extra_is_breaking : Bool,
) -> Unit {
  let shared = previous.length().min(candidate.length())
  for index = 0; index < shared; index = index + 1 {
    compare_rule_node(
      accumulator,
      compatibility_path(compatibility_path(path, keyword), index.to_string()),
      previous[index],
      candidate[index],
    )
  }
  if candidate.length() > previous.length() {
    add_rule_change(
      accumulator,
      compatibility_path(path, keyword),
      keyword,
      if extra_is_breaking {
        BreakingImpact
      } else {
        RelaxingImpact
      },
      "combinator branch added",
    )
  } else if candidate.length() < previous.length() {
    add_rule_change(
      accumulator,
      compatibility_path(path, keyword),
      keyword,
      if extra_is_breaking {
        RelaxingImpact
      } else {
        BreakingImpact
      },
      "combinator branch removed",
    )
  }
}

///|
fn rule_kind_hint(rule : Rule) -> ValueKind? {
  match rule {
    Kind(expected) => Some(expected)
    StringMatches(_) => Some(StringValue)
    NumberMatches(policy) =>
      if policy.integer_only {
        Some(IntegerValue)
      } else {
        Some(NumberValue)
      }
    ArrayMatches(_) => Some(ArrayValue)
    ObjectMatches(_) => Some(ObjectValue)
    _ => None
  }
}

///|
fn add_rule_shape_change(
  accumulator : CompatibilityAccumulator,
  path : String,
  previous : Rule,
  candidate : Rule,
) -> Unit {
  match (rule_kind_hint(previous), rule_kind_hint(candidate)) {
    (Some(old), Some(next)) => {
      let impact = if old == next {
        ReviewImpact
      } else if next == AnyValue || (old == IntegerValue && next == NumberValue) {
        RelaxingImpact
      } else {
        BreakingImpact
      }
      add_rule_change(
        accumulator,
        compatibility_path(path, "type"),
        "type",
        impact,
        "rule type changed from \{kind_name(old)} to \{kind_name(next)}",
      )
    }
    _ =>
      add_rule_change(
        accumulator,
        path,
        "rule",
        ReviewImpact,
        "rule shape changed and backward compatibility cannot be proven",
      )
  }
}

///|
fn compare_rule_node(
  accumulator : CompatibilityAccumulator,
  path : String,
  previous : Rule,
  candidate : Rule,
) -> Unit {
  if previous == candidate {
    return
  }
  match (previous, candidate) {
    (Accept, _) =>
      add_rule_change(
        accumulator,
        path,
        "rule",
        BreakingImpact,
        "candidate restricts a previously accepting rule",
      )
    (Reject(_), _) =>
      add_rule_change(
        accumulator,
        path,
        "rule",
        RelaxingImpact,
        "candidate replaces a rejecting rule",
      )
    (_, Accept) =>
      add_rule_change(
        accumulator,
        path,
        "rule",
        RelaxingImpact,
        "candidate accepts every value",
      )
    (_, Reject(_)) =>
      add_rule_change(
        accumulator,
        path,
        "rule",
        BreakingImpact,
        "candidate rejects every value",
      )
    (Kind(old), Kind(next)) => {
      let impact = if old == AnyValue {
        BreakingImpact
      } else if next == AnyValue || (old == IntegerValue && next == NumberValue) {
        RelaxingImpact
      } else {
        BreakingImpact
      }
      add_rule_change(
        accumulator,
        compatibility_path(path, "type"),
        "type",
        impact,
        "type changed from \{kind_name(old)} to \{kind_name(next)}",
      )
    }
    (StringMatches(old), StringMatches(next)) =>
      compare_string_policies(accumulator, path, old, next)
    (NumberMatches(old), NumberMatches(next)) =>
      compare_number_policies(accumulator, path, old, next)
    (ArrayMatches(old), ArrayMatches(next)) =>
      compare_array_policies(accumulator, path, old, next)
    (ObjectMatches(old), ObjectMatches(next)) =>
      compare_object_policies(accumulator, path, old, next)
    (EqualsValue(old), EqualsValue(next)) =>
      add_rule_change(
        accumulator,
        compatibility_path(path, "const"),
        "const",
        BreakingImpact,
        "constant value changed from \{json_preview(old, maximum_length=32)} to \{json_preview(next, maximum_length=32)}",
      )
    (InValues(old), InValues(next)) =>
      compare_json_set(accumulator, compatibility_path(path, "enum"), old, next)
    (EqualsValue(old), InValues(next)) =>
      if next.length() == 1 && json_array_contains(next, old) {
        ()
      } else if json_array_contains(next, old) {
        add_rule_change(
          accumulator,
          compatibility_path(path, "enum"),
          "enum",
          RelaxingImpact,
          "constant expanded to an enum",
        )
      } else {
        add_rule_change(
          accumulator,
          compatibility_path(path, "enum"),
          "enum",
          BreakingImpact,
          "candidate enum excludes the previous constant",
        )
      }
    (InValues(old), EqualsValue(next)) =>
      if old.length() == 1 && json_array_contains(old, next) {
        ()
      } else {
        add_rule_change(
          accumulator,
          compatibility_path(path, "const"),
          "const",
          BreakingImpact,
          "enum narrowed to a constant",
        )
      }
    (AllOf(old), AllOf(next)) =>
      compare_same_combinator(accumulator, path, "allOf", old, next, true)
    (AnyOf(old), AnyOf(next)) =>
      compare_same_combinator(accumulator, path, "anyOf", old, next, false)
    (OneOf(_), OneOf(_)) =>
      add_rule_change(
        accumulator,
        compatibility_path(path, "oneOf"),
        "oneOf",
        ReviewImpact,
        "exclusive alternatives changed; overlap requires shadow evidence",
      )
    (NoneOf(_), NoneOf(_)) =>
      add_rule_change(
        accumulator,
        compatibility_path(path, "noneOf"),
        "noneOf",
        ReviewImpact,
        "negated alternatives changed; polarity requires shadow evidence",
      )
    (old, AllOf(next)) =>
      if next.contains(old) {
        add_rule_change(
          accumulator,
          compatibility_path(path, "allOf"),
          "allOf",
          BreakingImpact,
          "candidate adds conjunctive constraints",
        )
      } else {
        add_rule_shape_change(accumulator, path, old, AllOf(next))
      }
    (AllOf(old), next) =>
      if old.contains(next) {
        add_rule_change(
          accumulator,
          compatibility_path(path, "allOf"),
          "allOf",
          RelaxingImpact,
          "candidate removes conjunctive constraints",
        )
      } else {
        add_rule_shape_change(accumulator, path, AllOf(old), next)
      }
    (Nullable(old), Nullable(next)) =>
      compare_rule_node(accumulator, path, old, next)
    (Optional(old), Optional(next)) =>
      compare_rule_node(accumulator, path, old, next)
    (old, Nullable(next)) => {
      add_rule_change(
        accumulator,
        compatibility_path(path, "nullable"),
        "nullable",
        RelaxingImpact,
        "null is now accepted",
      )
      compare_rule_node(accumulator, path, old, next)
    }
    (Nullable(old), next) => {
      add_rule_change(
        accumulator,
        compatibility_path(path, "nullable"),
        "nullable",
        BreakingImpact,
        "null is no longer accepted",
      )
      compare_rule_node(accumulator, path, old, next)
    }
    (old, Optional(next)) => {
      add_rule_change(
        accumulator,
        compatibility_path(path, "optional"),
        "optional",
        RelaxingImpact,
        "null is now accepted by the optional wrapper",
      )
      compare_rule_node(accumulator, path, old, next)
    }
    (Optional(old), next) => {
      add_rule_change(
        accumulator,
        compatibility_path(path, "optional"),
        "optional",
        BreakingImpact,
        "null is no longer accepted by the optional wrapper",
      )
      compare_rule_node(accumulator, path, old, next)
    }
    (Named(_, _, old), Named(_, _, next)) =>
      compare_rule_node(accumulator, path, old, next)
    (Named(_, _, old), next) => compare_rule_node(accumulator, path, old, next)
    (old, Named(_, _, next)) => compare_rule_node(accumulator, path, old, next)
    (AtPath(old_path, old), AtPath(next_path, next)) =>
      if old_path == next_path {
        compare_rule_node(
          accumulator,
          compatibility_path(path, "atPath"),
          old,
          next,
        )
      } else {
        add_rule_change(
          accumulator,
          compatibility_path(path, "atPath"),
          "atPath",
          ReviewImpact,
          "target path changed; compatibility requires shadow evidence",
        )
      }
    (
      When(old_predicate, old_then, old_else),
      When(next_predicate, next_then, next_else),
    ) =>
      if old_predicate == next_predicate {
        compare_rule_node(
          accumulator,
          compatibility_path(path, "then"),
          old_then,
          next_then,
        )
        match (old_else, next_else) {
          (Some(old), Some(next)) =>
            compare_rule_node(
              accumulator,
              compatibility_path(path, "else"),
              old,
              next,
            )
          (None, Some(_)) =>
            add_rule_change(
              accumulator,
              compatibility_path(path, "else"),
              "else",
              BreakingImpact,
              "conditional else rule added",
            )
          (Some(_), None) =>
            add_rule_change(
              accumulator,
              compatibility_path(path, "else"),
              "else",
              RelaxingImpact,
              "conditional else rule removed",
            )
          _ => ()
        }
      } else {
        add_rule_change(
          accumulator,
          compatibility_path(path, "when"),
          "when",
          ReviewImpact,
          "condition changed; shadow evidence is required",
        )
      }
    (WarningRule(_, old), WarningRule(_, next)) =>
      compare_rule_node(accumulator, path, old, next)
    _ => add_rule_shape_change(accumulator, path, previous, candidate)
  }
}

///|
/// Compare the payload acceptance semantics of a previous and candidate rule.
/// The score is a compact triage signal; callers should use the structured
/// changes and counts for policy decisions.
pub fn compare_rules(previous : Rule, candidate : Rule) -> CompatibilityReport {
  let accumulator : CompatibilityAccumulator = {
    changes: [],
    breaking_count: 0,
    relaxing_count: 0,
    review_count: 0,
  }
  compare_rule_node(accumulator, "", previous, candidate)
  let penalty = accumulator.breaking_count * 25 + accumulator.review_count * 10
  {
    backward_compatible: accumulator.breaking_count == 0 &&
    accumulator.review_count == 0,
    score: (100 - penalty).max(0),
    breaking_count: accumulator.breaking_count,
    relaxing_count: accumulator.relaxing_count,
    review_count: accumulator.review_count,
    changes: accumulator.changes,
  }
}

///|
pub fn compatibility_to_json(report : CompatibilityReport) -> String {
  report.to_json().stringify(indent=2)
}

///|
/// Parse and compare two dynamic rule documents without silently discarding
/// diagnostics from either side.
pub fn compare_rule_json(
  baseline_json : String,
  candidate_json : String,
) -> CompatibilityParseResult {
  let baseline = parse_rule_document(baseline_json)
  let candidate = parse_rule_document(candidate_json)
  let errors : Array[String] = []
  for error in baseline.errors {
    errors.push("baseline: \{error}")
  }
  for error in candidate.errors {
    errors.push("candidate: \{error}")
  }
  match (baseline.rule, candidate.rule) {
    (Some(previous), Some(next)) => {
      let report = compare_rules(previous, next)
      { ok: errors.is_empty(), errors, report: Some(report) }
    }
    _ => { ok: false, errors, report: None }
  }
}

///|
pub fn RuleRegistry::compare_versions(
  self : RuleRegistry,
  channel : String,
  baseline_version : Int,
  candidate_version : Int,
) -> RegistryCompatibilityResult {
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
        report: Some(compare_rules(baseline.rule, candidate.rule)),
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
pub fn RuleRegistry::compare_with_active(
  self : RuleRegistry,
  channel : String,
  candidate_version : Int,
) -> RegistryCompatibilityResult {
  match self.active_version(channel) {
    None =>
      {
        found: false,
        channel,
        baseline_version: None,
        candidate_version: None,
        report: None,
      }
    Some(active) => self.compare_versions(channel, active, candidate_version)
  }
}
