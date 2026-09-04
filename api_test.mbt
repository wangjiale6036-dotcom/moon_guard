///|
fn test_json(text : String) -> Json {
  @json.parse(text) catch {
    _ => Json::null()
  }
}

///|
fn test_valid(rule : Rule, text : String) -> Bool {
  validate(rule, test_json(text)).valid
}

///|
fn test_invalid(rule : Rule, text : String) -> Bool {
  !test_valid(rule, text)
}

///|
test "accept allows every value" {
  assert_true(test_valid(any_value(), "null"))
  assert_true(test_valid(any_value(), "{\"x\":1}"))
}

///|
test "reject rejects every value" {
  let report = validate(reject(message="blocked"), test_json("1"))
  assert_false(report.valid)
  assert_eq(report.issues[0].message, "blocked")
}

///|
test "kind any accepts object" {
  assert_true(test_valid(kind(AnyValue), "{}"))
}

///|
test "null rule accepts null" {
  assert_true(test_valid(null_value(), "null"))
  assert_true(test_invalid(null_value(), "false"))
}

///|
test "boolean rule distinguishes numbers" {
  assert_true(test_valid(boolean(), "true"))
  assert_true(test_invalid(boolean(), "1"))
}

///|
test "integer accepts integral JSON number" {
  assert_true(test_valid(integer(), "42"))
  assert_true(test_valid(integer(), "42.0"))
}

///|
test "integer rejects fraction" {
  assert_true(test_invalid(integer(), "4.2"))
}

///|
test "number accepts integer and fraction" {
  assert_true(test_valid(number(), "1"))
  assert_true(test_valid(number(), "1.5"))
}

///|
test "string constructor enforces kind" {
  assert_true(test_valid(string(), "\"hello\""))
  assert_true(test_invalid(string(), "5"))
}

///|
test "array constructor enforces kind" {
  assert_true(test_valid(array(), "[]"))
  assert_true(test_invalid(array(), "{}"))
}

///|
test "object constructor enforces kind" {
  assert_true(test_valid(object(), "{}"))
  assert_true(test_invalid(object(), "[]"))
}

///|
test "options defaults are bounded" {
  let options = default_validation_options()
  assert_false(options.fail_fast)
  assert_eq(options.max_issues, 100)
  assert_eq(options.max_depth, 64)
}

///|
test "options modifiers update one field" {
  let options = default_validation_options()
    .with_fail_fast(true)
    .with_max_issues(7)
    .with_max_depth(8)
  assert_true(options.fail_fast)
  assert_eq(options.max_issues, 7)
  assert_eq(options.max_depth, 8)
}

///|
test "options clamp unsafe limits" {
  let options = default_validation_options()
    .with_max_issues(0)
    .with_rule_budget(0)
  assert_eq(options.max_issues, 1)
  assert_eq(options.max_rule_visits, 1)
}

///|
test "validator facade reuses rule" {
  let validator = new_validator(integer())
  assert_true(validator.validate(test_json("4")).valid)
  assert_false(validator.validate(test_json("4.5")).valid)
}

///|
test "validator parses JSON text" {
  let validator = new_validator(string())
  assert_true(validator.validate_json("\"ok\"").valid)
  assert_false(validator.validate_json("bad").valid)
}

///|
test "json syntax produces structured issue" {
  let report = validate_json(any_value(), "{bad")
  assert_eq(report.stats.error_count, 1)
  assert_eq(report.issues[0].code, "json.syntax")
}

///|
test "value preview can be disabled" {
  let options = default_validation_options().with_value_preview(false)
  let report = validate(string(), test_json("1"), options~)
  assert_eq(report.issues[0].value_preview, "")
}

///|
test "fail fast stops after first error" {
  let rule = all_of([
    string_rule(min_length=Some(5)),
    string_rule(prefix=Some("x")),
  ])
  let report = validate(
    rule,
    test_json("\"a\""),
    options=default_validation_options().with_fail_fast(true),
  )
  assert_eq(report.stats.error_count, 1)
}

