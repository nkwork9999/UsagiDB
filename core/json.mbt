// ============================================
// JSON Parser
// ============================================

pub(all) enum JsonValue {
  JsonNull
  JsonBool(Bool)
  JsonNumber(Double)
  JsonString(String)
  JsonArray(Array[JsonValue])
  JsonObject(Array[(String, JsonValue)])
}

struct JsonParser {
  input : String
  mut pos : Int
}

fn JsonParser::new(input : String) -> JsonParser {
  { input: input, pos: 0 }
}

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

fn JsonParser::peek_char(self : JsonParser) -> Char {
  if self.pos < self.input.length() {
    self.input[self.pos].to_int().unsafe_to_char()
  } else {
    '\u0000'
  }
}

fn JsonParser::consume_char(self : JsonParser) -> Char {
  let c = self.peek_char()
  self.pos = self.pos + 1
  c
}

fn JsonParser::expect_char(self : JsonParser, expected : Char) -> Bool {
  self.skip_whitespace()
  if self.peek_char() == expected {
    self.pos = self.pos + 1
    true
  } else {
    false
  }
}

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
      } else {
        result = result + escaped.to_string()
      }
    } else {
      result = result + c.to_string()
    }
  }
  None
}

fn JsonParser::parse_number(self : JsonParser) -> Double? {
  self.skip_whitespace()
  let start = self.pos
  
  if self.peek_char() == '-' {
    self.pos = self.pos + 1
  }
  
  while self.pos < self.input.length() {
    let c = self.peek_char()
    if c >= '0' && c <= '9' {
      self.pos = self.pos + 1
    } else {
      break
    }
  }
  
  if self.peek_char() == '.' {
    self.pos = self.pos + 1
    while self.pos < self.input.length() {
      let c = self.peek_char()
      if c >= '0' && c <= '9' {
        self.pos = self.pos + 1
      } else {
        break
      }
    }
  }
  
  if self.peek_char() == 'e' || self.peek_char() == 'E' {
    self.pos = self.pos + 1
    if self.peek_char() == '+' || self.peek_char() == '-' {
      self.pos = self.pos + 1
    }
    while self.pos < self.input.length() {
      let c = self.peek_char()
      if c >= '0' && c <= '9' {
        self.pos = self.pos + 1
      } else {
        break
      }
    }
  }
  
  if self.pos > start {
    let num_str = substring_manual(self.input, start, self.pos)
    Some(parse_double(num_str))
  } else {
    None
  }
}

fn substring_manual(s : String, start : Int, end : Int) -> String {
  let mut result = ""
  for i = start; i < end && i < s.length(); i = i + 1 {
    result = result + s[i].to_int().unsafe_to_char().to_string()
  }
  result
}

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
  
  if is_negative { -result } else { result }
}

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

pub fn parse_json(input : String) -> JsonValue? {
  let parser = JsonParser::new(input)
  parser.parse_value()
}

// ============================================
// JsonValue Helpers
// ============================================

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

pub fn JsonValue::as_array(self : JsonValue) -> Array[JsonValue]? {
  match self {
    JsonArray(arr) => Some(arr)
    _ => None
  }
}

pub fn JsonValue::as_number(self : JsonValue) -> Double? {
  match self {
    JsonNumber(n) => Some(n)
    _ => None
  }
}

pub fn JsonValue::as_string(self : JsonValue) -> String? {
  match self {
    JsonString(s) => Some(s)
    _ => None
  }
}

pub fn JsonValue::as_bool(self : JsonValue) -> Bool? {
  match self {
    JsonBool(b) => Some(b)
    _ => None
  }
}

pub fn JsonValue::as_int(self : JsonValue) -> Int? {
  match self {
    JsonNumber(n) => Some(n.to_int())
    _ => None
  }
}

pub fn JsonValue::as_int64(self : JsonValue) -> Int64? {
  match self {
    JsonNumber(n) => Some(n.to_int64())
    _ => None
  }
}

