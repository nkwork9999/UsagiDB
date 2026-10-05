// ============================================
// JSON Parser
// ============================================

///|
pub(all) enum JsonValue {
  JsonNull
  JsonBool(Bool)
  JsonNumber(Double)
  JsonString(String)
  JsonArray(Array[JsonValue])
  JsonObject(Array[(String, JsonValue)])
}

///|
struct JsonParser {
  input : String
  mut pos : Int
}

///|
fn JsonParser::new(input : String) -> JsonParser {
  { input, pos: 0 }
}

///|
fn JsonParser::skip_whitespace(self : JsonParser) -> Unit {
  while self.pos < self.input.length() {
    let c = self.input[self.pos]
    if c == ' ' || c == '\n' || c == '\r' || c == '\t' {
      self.pos = self.pos + 1
    } else {
      break
    }
  }
}

///|
fn JsonParser::peek_char(self : JsonParser) -> Char {
  if self.pos < self.input.length() {
    self.input[self.pos].to_int().unsafe_to_char()
  } else {
    '\u0000'
  }
}

///|
fn JsonParser::consume_char(self : JsonParser) -> Char {
  let c = self.peek_char()
  self.pos = self.pos + 1
  c
}

///|
fn JsonParser::expect_char(self : JsonParser, expected : Char) -> Bool {
  self.skip_whitespace()
  if self.peek_char() == expected {
    self.pos = self.pos + 1
    true
  } else {
    false
  }
}

///|
fn JsonParser::parse_hex_quad(self : JsonParser) -> Int? {
  let mut code = 0
  for i = 0; i < 4; i = i + 1 {
    if self.pos >= self.input.length() {
      return None
    }
    let c = self.consume_char().to_int()
    let digit = if c >= 48 && c <= 57 {
      c - 48
    } else if c >= 65 && c <= 70 {
      c - 55
    } else if c >= 97 && c <= 102 {
      c - 87
    } else {
      return None
    }
    code = code * 16 + digit
  }
  Some(code)
}

///|
fn JsonParser::parse_string(self : JsonParser) -> String? {
  self.skip_whitespace()
  if self.peek_char() != '"' {
    return None
  }
  self.pos = self.pos + 1

  let mut result = ""
  while self.pos < self.input.length() {
    let c = self.consume_char()
    if c == '"' {
      return Some(result)
    } else if c == '\\' {
      let escaped = self.consume_char()
      if escaped == 'n' {
        result = result + "\n"
      } else if escaped == 'r' {
        result = result + "\r"
      } else if escaped == 't' {
        result = result + "\t"
      } else if escaped == '"' {
        result = result + "\""
      } else if escaped == '\\' {
        result = result + "\\"
      } else if escaped == 'u' {
        let mut code = match self.parse_hex_quad() {
          Some(code) => code
          None => return None
        }
        if code >= 0xd800 && code <= 0xdbff {
          if self.consume_char() != '\\' || self.consume_char() != 'u' {
            return None
          }
          let low = match self.parse_hex_quad() {
            Some(low) => low
            None => return None
          }
          if low < 0xdc00 || low > 0xdfff {
            return None
          }
          code = 0x10000 + (code - 0xd800) * 1024 + low - 0xdc00
        } else if code >= 0xdc00 && code <= 0xdfff {
          return None
        }
        result = result + code.unsafe_to_char().to_string()
      } else if escaped == '/' {
        result = result + "/"
      } else if escaped == 'b' {
        result = result + "\b"
      } else if escaped == 'f' {
        result = result + "\u000c"
      } else {
        return None
      }
    } else {
      if c.to_int() < 32 {
        return None
      }
      result = result + c.to_string()
    }
  }
  None
}