///|
test "max issues truncates report" {
  let rule = strict_object([
    property("a", string()),
    property("b", string()),
    property("c", string()),
  ])
  let report = validate(
    rule,
    test_json("{}"),
    options=default_validation_options().with_max_issues(2),
  )
  assert_eq(report.issues.length(), 2)
}

///|
test "json kind identifies integer" {
  assert_eq(json_kind(test_json("2")), IntegerValue)
}

///|
test "json kind identifies number" {
  assert_eq(json_kind(test_json("2.5")), NumberValue)
}

///|
test "json kind identifies containers" {
  assert_eq(json_kind(test_json("[]")), ArrayValue)
  assert_eq(json_kind(test_json("{}")), ObjectValue)
}

///|
test "kind names are stable" {
  assert_eq(kind_name(StringValue), "string")
  assert_eq(kind_name(IntegerValue), "integer")
}

///|
test "json pointer resolves object" {
  let value = test_json("{\"user\":{\"name\":\"gale\"}}")
  assert_eq(json_at_path(value, "/user/name"), Some("gale".to_json()))
}

///|
test "json pointer resolves array index" {
  let value = test_json("{\"items\":[10,20]}")
  assert_eq(json_at_path(value, "/items/1"), Some(test_json("20")))
}

///|
test "json pointer unescapes slash" {
  let value = test_json("{\"a/b\":1}")
  assert_eq(json_at_path(value, "/a~1b"), Some(test_json("1")))
}

///|
test "dot path resolves nested value" {
  let value = test_json("{\"user\":{\"active\":true}}")
  assert_eq(json_at_path(value, "user.active"), Some(true.to_json()))
}

///|
test "missing path returns none" {
  assert_eq(json_at_path(test_json("{}"), "/missing"), None)
}

///|
test "pointer segment escapes reserved characters" {
  assert_eq(escape_pointer_segment("a/b~c"), "a~1b~0c")
}

///|
test "child paths enumerate object" {
  let paths = child_paths(test_json("{\"a\":1,\"b\":2}"))
  assert_eq(paths.length(), 2)
  assert_true(paths.contains("/a"))
}

///|
test "json preview truncates long value" {
  let preview = json_preview(
    test_json("\"abcdefghijklmnopqrstuvwxyz\""),
    maximum_length=12,
  )
  assert_true(preview.has_suffix("..."))
}

///|
test "glob exact match" {
  assert_true(glob_matches("hello", "hello"))
  assert_false(glob_matches("hello", "Hello"))
}

///|
test "glob star match" {
  assert_true(glob_matches("api-*", "api-users"))
  assert_true(glob_matches("*", "anything"))
}

///|
test "glob question mark" {
  assert_true(glob_matches("v?.json", "v1.json"))
  assert_false(glob_matches("v?.json", "v10.json"))
}

///|
test "glob ignore case" {
  assert_true(glob_matches("API-*", "api-users", case_sensitive=false))
}

///|
test "identifier format" {
  assert_true(is_identifier("user_id2"))
  assert_false(is_identifier("2user"))
}

///|
test "slug format" {
  assert_true(is_slug("moon-guard-1"))
  assert_false(is_slug("Moon Guard"))
}

///|
test "hostname format" {
  assert_true(is_hostname("api.example.com"))
  assert_false(is_hostname("-api.example.com"))
}

///|
test "email format" {
  assert_true(is_email("gale@example.com"))
  assert_false(is_email("gale@localhost"))
}

///|
test "email rejects repeated at" {
  assert_false(is_email("a@@example.com"))
}

///|
test "ipv4 format" {
  assert_true(is_ipv4("192.168.1.1"))
  assert_false(is_ipv4("256.1.1.1"))
}

///|
test "ipv4 rejects leading zero" {
  assert_false(is_ipv4("192.168.01.1"))
}

///|
test "ipv4 cidr format" {
  assert_true(is_ipv4_cidr("10.0.0.0/8"))
  assert_false(is_ipv4_cidr("10.0.0.0/33"))
}

