// JSON serialization for log mode. Inline helpers — duplicates a few small
// ones from ts/serialize.mbt; that's intentional to keep log/ independent of
// ts/. A future cleanup could promote shared helpers to `core`.

///|
fn escape_json(s : String) -> String {
  let buf = StringBuilder::new()
  buf.write_char('"')
  for ch in s {
    match ch {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      _ => buf.write_char(ch)
    }
  }
  buf.write_char('"')
  buf.to_string()
}

///|
fn value_json(v : @core.Value) -> String {
  match v {
    @core.Value::Null => "{\"t\":0}"
    @core.Value::Int(n) => "{\"t\":1,\"v\":" + n.to_string() + "}"
    @core.Value::Float(n) => "{\"t\":2,\"v\":" + n.to_string() + "}"
    @core.Value::String(s) => "{\"t\":3,\"v\":" + escape_json(s) + "}"
    @core.Value::Timestamp(n) => "{\"t\":4,\"v\":" + n.to_string() + "}"
  }
}

///|
fn headers_json(hs : Array[(String, String)]) -> String {
  let buf = StringBuilder::new()
  buf.write_char('[')
  let mut first = true
  for h in hs {
    let (k, v) = h
    if not(first) {
      buf.write_char(',')
    }
    first = false
    buf.write_char('[')
    buf.write_string(escape_json(k))
    buf.write_char(',')
    buf.write_string(escape_json(v))
    buf.write_char(']')
  }
  buf.write_char(']')
  buf.to_string()
}

///|
fn key_json(k : String?) -> String {
  match k {
    None => "null"
    Some(s) => escape_json(s)
  }
}

///|
fn opt_int_json(x : Int?) -> String {
  match x {
    None => "null"
    Some(n) => n.to_string()
  }
}

///|
fn opt_int64_json(x : Int64?) -> String {
  match x {
    None => "null"
    Some(n) => n.to_string()
  }
}

///|
fn record_json(r : LogRecord) -> String {
  "{\"o\":" +
  r.offset.to_string() +
  ",\"ts\":" +
  r.timestamp.to_string() +
  ",\"k\":" +
  key_json(r.key) +
  ",\"v\":" +
  value_json(r.value) +
  ",\"h\":" +
  headers_json(r.headers) +
  "}"
}

///|
fn topic_json(t : Topic) -> String {
  let buf = StringBuilder::new()
  buf.write_string("{\"name\":")
  buf.write_string(escape_json(t.name))
  buf.write_string(",\"next\":")
  buf.write_string(t.next_offset.to_string())
  buf.write_string(",\"ret\":{\"max_records\":")
  buf.write_string(opt_int_json(t.retention.max_records))
  buf.write_string(",\"max_age_ms\":")
  buf.write_string(opt_int64_json(t.retention.max_age_ms))
  buf.write_string("},\"records\":[")
  let mut first = true
  for r in t.records {
    if not(first) {
      buf.write_char(',')
    }
    first = false
    buf.write_string(record_json(r))
  }
  buf.write_string("]}")
  buf.to_string()
}

///| Serialize the entire LogStore to JSON. The output is `parse_json`-able
/// and round-trips through `LogStore::deserialize`.
pub fn LogStore::serialize(self : LogStore) -> String {
  let buf = StringBuilder::new()
  buf.write_string("{\"topics\":[")
  let mut first = true
  for entry in self.topics {
    let (_, t) = entry
    if not(first) {
      buf.write_char(',')
    }
    first = false
    buf.write_string(topic_json(t))
  }
  buf.write_string("],\"groups\":[")
  let mut first2 = true
  for entry in self.group_offsets {
    let (k, off) = entry
    if not(first2) {
      buf.write_char(',')
    }
    first2 = false
    buf.write_char('[')
    buf.write_string(escape_json(k))
    buf.write_char(',')
    buf.write_string(off.to_string())
    buf.write_char(']')
  }
  buf.write_string("]}")
  buf.to_string()
}
