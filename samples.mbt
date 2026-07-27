///|
/// Example user-registration request schema.
pub fn sample_user_rule() -> Rule {
  named(
    "user-registration",
    strict_object([
      property("id", string_rule(format=Some("uuid"))),
      property("email", string_rule(format=Some("email"), max_length=Some(254))),
      property(
        "displayName",
        string_rule(min_length=Some(2), max_length=Some(80), non_blank=true),
      ),
      property(
        "age",
        number_rule(minimum=Some(13.0), maximum=Some(150.0), integer_only=true),
      ),
      optional_property("website", nullable(string_rule(format=Some("uri")))),
      optional_property(
        "roles",
        array_rule(
          items=Some(one_of_strings(["user", "editor", "admin"])),
          min_items=Some(1),
          unique_items=true,
        ),
      ),
    ]),
    description="Public API payload for creating a user account",
  )
}

///|
/// Example order schema with nested objects and arrays.
pub fn sample_order_rule() -> Rule {
  let line_item = strict_object([
    property("sku", string_rule(pattern=Some("SKU-*"), min_length=Some(5))),
    property("quantity", number_rule(minimum=Some(1.0), integer_only=true)),
    property(
      "unitPrice",
      number_rule(minimum=Some(0.0), multiple_of=Some(0.01)),
    ),
  ])
  named(
    "order-create",
    object_rule(
      properties=[
        property("orderId", string_rule(format=Some("uuid"))),
        property("currency", one_of_strings(["CNY", "USD", "EUR", "JPY"])),
        property(
          "items",
          array_rule(
            items=Some(line_item),
            min_items=Some(1),
            max_items=Some(200),
          ),
        ),
        optional_property("coupon", string_rule(pattern=Some("COUPON-*"))),
        optional_property("metadata", object()),
      ],
      allow_additional=false,
    ),
  )
}

///|
/// Webhook envelope with a conditional business payload.
pub fn sample_webhook_rule() -> Rule {
  all_of([
    strict_object([
      property(
        "event",
        one_of_strings(["ping", "payment.succeeded", "payment.failed"]),
      ),
      property("timestamp", string_rule(format=Some("date-time"))),
      property("signature", string_rule(min_length=Some(32), ascii_only=true)),
      optional_property("data", object()),
    ]),
    when(
      Equals("/event", "ping".to_json()),
      Accept,
      else_rule=Some(at_path("/data", object_rule(min_properties=Some(1)))),
    ),
  ])
}

///|
pub fn sample_valid_user_json() -> String {
  (
    #|{
    #|  "id": "550e8400-e29b-41d4-a716-446655440000",
    #|  "email": "gale@example.com",
    #|  "displayName": "gale",
    #|  "age": 20,
    #|  "roles": ["user"]
    #|}
  )
}

///|
pub fn sample_invalid_user_json() -> String {
  (
    #|{
    #|  "id": "not-a-uuid",
    #|  "email": "broken",
    #|  "displayName": " ",
    #|  "age": 8,
    #|  "roles": ["admin", "admin"],
    #|  "unexpected": true
    #|}
  )
}