///|
test "uuid format" {
  assert_true(is_uuid("550e8400-e29b-41d4-a716-446655440000"))
  assert_false(is_uuid("550e8400-e29b"))
}

///|
test "date format leap year" {
  assert_true(is_date("2024-02-29"))
  assert_false(is_date("2023-02-29"))
}

///|
test "date format rejects invalid month" {
  assert_false(is_date("2024-13-01"))
}

///|
test "time format" {
  assert_true(is_time("23:59:59Z"))
  assert_false(is_time("24:00:00"))
}

///|
test "datetime format" {
  assert_true(is_datetime("2026-07-27T12:30:00Z"))
  assert_false(is_datetime("2026-07-27 12:30:00"))
}

///|
test "uri format" {
  assert_true(is_uri("https://example.com/path"))
  assert_false(is_uri("not a uri"))
}

///|
test "semver format" {
  assert_true(is_semver("1.2.3-beta+build"))
  assert_false(is_semver("1.2"))
}

///|
test "base64 format" {
  assert_true(is_base64("SGVsbG8="))
  assert_false(is_base64("not base64"))
}

///|
test "base64url format" {
  assert_true(is_base64url("abc_DEF-123"))
  assert_false(is_base64url("abc+def"))
}

///|
test "jwt format" {
  assert_true(is_jwt("abc.def.ghi"))
  assert_false(is_jwt("abc.def"))
}

///|
test "mac address format" {
  assert_true(is_mac_address("00:1A:2B:3C:4D:5E"))
  assert_false(is_mac_address("00:1A:2B:3C"))
}

///|
test "credit card luhn format" {
  assert_true(is_credit_card("4111 1111 1111 1111"))
  assert_false(is_credit_card("4111 1111 1111 1112"))
}

///|
test "format registry lists email" {
  assert_true(supported_formats().contains("email"))
  assert_true(validate_format("gale@example.com", "email"))
}

///|
test "unknown format is rejected" {
  assert_false(validate_format("anything", "unknown-format"))
}

///|
test "string minimum length" {
  let rule = string_rule(min_length=Some(3))
  assert_true(test_valid(rule, "\"abc\""))
  assert_true(test_invalid(rule, "\"ab\""))
}

///|
test "string maximum length" {
  let rule = string_rule(max_length=Some(3))
  assert_true(test_valid(rule, "\"abc\""))
  assert_true(test_invalid(rule, "\"abcd\""))
}

///|
test "string exact unicode length" {
  let rule = string_rule(exact_length=Some(2))
  assert_true(test_valid(rule, "\"月兔\""))
}

///|
test "string prefix" {
  let rule = string_rule(prefix=Some("api-"))
  assert_true(test_valid(rule, "\"api-user\""))
  assert_true(test_invalid(rule, "\"web-user\""))
}

///|
test "string suffix" {
  let rule = string_rule(suffix=Some(".json"))
  assert_true(test_valid(rule, "\"data.json\""))
  assert_true(test_invalid(rule, "\"data.txt\""))
}

///|
test "string contains" {
  let rule = string_rule(contains=Some("guard"))
  assert_true(test_valid(rule, "\"moon-guard\""))
}

///|
test "string case insensitive constraints" {
  let rule = string_rule(prefix=Some("API"), case_sensitive=false)
  assert_true(test_valid(rule, "\"api-users\""))
}

///|
test "string pattern" {
  let rule = string_rule(pattern=Some("user-?"))
  assert_true(test_valid(rule, "\"user-1\""))
  assert_true(test_invalid(rule, "\"user-10\""))
}

///|
test "string email format policy" {
  let rule = string_rule(format=Some("email"))
  assert_true(test_valid(rule, "\"gale@example.com\""))
  assert_true(test_invalid(rule, "\"broken\""))
}

///|
test "string allowed values" {
  let rule = string_rule(allowed=["red", "green"])
  assert_true(test_valid(rule, "\"red\""))
  assert_true(test_invalid(rule, "\"blue\""))
}