///|
fn JsonParser::parse_number(self : JsonParser) -> Double? {
  self.skip_whitespace()
  let start = self.pos

  if self.peek_char() == '-' {
    self.pos = self.pos + 1
  }

  let integer_start = self.pos
  while self.pos < self.input.length() {
    let c = self.peek_char()
    if c >= '0' && c <= '9' {
      self.pos = self.pos + 1
    } else {
      break
    }
  }
  if self.pos == integer_start {
    return None
  }
  if self.pos - integer_start > 1 && self.input[integer_start] == '0' {
    return None
  }

  if self.peek_char() == '.' {
    self.pos = self.pos + 1
    let fraction_start = self.pos
    while self.pos < self.input.length() {
      let c = self.peek_char()
      if c >= '0' && c <= '9' {
        self.pos = self.pos + 1
      } else {
        break
      }
    }
    if self.pos == fraction_start {
      return None
    }
  }

  if self.peek_char() == 'e' || self.peek_char() == 'E' {
    self.pos = self.pos + 1
    if self.peek_char() == '+' || self.peek_char() == '-' {
      self.pos = self.pos + 1
    }
    let exponent_start = self.pos
    while self.pos < self.input.length() {
      let c = self.peek_char()
      if c >= '0' && c <= '9' {
        self.pos = self.pos + 1
      } else {
        break
      }
    }
    if self.pos == exponent_start {
      return None
    }
  }

  if self.pos > start {
    let num_str = substring_manual(self.input, start, self.pos)
    Some(parse_double(num_str))
  } else {
    None
  }
}

///|
fn substring_manual(s : String, start : Int, end : Int) -> String {
  let mut result = ""
  for i = start; i < end && i < s.length(); i = i + 1 {
    result = result + s[i].to_int().unsafe_to_char().to_string()
  }
  result
}

///|
fn parse_double(s : String) -> Double {
  let mut result = 0.0
  let mut decimal_place = 0.0
  let mut is_negative = false
  let mut i = 0

  if i < s.length() && s[i] == '-' {
    is_negative = true
    i = i + 1
  }

  while i < s.length() {
    let c = s[i].to_int().unsafe_to_char()
    if c >= '0' && c <= '9' {
      result = result * 10.0 + (c.to_int() - '0'.to_int()).to_double()
      i = i + 1
    } else if c == '.' {
      i = i + 1
      decimal_place = 0.1
      break
    } else {
      break
    }
  }

  while i < s.length() && decimal_place > 0.0 {
    let c = s[i].to_int().unsafe_to_char()
    if c >= '0' && c <= '9' {
      result = result + (c.to_int() - '0'.to_int()).to_double() * decimal_place
      decimal_place = decimal_place * 0.1
      i = i + 1
    } else {
      break
    }
  }

  if i < s.length() && (s[i] == 'e' || s[i] == 'E') {
    i = i + 1
    let mut exponent_negative = false
    if i < s.length() && (s[i] == '+' || s[i] == '-') {
      exponent_negative = s[i] == '-'
      i = i + 1
    }
    let mut exponent = 0
    while i < s.length() {
      // Bound work and integer arithmetic even for huge exponent strings.
      if exponent < 400 {
        exponent = exponent * 10 + s[i].to_int() - '0'.to_int()
      }
      i = i + 1
    }
    let factor = if exponent_negative { 0.1 } else { 10.0 }
    for j = 0; j < exponent; j = j + 1 {
      result = result * factor
    }
  }
  if is_negative {
    -result
  } else {
    result
  }
}

///|
fn JsonParser::check_keyword(self : JsonParser, keyword : String) -> Bool {
  let len = keyword.length()
  if self.pos + len > self.input.length() {
    return false
  }
  for i = 0; i < len; i = i + 1 {
    if self.input[self.pos + i] != keyword[i] {
      return false
    }
  }
  self.pos = self.pos + len
  true
}

