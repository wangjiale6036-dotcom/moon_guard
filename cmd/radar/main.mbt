///|
fn radar_case(id : String, text : String) -> @guard.ValidationCase {
  let value = @json.parse(text) catch { _ => Json::null() }
  { id, value, }
}

///|
fn version_text(version : Int?) -> String {
  match version {
    Some(value) => value.to_string()
    None => "none"
  }
}

///|
fn print_regression_witnesses(report : @guard.ShadowReport) -> Unit {
  let witnesses = @guard.regression_witnesses(report)
  println("regression witnesses: \{witnesses.length()}")
  for witness in witnesses {
    println("  - \{witness.id}: \{witness.value.stringify()}")
  }
}

///|
/// Compatibility Radar demo: static contract inference, opt-in replay
/// witnesses, rollout assessment, guarded promotion and deterministic canary
/// bucketing. Every payload below is synthetic demo data.
fn main {
  let channel = "client-profile"
  let registry = @guard.new_rule_registry()
  let baseline =
    #|{
    #|  "$name": "client-profile-v1",
    #|  "type": "object",
    #|  "additionalProperties": false,
    #|  "required": ["client_id", "email"],
    #|  "properties": {
    #|    "client_id": {"type": "string", "format": "slug"},
    #|    "email": {"type": "string", "format": "email"},
    #|    "region": {"enum": ["cn", "sg", "eu"]},
    #|    "age": {"type": "integer", "minimum": 13}
    #|  }
    #|}
  let candidate =
    #|{
    #|  "$name": "client-profile-v2",
    #|  "type": "object",
    #|  "additionalProperties": false,
    #|  "required": ["client_id", "email", "region"],
    #|  "properties": {
    #|    "client_id": {"type": "string", "format": "slug"},
    #|    "email": {"type": "string", "format": "email"},
    #|    "region": {"enum": ["cn", "sg", "eu"]},
    #|    "age": {"type": "integer", "minimum": 18}
    #|  }
    #|}

  println("=== MoonGuard Compatibility Radar ===")
  let first = registry.publish_json(
    channel,
    baseline,
    note="baseline contract",
    published_by="radar-demo",
  )
  let second = registry.publish_json(
    channel,
    candidate,
    note="candidate requires region and adult age",
    published_by="radar-demo",
  )
  println("\n[1] Published revisions")
  println(ToJson::to_json(first).stringify())
  println(ToJson::to_json(second).stringify())
  println("active version: \{version_text(registry.active_version(channel))}")

  println("\n[2] Static compare_with_active")
  let static_result = registry.compare_with_active(channel, 2)
  println(ToJson::to_json(static_result).stringify(indent=2))

  let callers : Array[@guard.ValidationCase] = [
    radar_case(
      "web-current", "{\"client_id\":\"web-current\",\"email\":\"web@example.test\",\"region\":\"cn\",\"age\":25}",
    ),
    radar_case(
      "ios-legacy", "{\"client_id\":\"ios-legacy\",\"email\":\"ios@example.test\",\"age\":20}",
    ),
    radar_case(
      "youth-app", "{\"client_id\":\"youth-app\",\"email\":\"youth@example.test\",\"region\":\"cn\",\"age\":15}",
    ),
    radar_case(
      "malformed-email", "{\"client_id\":\"bad-email\",\"email\":\"not-an-email\",\"region\":\"sg\",\"age\":30}",
    ),
    radar_case(
      "batch-worker", "{\"client_id\":\"batch-worker\",\"email\":\"batch@example.test\",\"region\":\"eu\"}",
    ),
  ]

  println("\n[3] Shadow replay (5 synthetic callers)")
  println(
    "payload capture defaults to OFF; this demo explicitly enables it for synthetic regression witnesses only",
  )
  let shadow_result = registry.shadow_with_active(
    channel,
    2,
    callers,
    capture_witnesses=true,
  )
  match shadow_result.report {
    None => println("shadow replay unavailable")
    Some(shadow_report) => {
      println(ToJson::to_json(shadow_report.metrics).stringify(indent=2))
      print_regression_witnesses(shadow_report)

      println("\n[4] Rollout assessment")
      let policy = @guard.rollout_policy(min_samples=4)
      let assessment = @guard.assess_rollout(
        static_result.report,
        shadow_report,
        policy~,
      )
      println(@guard.rollout_assessment_to_json(assessment))

      println("\n[5] Guarded promotion")
      let before = registry.active_version(channel)
      let promotion = registry.promote_if_safe(channel, 2, callers, policy~)
      let after = registry.active_version(channel)
      println(ToJson::to_json(promotion).stringify(indent=2))
      println(
        "active version before=\{version_text(before)}, after=\{version_text(after)} (candidate blocked)",
      )
    }
  }

  println("\n[6] Stable canary bucket")
  let routing_key = "demo-tenant-42"
  let first_bucket = @guard.stable_rollout_bucket(routing_key)
  let second_bucket = @guard.stable_rollout_bucket(routing_key)
  println(
    "key=\{routing_key}, bucket=\{first_bucket}, repeated=\{second_bucket}, selected_at_10_percent=\{@guard.is_canary_selected(routing_key, 1000)}",
  )
}