///|
test "string forbidden values" {
  let rule = string_rule(forbidden=["root"])
  assert_true(test_invalid(rule, "\"root\""))
}

///|
test "string ascii only" {
  let rule = string_rule(ascii_only=true)
  assert_true(test_valid(rule, "\"hello\""))
  assert_true(test_invalid(rule, "\"月兔\""))
}

///|
test "string non blank" {
  let rule = string_rule(non_blank=true)
  assert_true(test_invalid(rule, "\"   \""))
  assert_true(test_valid(rule, "\" x \""))
}

///|
test "number inclusive range" {
  let rule = range(1.0, 10.0)
  assert_true(test_valid(rule, "1"))
  assert_true(test_valid(rule, "10"))
  assert_true(test_invalid(rule, "11"))
}

///|
test "number exclusive range" {
  let rule = number_rule(
    exclusive_minimum=Some(0.0),
    exclusive_maximum=Some(1.0),
  )
  assert_true(test_valid(rule, "0.5"))
  assert_true(test_invalid(rule, "0"))
}

///|
test "number multiple of decimal" {
  let rule = number_rule(multiple_of=Some(0.25))
  assert_true(test_valid(rule, "1.5"))
  assert_true(test_invalid(rule, "1.6"))
}

///|
test "positive number" {
  assert_true(test_valid(positive_number(), "1"))
  assert_true(test_invalid(positive_number(), "0"))
}

///|
test "negative number" {
  assert_true(test_valid(negative_number(), "-1"))
  assert_true(test_invalid(negative_number(), "1"))
}

///|
test "nonzero number" {
  let rule = number_rule(non_zero=true)
  assert_true(test_invalid(rule, "0"))
}

///|
test "number rule rejects string" {
  assert_true(test_invalid(number_rule(), "\"1\""))
}

///|
test "list of validates every item" {
  let rule = list_of(integer())
  assert_true(test_valid(rule, "[1,2,3]"))
  assert_true(test_invalid(rule, "[1,2.5]"))
}

///|
test "non empty list" {
  let rule = non_empty_list(string())
  assert_true(test_invalid(rule, "[]"))
  assert_true(test_valid(rule, "[\"a\"]"))
}

///|
test "array maximum items" {
  let rule = array_rule(max_items=Some(2))
  assert_true(test_invalid(rule, "[1,2,3]"))
}

///|
test "array unique items" {
  let rule = array_rule(unique_items=true)
  assert_true(test_valid(rule, "[1,2]"))
  assert_true(test_invalid(rule, "[1,1]"))
}

///|
test "tuple validates positions" {
  let rule = tuple([string(), integer()])
  assert_true(test_valid(rule, "[\"id\",2]"))
  assert_true(test_invalid(rule, "[2,\"id\"]"))
}

///|
test "tuple validates exact length" {
  let rule = tuple([string(), integer()])
  assert_true(test_invalid(rule, "[\"id\"]"))
}

///|
test "array contains minimum" {
  let rule = array_rule(contains=Some(integer()), min_contains=2)
  assert_true(test_valid(rule, "[1,2,\"x\"]"))
  assert_true(test_invalid(rule, "[1,\"x\"]"))
}

///|
test "array contains maximum" {
  let rule = array_rule(contains=Some(integer()), max_contains=Some(1))
  assert_true(test_invalid(rule, "[1,2]"))
}

///|
test "array issue path includes index" {
  let report = validate(list_of(string()), test_json("[\"ok\",2]"))
  assert_eq(report.issues[0].path, "/1")
}

///|
test "required property" {
  let rule = object_rule(properties=[property("id", string())])
  let report = validate(rule, test_json("{}"))
  assert_false(report.valid)
  assert_eq(report.issues[0].path, "/id")
}

///|
test "optional property may be missing" {
  let rule = object_rule(properties=[optional_property("name", string())])
  assert_true(test_valid(rule, "{}"))
}

///|
test "strict object rejects extra property" {
  let rule = strict_object([property("id", integer())])
  assert_true(test_invalid(rule, "{\"id\":1,\"extra\":2}"))
}

