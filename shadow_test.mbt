///|
fn shadow_json(text : String) -> Json {
  @json.parse(text) catch {
    _ => Json::null()
  }
}

///|
fn shadow_case(id : String, text : String) -> ValidationCase {
  { id, value: shadow_json(text) }
}

///|
test "empty shadow replay has zero metrics" {
  let cases : Array[ValidationCase] = []
  let report = shadow_validate(string(), string(), cases)
  assert_eq(report.metrics.total, 0)
  assert_eq(report.metrics.regression_basis_points, 0)
  assert_eq(report.cases.length(), 0)
}

///|
test "shadow classifies stable acceptance" {
  let report = shadow_validate(string(), string_rule(min_length=Some(2)), [
    shadow_case("ok", "\"hello\""),
  ])
  assert_eq(report.cases[0].outcome, StableAccept)
  assert_eq(report.metrics.stable_accept, 1)
}

///|
test "shadow classifies stable rejection" {
  let report = shadow_validate(string(), string(), [shadow_case("bad", "1")])
  assert_eq(report.cases[0].outcome, StableReject)
  assert_eq(report.metrics.stable_reject, 1)
}

///|
test "shadow classifies candidate regression" {
  let report = shadow_validate(string(), string_rule(min_length=Some(5)), [
    shadow_case("old-client", "\"abc\""),
  ])
  assert_eq(report.cases[0].outcome, CandidateRegression)
  assert_eq(report.metrics.regressions, 1)
  assert_eq(report.metrics.regression_basis_points, 10000)
}

///|
test "shadow classifies candidate relaxation" {
  let report = shadow_validate(string_rule(min_length=Some(5)), string(), [
    shadow_case("newly-valid", "\"abc\""),
  ])
  assert_eq(report.cases[0].outcome, CandidateRelaxation)
  assert_eq(report.metrics.relaxations, 1)
}

///|
test "shadow detects diagnostic shift" {
  let report = shadow_validate(
    string_rule(min_length=Some(5)),
    string_rule(prefix=Some("x")),
    [shadow_case("different-error", "\"a\"")],
  )
  assert_eq(report.cases[0].outcome, DiagnosticShift)
  assert_eq(report.metrics.diagnostic_shifts, 1)
}

///|
test "shadow mixed batch counts every outcome" {
  let baseline = number_rule(minimum=Some(0.0), maximum=Some(10.0))
  let candidate = number_rule(minimum=Some(2.0), maximum=Some(20.0))
  let report = shadow_validate(baseline, candidate, [
    shadow_case("stable-pass", "5"),
    shadow_case("regression", "1"),
    shadow_case("relaxation", "15"),
    shadow_case("stable-fail", "-1"),
  ])
  assert_eq(report.metrics.total, 4)
  assert_eq(report.metrics.stable_accept, 1)
  assert_eq(report.metrics.regressions, 1)
  assert_eq(report.metrics.relaxations, 1)
  assert_eq(report.metrics.stable_reject, 1)
  assert_eq(report.metrics.disagreement_count, 2)
  assert_eq(report.metrics.regression_basis_points, 2500)
}

///|
test "shadow tracks baseline and candidate pass totals" {
  let report = shadow_validate(string(), string_rule(min_length=Some(3)), [
    shadow_case("short", "\"a\""),
    shadow_case("long", "\"abcd\""),
  ])
  assert_eq(report.metrics.baseline_passed, 2)
  assert_eq(report.metrics.candidate_passed, 1)
}

///|
test "shadow aggregates issue histograms" {
  let report = shadow_validate(string(), integer(), [
    shadow_case("number", "1"),
    shadow_case("bool", "true"),
  ])
  assert_true(report.metrics.baseline_issues.length() > 0)
  assert_true(report.metrics.candidate_issues.length() > 0)
}

///|
test "shadow counts truncated cases once" {
  let options = default_validation_options().with_rule_budget(1)
  let rule = strict_object([property("a", string()), property("b", string())])
  let report = shadow_validate(
    rule,
    rule,
    [shadow_case("many-errors", "{\"a\":1,\"b\":2}")],
    options~,
  )
  assert_eq(report.metrics.truncated_cases, 1)
}

///|
test "registry shadows two versions" {
  let registry = new_rule_registry()
  ignore(registry.publish_rule("users", string()))
  ignore(registry.publish_rule("users", string_rule(min_length=Some(3))))
  let result = registry.shadow_versions("users", 1, 2, [
    shadow_case("short", "\"a\""),
  ])
  assert_true(result.found)
  assert_eq(result.baseline_version, Some(1))
  assert_eq(result.candidate_version, Some(2))
  assert_eq(result.report.unwrap().metrics.regressions, 1)
}

///|
test "registry shadow reports missing version" {
  let registry = new_rule_registry()
  ignore(registry.publish_rule("users", string()))
  let cases : Array[ValidationCase] = []
  let result = registry.shadow_versions("users", 1, 9, cases)
  assert_false(result.found)
  assert_true(result.report is None)
}

///|
test "registry shadows candidate against active" {
  let registry = new_rule_registry()
  ignore(registry.publish_rule("users", string()))
  ignore(registry.publish_rule("users", string_rule(min_length=Some(3))))
  let result = registry.shadow_with_active("users", 2, [
    shadow_case("short", "\"a\""),
  ])
  assert_true(result.found)
  assert_eq(result.baseline_version, Some(1))
  assert_eq(result.report.unwrap().metrics.regressions, 1)
}

///|
test "shadow JSON is deterministic" {
  let report = shadow_validate(string(), string_rule(min_length=Some(3)), [
    shadow_case("short", "\"a\""),
  ])
  assert_eq(shadow_to_json(report), shadow_to_json(report))
  assert_true(shadow_to_json(report).contains("CandidateRegression"))
}

///|
test "shadow regression witnesses preserve input" {
  let report = shadow_validate(string(), string_rule(min_length=Some(3)), [
    shadow_case("short", "\"x\""),
  ])
  let witnesses = regression_witnesses(report)
  assert_eq(witnesses.length(), 1)
  assert_eq(witnesses[0].id, "short")
  assert_eq(witnesses[0].value, "x".to_json())
}

///|
test "shadow relaxation witnesses preserve input" {
  let report = shadow_validate(string_rule(min_length=Some(3)), string(), [
    shadow_case("newly-valid", "\"x\""),
  ])
  let witnesses = relaxation_witnesses(report)
  assert_eq(witnesses.length(), 1)
  assert_eq(witnesses[0].id, "newly-valid")
}
