///|
fn ascii_lower(value : String) -> String {
  let result = StringBuilder()
  for char in value {
    result.write_char(char.to_ascii_lowercase())
  }
  result.to_string()
}

///|
pub fn text_equal(left : String, right : String, case_sensitive : Bool) -> Bool {
  if case_sensitive {
    left == right
  } else {
    left.equal_ignore_ascii_case(right)
  }
}

///|
pub fn text_has_prefix(
  value : String,
  prefix : String,
  case_sensitive : Bool,
) -> Bool {
  if case_sensitive {
    value.has_prefix(prefix)
  } else {
    ascii_lower(value).has_prefix(ascii_lower(prefix))
  }
}

///|
pub fn text_has_suffix(
  value : String,
  suffix : String,
  case_sensitive : Bool,
) -> Bool {
  if case_sensitive {
    value.has_suffix(suffix)
  } else {
    ascii_lower(value).has_suffix(ascii_lower(suffix))
  }
}

///|
pub fn text_contains(
  value : String,
  needle : String,
  case_sensitive : Bool,
) -> Bool {
  if case_sensitive {
    value.contains(needle)
  } else {
    ascii_lower(value).contains(ascii_lower(needle))
  }
}

///|
/// Glob matcher supporting `*` for any sequence and `?` for one Unicode
/// scalar. It uses dynamic programming and therefore avoids exponential
/// backtracking on untrusted patterns.
pub fn glob_matches(
  pattern : String,
  value : String,
  case_sensitive? : Bool = true,
) -> Bool {
  let pattern = if case_sensitive { pattern } else { ascii_lower(pattern) }
  let value = if case_sensitive { value } else { ascii_lower(value) }
  let tokens = pattern.to_array()
  let chars = value.to_array()
  let previous : Array[Bool] = Array::make(chars.length() + 1, false)
  previous[0] = true
  for token in tokens {
    let current : Array[Bool] = Array::make(chars.length() + 1, false)
    if token == '*' {
      current[0] = previous[0]
      for index = 1; index <= chars.length(); index = index + 1 {
        current[index] = previous[index] || current[index - 1]
      }
    } else {
      for index = 1; index <= chars.length(); index = index + 1 {
        current[index] = previous[index - 1] &&
          (token == '?' || token == chars[index - 1])
      }
    }
    for index = 0; index <= chars.length(); index = index + 1 {
      previous[index] = current[index]
    }
  }
  previous[chars.length()]
}

///|
fn all_ascii(value : String) -> Bool {
  for char in value {
    if char.to_int() > 127 {
      return false
    }
  }
  true
}

///|
fn is_ascii_alphanumeric_char(char : Char) -> Bool {
  char.is_ascii_alphabetic() || char.is_ascii_digit()
}

///|
fn all_digits(value : String) -> Bool {
  if value.is_empty() {
    return false
  }
  for char in value {
    if !char.is_ascii_digit() {
      return false
    }
  }
  true
}

///|
fn all_hex(value : String) -> Bool {
  if value.is_empty() {
    return false
  }
  for char in value {
    if !char.is_ascii_digit() &&
      !(char >= 'a' && char <= 'f') &&
      !(char >= 'A' && char <= 'F') {
      return false
    }
  }
  true
}