///|
test "additional property rule" {
  let rule = object_rule(additional_rule=Some(string()))
  assert_true(test_valid(rule, "{\"x\":\"ok\"}"))
  assert_true(test_invalid(rule, "{\"x\":1}"))
}

///|
test "object minimum properties" {
  let rule = object_rule(min_properties=Some(2))
  assert_true(test_invalid(rule, "{\"x\":1}"))
}

///|
test "object maximum properties" {
  let rule = object_rule(max_properties=Some(1))
  assert_true(test_invalid(rule, "{\"x\":1,\"y\":2}"))
}

///|
test "property dependency" {
  let rule = object_rule(dependencies=[dependency("card", ["billingAddress"])])
  assert_true(test_invalid(rule, "{\"card\":\"x\"}"))
  assert_true(test_valid(rule, "{\"card\":\"x\",\"billingAddress\":{}}"))
}

///|
test "mutually exclusive properties" {
  let rule = object_rule(mutually_exclusive=[["password", "token"]])
  assert_true(test_invalid(rule, "{\"password\":\"x\",\"token\":\"y\"}"))
}

///|
test "at least one property group" {
  let rule = object_rule(at_least_one=[["email", "phone"]])
  assert_true(test_invalid(rule, "{}"))
  assert_true(test_valid(rule, "{\"email\":\"a\"}"))
}

///|
test "deprecated property emits warning only" {
  let rule = object_rule(properties=[deprecated_property("old", string())])
  let report = validate(rule, test_json("{\"old\":\"x\"}"))
  assert_true(report.valid)
  assert_eq(report.stats.warning_count, 1)
}

///|
test "warnings can be disabled" {
  let rule = object_rule(properties=[deprecated_property("old", string())])
  let report = validate(
    rule,
    test_json("{\"old\":\"x\"}"),
    options=default_validation_options().with_warnings(false),
  )
  assert_eq(report.issues.length(), 0)
}

///|
test "nested object issue path" {
  let rule = strict_object([
    property("user", strict_object([property("age", integer())])),
  ])
  let report = validate(rule, test_json("{\"user\":{\"age\":1.5}}"))
  assert_eq(report.issues[0].path, "/user/age")
}

///|
test "equals value" {
  assert_true(test_valid(equals("ok".to_json()), "\"ok\""))
  assert_true(test_invalid(equals("ok".to_json()), "\"no\""))
}

///|
test "literal constructors" {
  assert_true(test_valid(literal_string("x"), "\"x\""))
  assert_true(test_valid(literal_number(2.0), "2"))
}

///|
test "one of values" {
  let rule = one_of_strings(["small", "large"])
  assert_true(test_valid(rule, "\"small\""))
  assert_true(test_invalid(rule, "\"medium\""))
}

///|
test "all of requires every rule" {
  let rule = all_of([
    string_rule(min_length=Some(2)),
    string_rule(prefix=Some("a")),
  ])
  assert_true(test_valid(rule, "\"ab\""))
  assert_true(test_invalid(rule, "\"xb\""))
}

///|
test "any of accepts an alternative" {
  let rule = any_of([string(), integer()])
  assert_true(test_valid(rule, "\"x\""))
  assert_true(test_valid(rule, "2"))
  assert_true(test_invalid(rule, "false"))
}

///|
test "one of requires exactly one alternative" {
  let rule = exactly_one_of([number(), integer()])
  assert_true(test_invalid(rule, "2"))
  assert_true(test_valid(rule, "2.5"))
}

///|
test "none of forbids every matching alternative" {
  let rule = none_of([null_value(), boolean()])
  assert_true(test_valid(rule, "1"))
  assert_true(test_invalid(rule, "null"))
}

///|
test "not rule negates child" {
  let rule = not_rule(string())
  assert_true(test_valid(rule, "1"))
  assert_true(test_invalid(rule, "\"x\""))
}

///|
test "nullable accepts null" {
  let rule = nullable(string())
  assert_true(test_valid(rule, "null"))
  assert_true(test_valid(rule, "\"x\""))
}

