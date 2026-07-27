///|
/// MoonGuard's zero-configuration demonstration.
fn main {
  let rule = @guard.sample_user_rule()
  let report = @guard.validate_json(rule, @guard.sample_invalid_user_json())
  println("MoonGuard user-registration validation demo")
  println(@guard.report_to_json(report))
}
