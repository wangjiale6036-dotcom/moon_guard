///|
fn registry_json(text : String) -> Json {
  @json.parse(text) catch {
    _ => Json::null()
  }
}

///|
test "new registry is empty" {
  let registry = new_rule_registry()
  assert_eq(registry.channel_count(), 0)
  assert_eq(registry.channel_names(), [])
}

///|
test "first publish creates active revision" {
  let registry = new_rule_registry()
  let result = registry.publish_rule("users", string())
  assert_true(result.ok)
  assert_eq(result.version, Some(1))
  assert_eq(registry.channel_count(), 1)
  assert_eq(registry.active_version("users"), Some(1))
}

///|
test "later publish remains inactive" {
  let registry = new_rule_registry()
  ignore(registry.publish_rule("users", string()))
  ignore(registry.publish_rule("users", integer()))
  assert_eq(registry.revision_count("users"), 2)
  assert_eq(registry.active_version("users"), Some(1))
}

///|
test "publish keeps metadata and canonical schema" {
  let registry = new_rule_registry()
  ignore(
    registry.publish_rule(
      "users",
      string(),
      note="initial contract",
      published_by="gale",
    ),
  )
  match registry.get_revision("users", 1) {
    None => fail("revision missing")
    Some(revision) => {
      assert_eq(revision.note, "initial contract")
      assert_eq(revision.published_by, "gale")
      assert_true(revision.schema_json.length() > 0)
    }
  }
}

///|
test "publish preserves supplied schema document" {
  let registry = new_rule_registry()
  ignore(
    registry.publish_rule(
      "users",
      string(),
      schema_json="{\"type\":\"string\"}",
    ),
  )
  assert_eq(
    registry.get_revision("users", 1).unwrap().schema_json,
    "{\"type\":\"string\"}",
  )
}

///|
test "empty channel is rejected" {
  let registry = new_rule_registry()
  let result = registry.publish_rule("   ", string())
  assert_false(result.ok)
  assert_eq(result.code, "registry.channel.empty")
  assert_eq(registry.channel_count(), 0)
}

///|
test "invalid channel slug is rejected" {
  let registry = new_rule_registry()
  let result = registry.publish_rule("User Contract", string())
  assert_false(result.ok)
  assert_eq(result.code, "registry.channel.invalid")
}

///|
test "unknown revision queries are empty" {
  let registry = new_rule_registry()
  assert_eq(registry.revision_count("missing"), 0)
  assert_true(registry.get_revision("missing", 1) is None)
  assert_true(registry.active_revision("missing") is None)
  assert_eq(registry.list_revisions("missing"), [])
}

///|
test "channel names preserve creation order" {
  let registry = new_rule_registry()
  ignore(registry.publish_rule("users", string()))
  ignore(registry.publish_rule("orders", object()))
  assert_eq(registry.channel_names(), ["users", "orders"])
}

///|
test "dynamic JSON rule can be published" {
  let registry = new_rule_registry()
  let result = registry.publish_json("users", "{\"type\":\"string\"}")
  assert_true(result.ok)
  assert_eq(registry.active_version("users"), Some(1))
}

///|
test "dynamic JSON syntax failure is reported" {
  let registry = new_rule_registry()
  let result = registry.publish_json("users", "{bad")
  assert_false(result.ok)
  assert_eq(result.code, "registry.schema.invalid")
  assert_eq(registry.channel_count(), 0)
}

///|
test "dynamic JSON semantic failure is reported" {
  let registry = new_rule_registry()
  let result = registry.publish_json("users", "{\"type\":\"unknown\"}")
  assert_false(result.ok)
  assert_eq(result.code, "registry.schema.invalid")
}

///|
test "duplicate code rule is not appended" {
  let registry = new_rule_registry()
  ignore(registry.publish_rule("users", string()))
  let result = registry.publish_rule("users", string())
  assert_false(result.ok)
  assert_eq(result.code, "registry.rule.duplicate")
  assert_eq(registry.revision_count("users"), 1)
}

