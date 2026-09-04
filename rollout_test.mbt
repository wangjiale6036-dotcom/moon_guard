///|
fn rollout_case(id : String, value : Json) -> ValidationCase {
  { id, value }
}

///|
fn rollout_json(text : String) -> Json {
  @json.parse(text) catch {
    _ => Json::null()
  }
}

///|
test "default rollout policy is conservative" {
  let policy = default_rollout_policy()
  assert_eq(policy.min_samples, 100)
  assert_eq(policy.max_regressions, 0)
  assert_true(policy.require_static_compatibility)
  assert_false(policy.allow_static_review)
}

///|
test "rollout policy clamps unsafe thresholds" {
  let policy = rollout_policy(
    min_samples=-1,
    max_regressions=-1,
    max_regression_basis_points=20000,
  )
  assert_eq(policy.min_samples, 0)
  assert_eq(policy.max_regressions, 0)
  assert_eq(policy.max_regression_basis_points, 10000)
}

///|
test "rollout assessment reports insufficient evidence" {
  let shadow = shadow_validate(string(), string(), [])
  let assessment = assess_rollout(
    Some(compare_rules(string(), string())),
    shadow,
  )
  assert_eq(assessment.recommendation, InsufficientEvidence)
  assert_true(assessment.reasons[0].contains("sample count"))
}

///|
test "rollout promotes zero-delta candidate" {
  let cases : Array[ValidationCase] = [
    rollout_case("a", "one".to_json()),
    rollout_case("b", "two".to_json()),
  ]
  let shadow = shadow_validate(string(), string(), cases)
  let assessment = assess_rollout(
    Some(compare_rules(string(), string())),
    shadow,
    policy=rollout_policy(min_samples=2),
  )
  assert_eq(assessment.recommendation, PromoteCandidate)
}

///|
test "rollout rolls back on observed regression" {
  let shadow = shadow_validate(string(), string_rule(min_length=Some(3)), [
    rollout_case("short", "x".to_json()),
  ])
  let assessment = assess_rollout(
    Some(compare_rules(string(), string_rule(min_length=Some(3)))),
    shadow,
    policy=rollout_policy(min_samples=1),
  )
  assert_eq(assessment.recommendation, RollbackCandidate)
}

///|
test "rollout honors regression count boundary" {
  let shadow = shadow_validate(string(), string_rule(min_length=Some(3)), [
    rollout_case("short", "x".to_json()),
  ])
  let assessment = assess_rollout(
    Some(compare_rules(string(), string_rule(min_length=Some(3)))),
    shadow,
    policy=rollout_policy(
      min_samples=1,
      max_regressions=1,
      max_regression_basis_points=10000,
      require_static_compatibility=false,
    ),
  )
  assert_eq(assessment.recommendation, PromoteCandidate)
}

///|
test "static breaking change holds candidate without replay regression" {
  let baseline = string()
  let candidate = string_rule(min_length=Some(3))
  let shadow = shadow_validate(baseline, candidate, [
    rollout_case("long", "hello".to_json()),
  ])
  let assessment = assess_rollout(
    Some(compare_rules(baseline, candidate)),
    shadow,
    policy=rollout_policy(min_samples=1),
  )
  assert_eq(assessment.recommendation, HoldCandidate)
  assert_true(assessment.reasons[0].contains("breaking"))
}

///|
test "missing static evidence holds when required" {
  let shadow = shadow_validate(string(), string(), [
    rollout_case("ok", "x".to_json()),
  ])
  let assessment = assess_rollout(
    None,
    shadow,
    policy=rollout_policy(min_samples=1),
  )
  assert_eq(assessment.recommendation, HoldCandidate)
}

///|
test "security relaxation holds candidate by default" {
  let baseline = string_rule(min_length=Some(3))
  let candidate = string()
  let shadow = shadow_validate(baseline, candidate, [
    rollout_case("short", "x".to_json()),
  ])
  let assessment = assess_rollout(
    Some(compare_rules(baseline, candidate)),
    shadow,
    policy=rollout_policy(min_samples=1),
  )
  assert_eq(assessment.recommendation, HoldCandidate)
  assert_true(assessment.reasons[0].contains("relaxations"))
}