///|
test "optional accepts null" {
  assert_true(test_valid(optional(integer()), "null"))
}

///|
test "conditional then branch" {
  let rule = all_of([
    object(),
    when(Equals("/type", "business".to_json()), at_path("/taxId", string())),
  ])
  assert_true(test_valid(rule, "{\"type\":\"business\",\"taxId\":\"123\"}"))
  assert_true(test_invalid(rule, "{\"type\":\"business\"}"))
}

///|
test "conditional else branch" {
  let rule = when(
    Exists("/x"),
    at_path("/x", integer()),
    else_rule=Some(at_path("/y", string())),
  )
  assert_true(test_valid(rule, "{\"y\":\"ok\"}"))
  assert_true(test_invalid(rule, "{\"y\":2}"))
}

///|
test "predicate all" {
  let predicate : Predicate = AllPredicates([
    Exists("/a"),
    KindIs("/a", IntegerValue),
  ])
  let rule = when(predicate, Accept, else_rule=Some(Reject("bad")))
  assert_true(test_valid(rule, "{\"a\":1}"))
  assert_true(test_invalid(rule, "{\"a\":\"1\"}"))
}

///|
test "predicate any" {
  let predicate : Predicate = AnyPredicate([Exists("/email"), Exists("/phone")])
  assert_true(
    test_valid(
      when(predicate, Accept, else_rule=Some(reject())),
      "{\"phone\":\"1\"}",
    ),
  )
}

///|
test "predicate not" {
  let rule = when(
    NotPredicate(Exists("/blocked")),
    Accept,
    else_rule=Some(reject()),
  )
  assert_true(test_valid(rule, "{}"))
  assert_true(test_invalid(rule, "{\"blocked\":true}"))
}

///|
test "predicate validates nested value" {
  let predicate : Predicate = Validates("/age", number_rule(minimum=Some(18.0)))
  let rule = when(predicate, Accept, else_rule=Some(Reject("minor")))
  assert_true(test_valid(rule, "{\"age\":20}"))
  assert_true(test_invalid(rule, "{\"age\":10}"))
}

///|
test "named rule appears in issue" {
  let report = validate(
    named("username", string_rule(min_length=Some(3))),
    test_json("\"x\""),
  )
  assert_eq(report.issues[0].rule_name, "username")
}

///|
test "warning rule never invalidates" {
  let report = validate(
    warning("prefer uuid", string_rule(format=Some("uuid"))),
    test_json("\"legacy\""),
  )
  assert_true(report.valid)
  assert_eq(report.stats.warning_count, 1)
}

///|
test "first issue helper" {
  let report = validate(string(), test_json("1"))
  assert_true(first_issue(report) is Some(_))
}

///|
test "issues at helper" {
  let report = validate(
    strict_object([property("id", string())]),
    test_json("{}"),
  )
  assert_eq(issues_at(report, "/id").length(), 1)
}

///|
test "error and warning filters" {
  let rule = all_of([string(), warning("warn", integer())])
  let report = validate(rule, test_json("\"x\""))
  assert_eq(error_issues(report).length(), 0)
  assert_eq(warning_issues(report).length(), 1)
}

///|
test "report JSON contains issue fields" {
  let encoded = report_to_json(validate(string(), test_json("1")))
  assert_true(encoded.contains("type.mismatch"))
  assert_true(encoded.contains("issues"))
}

///|
test "parse boolean schema" {
  assert_true(rule_from_json("true") is Some(_))
  assert_true(rule_from_json("false") is Some(_))
}

///|
test "parse type schema" {
  match rule_from_json("{\"type\":\"string\"}") {
    Some(rule) => assert_true(test_valid(rule, "\"x\""))
    None => fail("expected rule")
  }
}

///|
test "parse string keywords" {
  let schema = "{\"type\":\"string\",\"minLength\":3,\"format\":\"email\"}"
  match rule_from_json(schema) {
    Some(rule) => assert_true(test_valid(rule, "\"a@example.com\""))
    None => fail("expected rule")
  }
}

