///|
fn compatibility_safety_json(text : String) -> Json {
  @json.parse(text) catch {
    _ => Json::null()
  }
}

///|
test "compatibility safety: enabling an allow-list is breaking" {
  let baseline = string()
  let candidate = string_rule(allowed=["user"])
  let witness = "guest".to_json()
  assert_true(validate(baseline, witness).valid)
  assert_false(validate(candidate, witness).valid)
  assert_false(compare_rules(baseline, candidate).backward_compatible)
}

///|
test "compatibility safety: removing a oneOf branch is not compatible" {
  let baseline = exactly_one_of([string(), integer()])
  let candidate = exactly_one_of([string()])
  let witness = compatibility_safety_json("1")
  assert_true(validate(baseline, witness).valid)
  assert_false(validate(candidate, witness).valid)
  assert_false(compare_rules(baseline, candidate).backward_compatible)
}

///|
test "compatibility safety: relaxing a oneOf branch can create overlap" {
  let baseline = exactly_one_of([literal_string("a"), literal_string("b")])
  let candidate = exactly_one_of([
    one_of_strings(["a", "b"]),
    literal_string("b"),
  ])
  let witness = "b".to_json()
  assert_true(validate(baseline, witness).valid)
  assert_false(validate(candidate, witness).valid)
  assert_false(compare_rules(baseline, candidate).backward_compatible)
}

///|
test "compatibility safety: noneOf reverses child compatibility polarity" {
  let baseline = none_of([string_rule(min_length=Some(5))])
  let candidate = none_of([string_rule(min_length=Some(3))])
  let witness = "abc".to_json()
  assert_true(validate(baseline, witness).valid)
  assert_false(validate(candidate, witness).valid)
  assert_false(compare_rules(baseline, candidate).backward_compatible)
}

///|
test "compatibility safety: removed prefix item falls through to items" {
  let baseline = array_rule(prefix_items=[integer()], items=Some(string()))
  let candidate = array_rule(prefix_items=[], items=Some(string()))
  let witness = compatibility_safety_json("[1]")
  assert_true(validate(baseline, witness).valid)
  assert_false(validate(candidate, witness).valid)
  assert_false(compare_rules(baseline, candidate).backward_compatible)
}

///|
test "compatibility safety: optional property can replace additional rule" {
  let baseline = object_rule(
    properties=[],
    allow_additional=false,
    additional_rule=Some(string()),
  )
  let candidate = object_rule(
    properties=[optional_property("x", integer())],
    allow_additional=false,
    additional_rule=Some(string()),
  )
  let witness = compatibility_safety_json("{\"x\":\"ok\"}")
  assert_true(validate(baseline, witness).valid)
  assert_false(validate(candidate, witness).valid)
  assert_false(compare_rules(baseline, candidate).backward_compatible)
}

///|
test "compatibility safety: JSON type plus minLength wrapper is breaking" {
  let baseline_json = "{\"type\":\"string\"}"
  let candidate_json = "{\"type\":\"string\",\"minLength\":3}"
  let comparison = compare_rule_json(baseline_json, candidate_json)
  let baseline = rule_from_json(baseline_json).unwrap()
  let candidate = rule_from_json(candidate_json).unwrap()
  let witness = "x".to_json()
  assert_true(comparison.ok)
  assert_true(validate(baseline, witness).valid)
  assert_false(validate(candidate, witness).valid)
  assert_false(comparison.report.unwrap().backward_compatible)
}

///|
test "compatibility safety: changing string to integer is breaking" {
  let baseline = string()
  let candidate = integer()
  let witness = "7".to_json()
  assert_true(validate(baseline, witness).valid)
  assert_false(validate(candidate, witness).valid)
  assert_false(compare_rules(baseline, candidate).backward_compatible)
}
