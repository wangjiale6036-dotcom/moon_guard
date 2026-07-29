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
