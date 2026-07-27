///|
/// Demonstrates loading a validation policy from a JSON document at runtime.
fn main {
  let schema =
    #|{
    #|  "$name": "login-request",
    #|  "type": "object",
    #|  "additionalProperties": false,
    #|  "required": ["account", "password"],
    #|  "properties": {
    #|    "account": {"type": "string", "minLength": 3, "maxLength": 254},
    #|    "password": {"type": "string", "minLength": 8, "maxLength": 128},
    #|    "remember": {"type": "boolean"}
    #|  }
    #|}
  match @guard.rule_from_json(schema) {
    None => println("schema could not be parsed")
    Some(rule) => {
      println(@guard.rule_outline(rule))
      let payload = "{\"account\":\"gale@example.com\",\"password\":\"moonbit-2026\"}"
      println(@guard.report_to_json(@guard.validate_json(rule, payload)))
    }
  }
}