///|
test "parse number keywords" {
  let schema = "{\"type\":\"number\",\"minimum\":1,\"maximum\":2}"
  match rule_from_json(schema) {
    Some(rule) => assert_true(test_invalid(rule, "3"))
    None => fail("expected rule")
  }
}

///|
test "parse array item schema" {
  let schema = "{\"type\":\"array\",\"items\":{\"type\":\"integer\"},\"uniqueItems\":true}"
  match rule_from_json(schema) {
    Some(rule) => assert_true(test_invalid(rule, "[1,1]"))
    None => fail("expected rule")
  }
}

///|
test "parse object properties" {
  let schema =
    #|{"type":"object","properties":{"id":{"type":"integer"}},"required":["id"],"additionalProperties":false}
  match rule_from_json(schema) {
    Some(rule) => {
      assert_true(test_valid(rule, "{\"id\":1}"))
      assert_true(test_invalid(rule, "{}"))
    }
    None => fail("expected rule")
  }
}

///|
test "parse dependent required" {
  let schema =
    #|{"dependentRequired":{"card":["address"]}}
  match rule_from_json(schema) {
    Some(rule) => assert_true(test_invalid(rule, "{\"card\":1}"))
    None => fail("expected rule")
  }
}

///|
test "parse combinators" {
  let schema =
    #|{"anyOf":[{"type":"string"},{"type":"integer"}]}
  match rule_from_json(schema) {
    Some(rule) => assert_true(test_valid(rule, "2"))
    None => fail("expected rule")
  }
}

///|
test "parse conditional" {
  let schema =
    #|{"when":{"path":"/kind","equals":"x"},"then":{"atPath":"/value","type":"integer"}}
  match rule_from_json(schema) {
    Some(rule) => assert_true(test_valid(rule, "{\"kind\":\"x\",\"value\":2}"))
    None => fail("expected rule")
  }
}

///|
test "parse invalid JSON reports error" {
  let result = parse_rule_document("{bad")
  assert_true(result.rule is None)
  assert_eq(result.errors.length(), 1)
}

///|
test "parse unknown type reports error" {
  let result = parse_rule_document("{\"type\":\"mystery\"}")
  assert_true(result.rule is None)
  assert_true(!result.errors.is_empty())
}

///|
test "parse malformed required reports error" {
  let result = parse_rule_document("{\"required\":true}")
  assert_true(result.rule is None)
}

///|
test "parse required without property warns" {
  let result = parse_rule_document("{\"required\":[\"id\"]}")
  assert_true(result.rule is Some(_))
  assert_eq(result.warnings.length(), 1)
}

///|
test "rule export is parseable" {
  let encoded = rule_to_json(sample_user_rule())
  assert_true(rule_from_json(encoded) is Some(_))
}

///|
test "rule round trip preserves behavior" {
  match rule_round_trip(string_rule(min_length=Some(2))) {
    Some(rule) => {
      assert_true(test_valid(rule, "\"ok\""))
      assert_true(test_invalid(rule, "\"x\""))
    }
    None => fail("round trip failed")
  }
}

///|
test "rule export includes name" {
  let encoded = rule_to_json(named("id", integer(), description="identifier"))
  assert_true(encoded.contains("$name"))
  assert_true(encoded.contains("description"))
}

///|
test "rule analysis counts nodes" {
  let analysis = analyze_rule(all_of([string(), not_rule(null_value())]))
  assert_true(analysis.node_count >= 4)
  assert_true(analysis.maximum_depth >= 1)
}

///|
test "rule analysis counts object properties" {
  let analysis = analyze_rule(sample_user_rule())
  assert_eq(analysis.object_property_count, 6)
  assert_true(analysis.named_rules.contains("user-registration"))
}

///|
test "rule analysis finds invalid range" {
  let analysis = analyze_rule(
    number_rule(minimum=Some(10.0), maximum=Some(1.0)),
  )
  assert_true(!analysis.warnings.is_empty())
  assert_false(
    rule_is_well_formed(number_rule(minimum=Some(10.0), maximum=Some(1.0))),
  )
}

