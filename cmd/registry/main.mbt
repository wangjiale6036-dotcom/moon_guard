///|
fn demo_json(text : String) -> Json {
  @json.parse(text) catch {
    _ => Json::null()
  }
}

///|
/// End-to-end MVP flow: compatibility gate, version publication, explicit
/// activation, request validation, manifest export and rollback.
fn main {
  let registry = @guard.new_rule_registry()
  let v1 =
    #|{
    #|  "$name": "account-v1",
    #|  "type": "object",
    #|  "additionalProperties": false,
    #|  "required": ["email"],
    #|  "properties": {
    #|    "email": {"type": "string", "format": "email"}
    #|  }
    #|}
  let compatibility : Array[@guard.ValidationCase] = [
    {
      id: "existing-client",
      value: demo_json("{\"email\":\"gale@example.com\"}"),
    },
  ]
  let first = registry.publish_json_checked(
    "accounts",
    v1,
    compatibility,
    note="initial account contract",
    published_by="gale",
  )
  println("publish v1: \{first.result.to_json().stringify()}")

  let v2 =
    #|{
    #|  "$name": "account-v2",
    #|  "type": "object",
    #|  "additionalProperties": false,
    #|  "required": ["email", "age"],
    #|  "properties": {
    #|    "email": {"type": "string", "format": "email"},
    #|    "age": {"type": "integer", "minimum": 13}
    #|  }
    #|}
  let second = registry.publish_json(
    "accounts",
    v2,
    note="require minimum account age",
    published_by="gale",
  )
  println("publish v2: \{second.to_json().stringify()}")
  let activated = registry.activate("accounts", 2)
  println("activate v2: \{activated.to_json().stringify()}")

  let request = "{\"email\":\"gale@example.com\",\"age\":20}"
  let validated = registry.validate_active_json("accounts", request)
  println("active validation: \{validated.to_json().stringify(indent=2)}")
  println("manifest: \{registry.manifest_json()}")
  let rolled_back = registry.rollback("accounts")
  println("rollback: \{rolled_back.to_json().stringify()}")
}
