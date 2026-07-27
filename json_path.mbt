///|
/// Human-readable value category.
pub fn kind_name(value : ValueKind) -> String {
  match value {
    AnyValue => "any"
    NullValue => "null"
    BooleanValue => "boolean"
    NumberValue => "number"
    IntegerValue => "integer"
    StringValue => "string"
    ArrayValue => "array"
    ObjectValue => "object"
  }
}

///|
/// Determine the most specific category for a JSON value.
pub fn json_kind(value : Json) -> ValueKind {
  match value {
    Null => NullValue
    True | False => BooleanValue
    Number(number, ..) =>
      if number == number.round() {
        IntegerValue
      } else {
        NumberValue
      }
    String(_) => StringValue
    Array(_) => ArrayValue
    Object(_) => ObjectValue
  }
}

///|
pub fn value_matches_kind(value : Json, expected : ValueKind) -> Bool {
  match expected {
    AnyValue => true
    NumberValue => value is Number(_)
    IntegerValue =>
      match value {
        Number(number, ..) => number == number.round()
        _ => false
      }
    other => json_kind(value) == other
  }
}

///|
fn parse_non_negative_int(value : String) -> Int? {
  if value.is_empty() {
    return None
  }
  let mut result = 0
  for char in value {
    if !char.is_ascii_digit() {
      return None
    }
    result = result * 10 + char.to_int() - '0'.to_int()
  }
  Some(result)
}

///|
fn unescape_pointer_segment(value : String) -> String? {
  let result = StringBuilder()
  let chars = value.to_array()
  let mut index = 0
  while index < chars.length() {
    if chars[index] != '~' {
      result.write_char(chars[index])
      index += 1
      continue
    }
    if index + 1 >= chars.length() {
      return None
    }
    match chars[index + 1] {
      '0' => result.write_char('~')
      '1' => result.write_char('/')
      _ => return None
    }
    index += 2
  }
  Some(result.to_string())
}

///|
fn pointer_segments(path : String) -> Array[String]? {
  if path.is_empty() || path == "/" {
    return Some([])
  }
  if !path.has_prefix("/") {
    return None
  }
  let result : Array[String] = []
  let raw = path[1:].to_owned()
  for part in raw.split("/") {
    match unescape_pointer_segment(part.to_owned()) {
      Some(value) => result.push(value)
      None => return None
    }
  }
  Some(result)
}

///|
fn dot_segments(path : String) -> Array[String]? {
  if path.is_empty() || path == "$" {
    return Some([])
  }
  let raw = if path.has_prefix("$.") { path[2:].to_owned() } else { path }
  let result : Array[String] = []
  for part in raw.split(".") {
    let value = part.trim().to_owned()
    if value.is_empty() {
      return None
    }
    result.push(value)
  }
  Some(result)
}

///|
/// Resolve RFC 6901 JSON Pointer paths (`/user/name`) and a lightweight dot
/// notation (`user.name`). Empty path and `$` return the root.
pub fn json_at_path(root : Json, path : String) -> Json? {
  let segments = if path.has_prefix("/") {
    pointer_segments(path)
  } else {
    dot_segments(path)
  }
  let segments = match segments {
    Some(value) => value
    None => return None
  }
  let mut current = root
  for segment in segments {
    match current {
      Object(values) =>
        match values.get(segment) {
          Some(value) => current = value
          None => return None
        }
      Array(values) =>
        match parse_non_negative_int(segment) {
          Some(index) =>
            if index < values.length() {
              current = values[index]
            } else {
              return None
            }
          None => return None
        }
      _ => return None
    }
  }
  Some(current)
}

///|
pub fn path_exists(root : Json, path : String) -> Bool {
  json_at_path(root, path) is Some(_)
}

///|
pub fn escape_pointer_segment(value : String) -> String {
  value.replace_all(old="~", new="~0").replace_all(old="/", new="~1")
}

///|
/// Build a child path using the configured report style.
fn child_path(parent : String, segment : String, style : String) -> String {
  if style == "dot" {
    if parent.is_empty() || parent == "$" {
      "$.\{segment}"
    } else {
      "\{parent}.\{segment}"
    }
  } else if parent.is_empty() || parent == "/" {
    "/\{escape_pointer_segment(segment)}"
  } else {
    "\{parent}/\{escape_pointer_segment(segment)}"
  }
}

///|
pub fn root_path(style : String) -> String {
  if style == "dot" {
    "$"
  } else {
    ""
  }
}

///|
/// Compact value preview for error reports.
pub fn json_preview(value : Json, maximum_length? : Int = 120) -> String {
  let encoded = value.stringify()
  let maximum_length = maximum_length.max(8)
  if encoded.length() <= maximum_length {
    encoded
  } else {
    "\{encoded[:maximum_length - 3].to_owned()}..."
  }
}

///|
/// Return every direct child path of an array or object.
pub fn child_paths(
  value : Json,
  path? : String = "",
  style? : String = "json-pointer",
) -> Array[String] {
  let result : Array[String] = []
  match value {
    Array(values) =>
      for i = 0; i < values.length(); i = i + 1 {
        result.push(child_path(path, i.to_string(), style))
      }
    Object(values) =>
      for key, _ in values {
        result.push(child_path(path, key, style))
      }
    _ => ()
  }
  result
}