///|
test "diagnostic drift holds candidate" {
  let baseline = string_rule(min_length=Some(3))
  let candidate = string_rule(prefix=Some("z"))
  let shadow = shadow_validate(baseline, candidate, [
    rollout_case("bad", "x".to_json()),
  ])
  let assessment = assess_rollout(
    Some(compare_rules(baseline, candidate)),
    shadow,
    policy=rollout_policy(
      min_samples=1,
      require_static_compatibility=false,
      max_relaxations=1,
    ),
  )
  assert_eq(assessment.recommendation, HoldCandidate)
  assert_true(assessment.reasons[0].contains("diagnostic"))
}

///|
test "registry assesses active and candidate versions" {
  let registry = new_rule_registry()
  ignore(registry.publish_rule("users", string()))
  ignore(registry.publish_rule("users", string_rule(min_length=Some(3))))
  let result = registry.assess_candidate(
    "users",
    2,
    [rollout_case("short", "x".to_json())],
    policy=rollout_policy(min_samples=1),
  )
  assert_true(result.found)
  assert_eq(result.baseline_version, Some(1))
  assert_eq(result.candidate_version, Some(2))
  assert_eq(result.assessment.unwrap().recommendation, RollbackCandidate)
}

///|
test "registry assessment reports missing candidate" {
  let registry = new_rule_registry()
  ignore(registry.publish_rule("users", string()))
  let cases : Array[ValidationCase] = []
  let result = registry.assess_candidate("users", 9, cases)
  assert_false(result.found)
  assert_true(result.assessment is None)
}

///|
test "stable rollout bucket is deterministic" {
  assert_eq(
    stable_rollout_bucket("account-42"),
    stable_rollout_bucket("account-42"),
  )
}

///|
test "stable rollout bucket respects custom range" {
  let bucket = stable_rollout_bucket("account-42", buckets=17)
  assert_true(bucket >= 0)
  assert_true(bucket < 17)
}

///|
test "zero percent canary selects nobody" {
  assert_false(is_canary_selected("account-42", 0))
}

///|
test "full canary selects every routing key" {
  assert_true(is_canary_selected("account-42", 10000))
  assert_true(is_canary_selected("", 10000))
}

///|
test "zero percent canary serves active version" {
  let registry = new_rule_registry()
  ignore(registry.publish_rule("users", string()))
  ignore(registry.publish_rule("users", integer()))
  let result = registry.validate_canary_json(
    "users", 2, "account-42", 0, "\"hello\"",
  )
  assert_true(result.found)
  assert_false(result.routed_to_candidate)
  assert_eq(result.served_version, Some(1))
  assert_true(result.report.unwrap().valid)
}

///|
test "full canary serves candidate version" {
  let registry = new_rule_registry()
  ignore(registry.publish_rule("users", string()))
  ignore(registry.publish_rule("users", integer()))
  let result = registry.validate_canary_json(
    "users", 2, "account-42", 10000, "1",
  )
  assert_true(result.routed_to_candidate)
  assert_eq(result.served_version, Some(2))
  assert_true(result.report.unwrap().valid)
}

///|
test "canary reports missing revision" {
  let registry = new_rule_registry()
  ignore(registry.publish_rule("users", string()))
  let result = registry.validate_canary_json(
    "users", 9, "account-42", 500, "\"hello\"",
  )
  assert_false(result.found)
  assert_true(result.report is None)
}

///|
test "rollout assessment JSON exposes recommendation" {
  let shadow = shadow_validate(string(), string(), [
    rollout_case("ok", rollout_json("\"x\"")),
  ])
  let assessment = assess_rollout(
    Some(compare_rules(string(), string())),
    shadow,
    policy=rollout_policy(min_samples=1),
  )
  assert_true(
    rollout_assessment_to_json(assessment).contains("PromoteCandidate"),
  )
}