///|
test "semantically duplicate JSON rule is not appended" {
  let registry = new_rule_registry()
  ignore(registry.publish_json("users", "{\"type\":\"string\"}"))
  let result = registry.publish_json("users", "{ \"type\" : \"string\" }")
  assert_false(result.ok)
  assert_eq(result.code, "registry.rule.duplicate")
  assert_eq(registry.revision_count("users"), 1)
}

///|
test "different dynamic rule creates next version" {
  let registry = new_rule_registry()
  ignore(registry.publish_json("users", "{\"type\":\"string\"}"))
  let result = registry.publish_json("users", "{\"type\":\"integer\"}")
  assert_true(result.ok)
  assert_eq(result.version, Some(2))
}

///|
test "dynamic publish preserves author and note" {
  let registry = new_rule_registry()
  ignore(
    registry.publish_json(
      "users",
      "{\"type\":\"string\"}",
      note="API v1",
      published_by="gale",
    ),
  )
  let revision = registry.get_revision("users", 1).unwrap()
  assert_eq(revision.note, "API v1")
  assert_eq(revision.published_by, "gale")
}

///|
test "invalid dynamic publish does not disturb active rule" {
  let registry = new_rule_registry()
  ignore(registry.publish_rule("users", string()))
  ignore(registry.publish_json("users", "{\"type\":\"unknown\"}"))
  assert_eq(registry.active_version("users"), Some(1))
  assert_eq(registry.revision_count("users"), 1)
}

///|
test "published revision can be activated" {
  let registry = new_rule_registry()
  ignore(registry.publish_rule("users", string()))
  ignore(registry.publish_rule("users", integer()))
  let result = registry.activate("users", 2)
  assert_true(result.ok)
  assert_eq(registry.active_version("users"), Some(2))
}

///|
test "activation rejects missing channel" {
  let result = new_rule_registry().activate("missing", 1)
  assert_false(result.ok)
  assert_eq(result.code, "registry.channel.missing")
}

///|
test "activation rejects missing version" {
  let registry = new_rule_registry()
  ignore(registry.publish_rule("users", string()))
  let result = registry.activate("users", 9)
  assert_false(result.ok)
  assert_eq(result.code, "registry.version.missing")
}

///|
test "rollback selects previous revision" {
  let registry = new_rule_registry()
  ignore(registry.publish_rule("users", string()))
  ignore(registry.publish_rule("users", integer()))
  ignore(registry.activate("users", 2))
  let result = registry.rollback("users")
  assert_true(result.ok)
  assert_eq(registry.active_version("users"), Some(1))
}

///|
test "rollback reports unavailable history" {
  let registry = new_rule_registry()
  ignore(registry.publish_rule("users", string()))
  let result = registry.rollback("users")
  assert_false(result.ok)
  assert_eq(result.code, "registry.rollback.unavailable")
}

///|
test "active validation records version" {
  let registry = new_rule_registry()
  ignore(registry.publish_rule("users", string()))
  let result = registry.validate_active("users", "ok".to_json())
  assert_true(result.found)
  assert_eq(result.version, Some(1))
  assert_true(result.report.unwrap().valid)
}

///|
test "activation changes validation behavior" {
  let registry = new_rule_registry()
  ignore(registry.publish_rule("users", string()))
  ignore(registry.publish_rule("users", integer()))
  assert_false(
    registry.validate_active_json("users", "1").report.unwrap().valid,
  )
  ignore(registry.activate("users", 2))
  assert_true(registry.validate_active_json("users", "1").report.unwrap().valid)
}

///|
test "unknown active validation is explicit" {
  let result = new_rule_registry().validate_active_json("missing", "1")
  assert_false(result.found)
  assert_true(result.report is None)
}

///|
test "registry validates JSON array batch" {
  let registry = new_rule_registry()
  ignore(registry.publish_json("numbers", "{\"type\":\"integer\"}"))
  let result = registry.validate_active_json_array("numbers", "[1,2,\"x\"]")
  assert_true(result.found)
  assert_eq(result.report.unwrap().failed, 1)
}

