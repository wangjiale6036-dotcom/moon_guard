///|
fn compatibility_has(
  report : CompatibilityReport,
  keyword : String,
  impact : ChangeImpact,
) -> Bool {
  for change in report.changes {
    if change.keyword == keyword && change.impact == impact {
      return true
    }
  }
  false
}

///|
fn compatibility_json(text : String) -> Json {
  @json.parse(text) catch {
    _ => Json::null()
  }
}

///|
test "identical rules are fully compatible" {
  let report = compare_rules(sample_user_rule(), sample_user_rule())
  assert_true(report.backward_compatible)
  assert_eq(report.score, 100)
  assert_eq(report.changes.length(), 0)
}

///|
test "adding string minimum length is breaking" {
  let report = compare_rules(string(), string_rule(min_length=Some(3)))
  assert_false(report.backward_compatible)
  assert_true(compatibility_has(report, "minLength", BreakingImpact))
}

///|
test "removing string minimum length is relaxing" {
  let report = compare_rules(string_rule(min_length=Some(3)), string())
  assert_true(report.backward_compatible)
  assert_true(compatibility_has(report, "minLength", RelaxingImpact))
}

///|
test "increasing string minimum length is breaking" {
  let report = compare_rules(
    string_rule(min_length=Some(3)),
    string_rule(min_length=Some(5)),
  )
  assert_true(compatibility_has(report, "minLength", BreakingImpact))
}

///|
test "decreasing string minimum length is relaxing" {
  let report = compare_rules(
    string_rule(min_length=Some(5)),
    string_rule(min_length=Some(3)),
  )
  assert_true(compatibility_has(report, "minLength", RelaxingImpact))
}

///|
test "decreasing string maximum length is breaking" {
  let report = compare_rules(
    string_rule(max_length=Some(20)),
    string_rule(max_length=Some(10)),
  )
  assert_true(compatibility_has(report, "maxLength", BreakingImpact))
}

///|
test "increasing string maximum length is relaxing" {
  let report = compare_rules(
    string_rule(max_length=Some(10)),
    string_rule(max_length=Some(20)),
  )
  assert_true(compatibility_has(report, "maxLength", RelaxingImpact))
}

///|
test "adding a string format is breaking" {
  let report = compare_rules(string(), string_rule(format=Some("email")))
  assert_true(compatibility_has(report, "format", BreakingImpact))
}

///|
test "removing a string format is relaxing" {
  let report = compare_rules(string_rule(format=Some("email")), string())
  assert_true(compatibility_has(report, "format", RelaxingImpact))
}

///|
test "changing a string format is breaking" {
  let report = compare_rules(
    string_rule(format=Some("email")),
    string_rule(format=Some("uuid")),
  )
  assert_true(compatibility_has(report, "format", BreakingImpact))
}

///|
test "removing allowed string is breaking" {
  let report = compare_rules(
    string_rule(allowed=["user", "admin"]),
    string_rule(allowed=["user"]),
  )
  assert_true(compatibility_has(report, "allowed", BreakingImpact))
}

///|
test "adding allowed string is relaxing" {
  let report = compare_rules(
    string_rule(allowed=["user"]),
    string_rule(allowed=["user", "admin"]),
  )
  assert_true(compatibility_has(report, "allowed", RelaxingImpact))
}

///|
test "enabling a previously disabled allow-list is breaking" {
  let report = compare_rules(
    string_rule(allowed=[]),
    string_rule(allowed=["user"]),
  )
  assert_true(compatibility_has(report, "allowed", BreakingImpact))
  assert_false(report.backward_compatible)
  assert_true(validate(string_rule(allowed=[]), "guest".to_json()).valid)
  assert_false(validate(string_rule(allowed=["user"]), "guest".to_json()).valid)
}

///|
test "disabling an allow-list is relaxing" {
  let report = compare_rules(
    string_rule(allowed=["user"]),
    string_rule(allowed=[]),
  )
  assert_true(compatibility_has(report, "allowed", RelaxingImpact))
  assert_true(report.backward_compatible)
}