///|
test "rule analysis finds unknown format" {
  let analysis = analyze_rule(string_rule(format=Some("mystery")))
  assert_true(!analysis.warnings.is_empty())
}

///|
test "rule outline includes properties" {
  let outline = rule_outline(sample_user_rule())
  assert_true(outline.contains("user-registration"))
  assert_true(outline.contains("property email"))
}

///|
test "rule optimization removes accept from allOf" {
  let optimized = optimize_rule(all_of([Accept, string()]))
  assert_eq(rule_node_count(optimized), 1)
  assert_true(test_valid(optimized, "\"x\""))
}

///|
test "batch validation counts passes" {
  let cases : Array[ValidationCase] = [
    { id: "a", value: test_json("1"), },
    { id: "b", value: test_json("2"), },
    { id: "c", value: "x".to_json(), },
  ]
  let report = validate_batch(integer(), cases)
  assert_eq(report.passed, 2)
  assert_eq(report.failed, 1)
}

///|
test "JSON array batch" {
  let report = validate_json_array(integer(), "[1,2,\"x\"]")
  assert_eq(report.total, 3)
  assert_eq(report.failed, 1)
}

///|
test "JSON lines batch skips blanks" {
  let report = validate_json_lines(integer(), "1\n\n2\n\"x\"")
  assert_eq(report.total, 3)
  assert_eq(report.failed, 1)
  assert_eq(report.cases[1].id, "3")
}

///|
test "batch issue histogram" {
  let report = validate_json_array(string(), "[1,2]")
  let counts = batch_issue_histogram(report)
  assert_eq(counts[0].code, "type.mismatch")
  assert_eq(counts[0].count, 2)
}

///|
test "batch summary reports failure" {
  let report = validate_json_array(integer(), "[1,\"x\"]")
  assert_true(batch_summary(report).has_prefix("FAIL"))
}

///|
test "batch JSON encodes cases" {
  let encoded = batch_to_json(validate_json_array(integer(), "[1]"))
  assert_true(encoded.contains("cases"))
}

///|
test "merge reports sums errors" {
  let merged = merge_reports([
    validate(string(), test_json("1")),
    validate(integer(), "x".to_json()),
  ])
  assert_eq(merged.stats.error_count, 2)
  assert_eq(merged.issues.length(), 2)
}

///|
test "prefix report paths" {
  let report = validate(
    strict_object([property("id", string())]),
    test_json("{}"),
  )
  let prefixed = prefix_report_paths(report, "/request")
  assert_eq(prefixed.issues[0].path, "/request/id")
}

///|
test "sample user accepts valid payload" {
  assert_true(validate_json(sample_user_rule(), sample_valid_user_json()).valid)
}

///|
test "sample user rejects invalid payload" {
  let report = validate_json(sample_user_rule(), sample_invalid_user_json())
  assert_false(report.valid)
  assert_true(report.stats.error_count >= 5)
}

///|
test "sample order accepts order" {
  let value =
    #|{"orderId":"550e8400-e29b-41d4-a716-446655440000","currency":"CNY","items":[{"sku":"SKU-1","quantity":2,"unitPrice":9.99}]}
  assert_true(validate_json(sample_order_rule(), value).valid)
}

///|
test "sample order rejects empty items" {
  let value =
    #|{"orderId":"550e8400-e29b-41d4-a716-446655440000","currency":"CNY","items":[]}
  assert_false(validate_json(sample_order_rule(), value).valid)
}

///|
test "sample webhook ping needs no data" {
  let value =
    #|{"event":"ping","timestamp":"2026-07-27T12:30:00Z","signature":"12345678901234567890123456789012"}
  assert_true(validate_json(sample_webhook_rule(), value).valid)
}

///|
test "sample webhook payment needs data" {
  let value =
    #|{"event":"payment.succeeded","timestamp":"2026-07-27T12:30:00Z","signature":"12345678901234567890123456789012"}
  assert_false(validate_json(sample_webhook_rule(), value).valid)
}