///|
test "registry validates JSON Lines batch" {
  let registry = new_rule_registry()
  ignore(registry.publish_rule("numbers", integer()))
  let result = registry.validate_active_json_lines("numbers", "1\n2\n\"x\"")
  assert_true(result.found)
  assert_eq(result.report.unwrap().total, 3)
  assert_eq(result.report.unwrap().failed, 1)
}

///|
test "checked publish accepts compatible examples" {
  let registry = new_rule_registry()
  let cases : Array[ValidationCase] = [
    { id: "one", value: registry_json("1") },
    { id: "two", value: registry_json("2") },
  ]
  let gate = registry.publish_json_checked(
    "numbers", "{\"type\":\"integer\"}", cases,
  )
  assert_true(gate.published)
  assert_eq(registry.revision_count("numbers"), 1)
}

///|
test "checked publish rejects incompatible example" {
  let registry = new_rule_registry()
  let cases : Array[ValidationCase] = [{ id: "bad", value: "text".to_json() }]
  let gate = registry.publish_json_checked(
    "numbers", "{\"type\":\"integer\"}", cases,
  )
  assert_false(gate.published)
  assert_eq(gate.result.code, "registry.gate.failed")
  assert_eq(registry.channel_count(), 0)
}

///|
test "checked publish returns per-case diagnostics" {
  let registry = new_rule_registry()
  let cases : Array[ValidationCase] = [
    { id: "sample-42", value: "wrong".to_json() },
  ]
  let gate = registry.publish_json_checked(
    "numbers", "{\"type\":\"integer\"}", cases,
  )
  let report = gate.compatibility.unwrap()
  assert_eq(report.failed, 1)
  assert_eq(report.cases[0].id, "sample-42")
}

///|
test "checked publish reports schema failure before examples" {
  let registry = new_rule_registry()
  let gate = registry.publish_json_checked("numbers", "{bad", [
    { id: "one", value: registry_json("1") },
  ])
  assert_false(gate.published)
  assert_eq(gate.result.code, "registry.schema.invalid")
  assert_true(gate.compatibility is None)
}

///|
test "checked publish permits empty example set" {
  let registry = new_rule_registry()
  let cases : Array[ValidationCase] = []
  let gate = registry.publish_json_checked(
    "numbers", "{\"type\":\"integer\"}", cases,
  )
  assert_true(gate.published)
  assert_eq(gate.compatibility.unwrap().total, 0)
}

///|
test "checked second revision remains inactive" {
  let registry = new_rule_registry()
  ignore(registry.publish_rule("numbers", number()))
  let gate = registry.publish_json_checked(
    "numbers",
    "{\"type\":\"integer\"}",
    [{ id: "one", value: registry_json("1") }],
  )
  assert_true(gate.published)
  assert_eq(gate.result.version, Some(2))
  assert_eq(registry.active_version("numbers"), Some(1))
}

///|
test "checked duplicate does not append revision" {
  let registry = new_rule_registry()
  ignore(registry.publish_json("numbers", "{\"type\":\"integer\"}"))
  let gate = registry.publish_json_checked(
    "numbers",
    "{\"type\":\"integer\"}",
    [{ id: "one", value: registry_json("1") }],
  )
  assert_false(gate.published)
  assert_eq(gate.result.code, "registry.rule.duplicate")
  assert_eq(registry.revision_count("numbers"), 1)
}

///|
test "checked publish keeps release metadata" {
  let registry = new_rule_registry()
  let gate = registry.publish_json_checked(
    "numbers",
    "{\"type\":\"integer\"}",
    [{ id: "one", value: registry_json("1") }],
    note="validated contract",
    published_by="gale",
  )
  assert_true(gate.published)
  let revision = registry.get_revision("numbers", 1).unwrap()
  assert_eq(revision.note, "validated contract")
  assert_eq(revision.published_by, "gale")
}