///|
test "adding forbidden string is breaking" {
  let report = compare_rules(
    string_rule(forbidden=[]),
    string_rule(forbidden=["root"]),
  )
  assert_true(compatibility_has(report, "forbidden", BreakingImpact))
}

///|
test "removing forbidden string is relaxing" {
  let report = compare_rules(
    string_rule(forbidden=["root"]),
    string_rule(forbidden=[]),
  )
  assert_true(compatibility_has(report, "forbidden", RelaxingImpact))
}

///|
test "enabling ascii-only is breaking" {
  let report = compare_rules(string(), string_rule(ascii_only=true))
  assert_true(compatibility_has(report, "asciiOnly", BreakingImpact))
}

///|
test "case sensitivity change requires review" {
  let report = compare_rules(
    string_rule(case_sensitive=true),
    string_rule(case_sensitive=false),
  )
  assert_false(report.backward_compatible)
  assert_eq(report.review_count, 1)
}

///|
test "numeric minimum increase is breaking" {
  let report = compare_rules(
    number_rule(minimum=Some(1.0)),
    number_rule(minimum=Some(2.0)),
  )
  assert_true(compatibility_has(report, "minimum", BreakingImpact))
}

///|
test "numeric maximum increase is relaxing" {
  let report = compare_rules(
    number_rule(maximum=Some(10.0)),
    number_rule(maximum=Some(20.0)),
  )
  assert_true(compatibility_has(report, "maximum", RelaxingImpact))
}

///|
test "adding multiple-of is breaking" {
  let report = compare_rules(number(), number_rule(multiple_of=Some(2.0)))
  assert_true(compatibility_has(report, "multipleOf", BreakingImpact))
}

///|
test "enabling integer-only is breaking" {
  let report = compare_rules(number(), integer())
  assert_true(compatibility_has(report, "integerOnly", BreakingImpact))
}

///|
test "number kind relaxes integer kind" {
  let report = compare_rules(kind(IntegerValue), kind(NumberValue))
  assert_true(report.backward_compatible)
  assert_true(compatibility_has(report, "type", RelaxingImpact))
}

///|
test "integer kind narrows number kind" {
  let report = compare_rules(kind(NumberValue), kind(IntegerValue))
  assert_true(compatibility_has(report, "type", BreakingImpact))
}

///|
test "array minimum increase is breaking" {
  let report = compare_rules(
    array_rule(min_items=Some(1)),
    array_rule(min_items=Some(2)),
  )
  assert_true(compatibility_has(report, "minItems", BreakingImpact))
}

///|
test "enabling unique items is breaking" {
  let report = compare_rules(array(), array_rule(unique_items=true))
  assert_true(compatibility_has(report, "uniqueItems", BreakingImpact))
}

///|
test "adding array item rule is breaking" {
  let report = compare_rules(array(), array_rule(items=Some(integer())))
  assert_true(compatibility_has(report, "items", BreakingImpact))
}

///|
test "nested array item relaxation is reported" {
  let report = compare_rules(
    array_rule(items=Some(string_rule(min_length=Some(4)))),
    array_rule(items=Some(string_rule(min_length=Some(2)))),
  )
  assert_true(compatibility_has(report, "minLength", RelaxingImpact))
  assert_eq(report.changes[0].path, "/items/minLength")
}

///|
test "disallowing additional properties is breaking" {
  let report = compare_rules(object(), object_rule(allow_additional=false))
  assert_true(compatibility_has(report, "additionalProperties", BreakingImpact))
}

///|
test "allowing additional properties is relaxing" {
  let report = compare_rules(object_rule(allow_additional=false), object())
  assert_true(compatibility_has(report, "additionalProperties", RelaxingImpact))
}

///|
test "adding required property is breaking" {
  let report = compare_rules(
    strict_object([]),
    strict_object([property("email", string())]),
  )
  assert_true(compatibility_has(report, "properties", BreakingImpact))
  assert_eq(report.changes[0].path, "/properties/email")
}