///|
fn JsonParser::parse_value(self : JsonParser) -> JsonValue? {
  self.skip_whitespace()
  let c = self.peek_char()

  if c == '"' {
    match self.parse_string() {
      Some(s) => Some(JsonValue::JsonString(s))
      None => None
    }
  } else if c == '-' || (c >= '0' && c <= '9') {
    match self.parse_number() {
      Some(n) => Some(JsonValue::JsonNumber(n))
      None => None
    }
  } else if c == '{' {
    self.parse_object()
  } else if c == '[' {
    self.parse_array()
  } else if c == 't' {
    if self.check_keyword("true") {
      Some(JsonValue::JsonBool(true))
    } else {
      None
    }
  } else if c == 'f' {
    if self.check_keyword("false") {
      Some(JsonValue::JsonBool(false))
    } else {
      None
    }
  } else if c == 'n' {
    if self.check_keyword("null") {
      Some(JsonValue::JsonNull)
    } else {
      None
    }
  } else {
    None
  }
}

///|
fn JsonParser::parse_array(self : JsonParser) -> JsonValue? {
  if not(self.expect_char('[')) {
    return None
  }

  let arr : Array[JsonValue] = []
  self.skip_whitespace()

  if self.peek_char() == ']' {
    self.pos = self.pos + 1
    return Some(JsonValue::JsonArray(arr))
  }

  while true {
    match self.parse_value() {
      Some(v) => arr.push(v)
      None => return None
    }

    self.skip_whitespace()
    if self.peek_char() == ',' {
      self.pos = self.pos + 1
    } else if self.peek_char() == ']' {
      self.pos = self.pos + 1
      break
    } else {
      return None
    }
  }

  Some(JsonValue::JsonArray(arr))
}

///|
fn JsonParser::parse_object(self : JsonParser) -> JsonValue? {
  if not(self.expect_char('{')) {
    return None
  }

  let obj : Array[(String, JsonValue)] = []
  self.skip_whitespace()

  if self.peek_char() == '}' {
    self.pos = self.pos + 1
    return Some(JsonValue::JsonObject(obj))
  }

  while true {
    let key = match self.parse_string() {
      Some(s) => s
      None => return None
    }

    if not(self.expect_char(':')) {
      return None
    }

    let value = match self.parse_value() {
      Some(v) => v
      None => return None
    }

    obj.push((key, value))

    self.skip_whitespace()
    if self.peek_char() == ',' {
      self.pos = self.pos + 1
    } else if self.peek_char() == '}' {
      self.pos = self.pos + 1
      break
    } else {
      return None
    }
  }

  Some(JsonValue::JsonObject(obj))
}

///|
pub fn parse_json(input : String) -> JsonValue? {
  let parser = JsonParser::new(input)
  let value = parser.parse_value()
  parser.skip_whitespace()
  if parser.pos != input.length() {
    return None
  }
  value
}

// ============================================
// JsonValue Helpers
// ============================================

///|
pub fn JsonValue::get(self : JsonValue, key : String) -> JsonValue? {
  match self {
    JsonObject(pairs) => {
      for pair in pairs {
        if pair.0 == key {
          return Some(pair.1)
        }
      }
      None
    }
    _ => None
  }
}

///|
pub fn JsonValue::as_array(self : JsonValue) -> Array[JsonValue]? {
  match self {
    JsonArray(arr) => Some(arr)
    _ => None
  }
}

///|
pub fn JsonValue::as_number(self : JsonValue) -> Double? {
  match self {
    JsonNumber(n) => Some(n)
    _ => None
  }
}

///|
pub fn JsonValue::as_string(self : JsonValue) -> String? {
  match self {
    JsonString(s) => Some(s)
    _ => None
  }
}

///|
pub fn JsonValue::as_bool(self : JsonValue) -> Bool? {
  match self {
    JsonBool(b) => Some(b)
    _ => None
  }
}

///|
pub fn JsonValue::as_int(self : JsonValue) -> Int? {
  match self {
    JsonNumber(n) => Some(n.to_int())
    _ => None
  }
}

///|
pub fn JsonValue::as_int64(self : JsonValue) -> Int64? {
  match self {
    JsonNumber(n) => Some(n.to_int64())
    _ => None
  }
}