///|
fn parse_small_int(value : StringView) -> Int? {
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
pub fn is_identifier(value : String) -> Bool {
  let chars = value.to_array()
  if chars.is_empty() || !(chars[0].is_ascii_alphabetic() || chars[0] == '_') {
    return false
  }
  for index = 1; index < chars.length(); index = index + 1 {
    let char = chars[index]
    if !is_ascii_alphanumeric_char(char) && char != '_' {
      return false
    }
  }
  true
}

///|
pub fn is_slug(value : String) -> Bool {
  let chars = value.to_array()
  if chars.is_empty() || chars[0] == '-' || chars[chars.length() - 1] == '-' {
    return false
  }
  let mut previous_hyphen = false
  for char in chars {
    if char == '-' {
      if previous_hyphen {
        return false
      }
      previous_hyphen = true
    } else {
      if !char.is_ascii_lowercase() && !char.is_ascii_digit() {
        return false
      }
      previous_hyphen = false
    }
  }
  true
}

///|
pub fn is_hostname(value : String) -> Bool {
  if value.is_empty() || value.length() > 253 || !all_ascii(value) {
    return false
  }
  let normalized = if value.has_suffix(".") {
    value[:value.length() - 1].to_owned()
  } else {
    value
  }
  for raw in normalized.split(".") {
    let label = raw.to_owned()
    if label.is_empty() ||
      label.length() > 63 ||
      label.has_prefix("-") ||
      label.has_suffix("-") {
      return false
    }
    for char in label {
      if !is_ascii_alphanumeric_char(char) && char != '-' {
        return false
      }
    }
  }
  true
}

///|
pub fn is_email(value : String) -> Bool {
  if value.is_empty() || value.length() > 254 || !all_ascii(value) {
    return false
  }
  let parts = value.split("@").to_array()
  if parts.length() != 2 {
    return false
  }
  let local_part = parts[0].to_owned()
  let domain = parts[1].to_owned()
  if local_part.is_empty() ||
    local_part.length() > 64 ||
    local_part.has_prefix(".") ||
    local_part.has_suffix(".") ||
    local_part.contains("..") {
    return false
  }
  for char in local_part {
    let allowed_symbol = char == '.' ||
      char == '_' ||
      char == '%' ||
      char == '+' ||
      char == '-'
    if !is_ascii_alphanumeric_char(char) && !allowed_symbol {
      return false
    }
  }
  is_hostname(domain) && domain.contains(".")
}

///|
pub fn is_ipv4(value : String) -> Bool {
  let parts = value.split(".").to_array()
  if parts.length() != 4 {
    return false
  }
  for part in parts {
    if part.length() > 1 && part.has_prefix("0") {
      return false
    }
    match parse_small_int(part) {
      Some(number) => if number > 255 { return false }
      None => return false
    }
  }
  true
}

///|
pub fn is_ipv4_cidr(value : String) -> Bool {
  let parts = value.split("/").to_array()
  if parts.length() != 2 || !is_ipv4(parts[0].to_owned()) {
    return false
  }
  match parse_small_int(parts[1]) {
    Some(prefix) => prefix <= 32
    None => false
  }
}

///|
pub fn is_uuid(value : String) -> Bool {
  if value.length() != 36 {
    return false
  }
  let chars = value.to_array()
  for index = 0; index < chars.length(); index = index + 1 {
    if index == 8 || index == 13 || index == 18 || index == 23 {
      if chars[index] != '-' {
        return false
      }
    } else {
      let char = chars[index]
      if !char.is_ascii_digit() &&
        !(char >= 'a' && char <= 'f') &&
        !(char >= 'A' && char <= 'F') {
        return false
      }
    }
  }
  true
}

///|
fn is_leap_year(year : Int) -> Bool {
  year % 400 == 0 || (year % 4 == 0 && year % 100 != 0)
}

///|
pub fn is_date(value : String) -> Bool {
  if value.length() != 10 || value[4] != '-' || value[7] != '-' {
    return false
  }
  let year = parse_small_int(value[:4])
  let month = parse_small_int(value[5:7])
  let day = parse_small_int(value[8:10])
  match (year, month, day) {
    (Some(year), Some(month), Some(day)) => {
      if month < 1 || month > 12 || day < 1 {
        return false
      }
      let days = match month {
        2 => if is_leap_year(year) { 29 } else { 28 }
        4 | 6 | 9 | 11 => 30
        _ => 31
      }
      day <= days
    }
    _ => false
  }
}

///|
pub fn is_time(value : String) -> Bool {
  let core = if value.has_suffix("Z") {
    value[:value.length() - 1].to_owned()
  } else {
    value
  }
  if core.length() < 8 || core[2] != ':' || core[5] != ':' {
    return false
  }
  let hour = parse_small_int(core[:2])
  let minute = parse_small_int(core[3:5])
  let second_text = if core.length() == 8 {
    core[6:8].to_owned()
  } else if core.length() > 9 && core[8] == '.' {
    core[6:8].to_owned()
  } else {
    return false
  }
  let second = parse_small_int(second_text)
  match (hour, minute, second) {
    (Some(hour), Some(minute), Some(second)) =>
      hour <= 23 && minute <= 59 && second <= 59
    _ => false
  }
}

///|
pub fn is_datetime(value : String) -> Bool {
  let parts = value.split("T").to_array()
  parts.length() == 2 &&
  is_date(parts[0].to_owned()) &&
  is_time(parts[1].to_owned())
}

///|
pub fn is_uri(value : String) -> Bool {
  if value.is_empty() || value.contains(" ") || value.contains("\n") {
    return false
  }
  let colon = value.find(":")
  match colon {
    Some(index) => {
      if index == 0 {
        return false
      }
      let scheme = value[:index].to_owned()
      let chars = scheme.to_array()
      if chars.is_empty() || !chars[0].is_ascii_alphabetic() {
        return false
      }
      for char in chars {
        if !is_ascii_alphanumeric_char(char) &&
          char != '+' &&
          char != '-' &&
          char != '.' {
          return false
        }
      }
      index + 1 < value.length()
    }
    None => false
  }
}

///|
pub fn is_semver(value : String) -> Bool {
  let core = value.split("+").next().unwrap_or("")
  let version = core.split("-").next().unwrap_or("")
  let parts = version.split(".").to_array()
  if parts.length() != 3 {
    return false
  }
  for part in parts {
    if !all_digits(part.to_owned()) ||
      (part.length() > 1 && part.has_prefix("0")) {
      return false
    }
  }
  true
}

///|
pub fn is_base64(value : String) -> Bool {
  if value.is_empty() || value.length() % 4 != 0 {
    return false
  }
  let chars = value.to_array()
  let mut padding = 0
  for index = 0; index < chars.length(); index = index + 1 {
    let char = chars[index]
    if char == '=' {
      padding += 1
      if index < chars.length() - 2 || padding > 2 {
        return false
      }
    } else if padding > 0 ||
      (!is_ascii_alphanumeric_char(char) && char != '+' && char != '/') {
      return false
    }
  }
  true
}

///|
pub fn is_base64url(value : String) -> Bool {
  if value.is_empty() {
    return false
  }
  for char in value {
    if !is_ascii_alphanumeric_char(char) &&
      char != '-' &&
      char != '_' &&
      char != '=' {
      return false
    }
  }
  true
}

///|
pub fn is_jwt(value : String) -> Bool {
  let parts = value.split(".").to_array()
  parts.length() == 3 &&
  is_base64url(parts[0].to_owned()) &&
  is_base64url(parts[1].to_owned()) &&
  is_base64url(parts[2].to_owned())
}

///|
pub fn is_mac_address(value : String) -> Bool {
  let separator = if value.contains(":") { ":" } else { "-" }
  let parts = value.split(separator).to_array()
  if parts.length() != 6 {
    return false
  }
  for part in parts {
    if part.length() != 2 || !all_hex(part.to_owned()) {
      return false
    }
  }
  true
}

///|
pub fn is_credit_card(value : String) -> Bool {
  let digits = value.replace_all(old=" ", new="").replace_all(old="-", new="")
  if digits.length() < 12 || digits.length() > 19 || !all_digits(digits) {
    return false
  }
  let chars = digits.to_array()
  let mut sum = 0
  let mut alternate = false
  let mut index = chars.length()
  while index > 0 {
    index -= 1
    let mut digit = chars[index].to_int() - '0'.to_int()
    if alternate {
      digit *= 2
      if digit > 9 {
        digit -= 9
      }
    }
    sum += digit
    alternate = !alternate
  }
  sum % 10 == 0
}

///|
/// Names accepted by `validate_format`.
pub fn supported_formats() -> Array[String] {
  [
    "email", "hostname", "ipv4", "ipv4-cidr", "uuid", "date", "time", "date-time",
    "uri", "semver", "identifier", "slug", "base64", "base64url", "jwt", "hex", "mac",
    "credit-card",
  ]
}

///|
/// Validate a built-in API string format. Unknown names are rejected so schema
/// typos cannot silently disable validation.
pub fn validate_format(value : String, format : String) -> Bool {
  match format {
    "email" => is_email(value)
    "hostname" => is_hostname(value)
    "ipv4" => is_ipv4(value)
    "ipv4-cidr" => is_ipv4_cidr(value)
    "uuid" => is_uuid(value)
    "date" => is_date(value)
    "time" => is_time(value)
    "date-time" => is_datetime(value)
    "uri" => is_uri(value)
    "semver" => is_semver(value)
    "identifier" => is_identifier(value)
    "slug" => is_slug(value)
    "base64" => is_base64(value)
    "base64url" => is_base64url(value)
    "jwt" => is_jwt(value)
    "hex" => all_hex(value)
    "mac" => is_mac_address(value)
    "credit-card" => is_credit_card(value)
    _ => false
  }
}