///|
test "required property becoming optional is relaxing" {
  let report = compare_rules(
    strict_object([property("email", string())]),
    strict_object([optional_property("email", string())]),
  )
  assert_true(compatibility_has(report, "required", RelaxingImpact))
}

///|
test "nested object constraint uses property path" {
  let report = compare_rules(
    strict_object([property("age", number_rule(minimum=Some(13.0)))]),
    strict_object([property("age", number_rule(minimum=Some(18.0)))]),
  )
  assert_eq(report.changes[0].path, "/properties/age/minimum")
}

///|
test "removing enum value is breaking" {
  let report = compare_rules(
    one_of_strings(["user", "admin"]),
    one_of_strings(["user"]),
  )
  assert_true(compatibility_has(report, "enum", BreakingImpact))
}

///|
test "adding enum value is relaxing" {
  let report = compare_rules(
    one_of_strings(["user"]),
    one_of_strings(["user", "admin"]),
  )
  assert_true(compatibility_has(report, "enum", RelaxingImpact))
}

///|
test "making a rule nullable is relaxing" {
  let report = compare_rules(string(), nullable(string()))
  assert_true(compatibility_has(report, "nullable", RelaxingImpact))
}

///|
test "removing nullable wrapper is breaking" {
  let report = compare_rules(nullable(string()), string())
  assert_true(compatibility_has(report, "nullable", BreakingImpact))
}

///|
test "adding all-of branch is breaking" {
  let report = compare_rules(
    all_of([string()]),
    all_of([string(), string_rule(min_length=Some(2))]),
  )
  assert_true(compatibility_has(report, "allOf", BreakingImpact))
}

///|
test "adding any-of branch is relaxing" {
  let report = compare_rules(any_of([string()]), any_of([string(), integer()]))
  assert_true(compatibility_has(report, "anyOf", RelaxingImpact))
}

///|
test "changing one-of alternatives requires review" {
  let baseline = exactly_one_of([string(), integer()])
  let candidate = exactly_one_of([string()])
  let report = compare_rules(baseline, candidate)
  assert_true(compatibility_has(report, "oneOf", ReviewImpact))
  assert_false(report.backward_compatible)
  assert_true(validate(baseline, (1).to_json()).valid)
  assert_false(validate(candidate, (1).to_json()).valid)
}

///|
test "changing none-of alternatives requires review" {
  let baseline = none_of([string_rule(min_length=Some(5))])
  let candidate = none_of([string_rule(min_length=Some(3))])
  let report = compare_rules(baseline, candidate)
  assert_true(compatibility_has(report, "noneOf", ReviewImpact))
  assert_false(report.backward_compatible)
  assert_true(validate(baseline, "abc".to_json()).valid)
  assert_false(validate(candidate, "abc".to_json()).valid)
}

///|
test "prefix item length change with fallback items requires review" {
  let baseline = array_rule(prefix_items=[integer()], items=Some(string()))
  let candidate = array_rule(prefix_items=[], items=Some(string()))
  let report = compare_rules(baseline, candidate)
  assert_true(compatibility_has(report, "prefixItems", ReviewImpact))
  assert_true(validate(baseline, compatibility_json("[1]")).valid)
  assert_false(validate(candidate, compatibility_json("[1]")).valid)
}

///|
test "declaring a typed additional property requires review" {
  let additional = Some(string())
  let baseline = object_rule(allow_additional=false, additional_rule=additional)
  let candidate = object_rule(
    properties=[optional_property("x", integer())],
    allow_additional=false,
    additional_rule=additional,
  )
  let report = compare_rules(baseline, candidate)
  let witness = compatibility_json("{\"x\":\"ok\"}")
  assert_true(compatibility_has(report, "properties", ReviewImpact))
  assert_true(validate(baseline, witness).valid)
  assert_false(validate(candidate, witness).valid)
}

///|
test "additional allow flag is metadata when a typed rule exists" {
  let baseline = object_rule(
    allow_additional=false,
    additional_rule=Some(string()),
  )
  let candidate = object_rule(
    allow_additional=true,
    additional_rule=Some(string()),
  )
  let report = compare_rules(baseline, candidate)
  assert_true(report.backward_compatible)
  assert_eq(report.changes.length(), 0)
}

///|
test "equivalent const and singleton enum have no semantic change" {
  let from_const = compare_rules(
    equals("x".to_json()),
    one_of_values(["x".to_json()]),
  )
  let from_enum = compare_rules(
    one_of_values(["x".to_json()]),
    equals("x".to_json()),
  )
  assert_eq(from_const.changes.length(), 0)
  assert_eq(from_enum.changes.length(), 0)
}

///|
test "changing multiple-of requires review" {
  let report = compare_rules(
    number_rule(multiple_of=Some(2.0)),
    number_rule(multiple_of=Some(3.0)),
  )
  assert_true(compatibility_has(report, "multipleOf", ReviewImpact))
}

///|
test "named metadata does not alter acceptance" {
  let report = compare_rules(
    named("v1", string(), description="old"),
    named("v2", string(), description="new"),
  )
  assert_true(report.backward_compatible)
  assert_eq(report.changes.length(), 0)
}

///|
test "changing conditional predicate requires review" {
  let report = compare_rules(
    when(Exists("/a"), string()),
    when(Exists("/b"), string()),
  )
  assert_true(compatibility_has(report, "when", ReviewImpact))
}

///|
test "compatibility score penalizes breaking changes" {
  let report = compare_rules(
    string(),
    string_rule(min_length=Some(2), max_length=Some(8), non_blank=true),
  )
  assert_eq(report.breaking_count, 3)
  assert_eq(report.score, 25)
}

///|
test "compatibility JSON exposes structured changes" {
  let encoded = compatibility_to_json(compare_rules(string(), integer()))
  assert_true(encoded.contains("breaking_count"))
  assert_true(encoded.contains("BreakingImpact"))
}

///|
test "JSON rule comparison ignores whitespace" {
  let result = compare_rule_json(
    "{\"type\":\"string\"}", "{ \"type\" : \"string\" }",
  )
  assert_true(result.ok)
  assert_true(result.report.unwrap().backward_compatible)
  assert_eq(result.report.unwrap().changes.length(), 0)
}

///|
test "JSON rule comparison labels baseline parse error" {
  let result = compare_rule_json("{bad", "{\"type\":\"string\"}")
  assert_false(result.ok)
  assert_true(result.report is None)
  assert_true(result.errors[0].has_prefix("baseline:"))
}

///|
test "JSON rule comparison labels candidate semantic error" {
  let result = compare_rule_json(
    "{\"type\":\"string\"}", "{\"type\":\"unknown\"}",
  )
  assert_false(result.ok)
  assert_true(result.errors[0].has_prefix("candidate:"))
}

///|
test "registry compares two published versions" {
  let registry = new_rule_registry()
  ignore(registry.publish_json("users", "{\"type\":\"string\"}"))
  ignore(
    registry.publish_json("users", "{\"type\":\"string\",\"minLength\":3}"),
  )
  let result = registry.compare_versions("users", 1, 2)
  assert_true(result.found)
  assert_eq(result.baseline_version, Some(1))
  assert_eq(result.candidate_version, Some(2))
  assert_eq(result.report.unwrap().breaking_count, 1)
}

///|
test "registry comparison reports missing revision" {
  let registry = new_rule_registry()
  ignore(registry.publish_rule("users", string()))
  let result = registry.compare_versions("users", 1, 9)
  assert_false(result.found)
  assert_true(result.report is None)
}

///|
test "registry compares candidate with active revision" {
  let registry = new_rule_registry()
  ignore(registry.publish_rule("users", string()))
  ignore(registry.publish_rule("users", string_rule(min_length=Some(3))))
  let result = registry.compare_with_active("users", 2)
  assert_true(result.found)
  assert_eq(result.baseline_version, Some(1))
  assert_eq(result.report.unwrap().breaking_count, 1)
}
