// JSON → LogStore. Lenient where possible (missing fields → reasonable
// defaults) so a partially-serialized log still loads.

///|
fn jget(json : @core.JsonValue, key : String) -> @core.JsonValue? {
  json.get(key)
}

///|
fn restore_value(json : @core.JsonValue) -> @core.Value? {
  let tag = match jget(json, "t") {
    Some(v) =>
      match v.as_int() {
        Some(n) => n
        None => return None
      }
    None => return None
  }
  match tag {
    0 => Some(@core.Value::Null)
    1 =>
      match jget(json, "v") {
        Some(v) => v.as_int64().map(fn(n) { @core.Value::Int(n) })
        None => None
      }
    2 =>
      match jget(json, "v") {
        Some(v) => v.as_number().map(fn(n) { @core.Value::Float(n) })
        None => None
      }
    3 =>
      match jget(json, "v") {
        Some(v) => v.as_string().map(fn(s) { @core.Value::String(s) })
        None => None
      }
    4 =>
      match jget(json, "v") {
        Some(v) => v.as_int64().map(fn(n) { @core.Value::Timestamp(n) })
        None => None
      }
    _ => None
  }
}

///|
fn restore_headers(
  json : @core.JsonValue,
) -> Array[(String, String)] {
  let result : Array[(String, String)] = []
  match json.as_array() {
    None => return result
    Some(arr) =>
      for pair in arr {
        match pair.as_array() {
          Some(kv) =>
            if kv.length() == 2 {
              match (kv[0].as_string(), kv[1].as_string()) {
                (Some(k), Some(v)) => result.push((k, v))
                _ => ()
              }
            }
          None => ()
        }
      }
  }
  result
}

///|
fn restore_record(json : @core.JsonValue) -> LogRecord? {
  let offset = match jget(json, "o") {
    Some(v) =>
      match v.as_int64() {
        Some(n) => n
        None => return None
      }
    None => return None
  }
  let timestamp = match jget(json, "ts") {
    Some(v) =>
      match v.as_int64() {
        Some(n) => n
        None => 0L
      }
    None => 0L
  }
  let key = match jget(json, "k") {
    Some(v) => v.as_string()
    None => None
  }
  let value = match jget(json, "v") {
    Some(v) =>
      match restore_value(v) {
        Some(rv) => rv
        None => return None
      }
    None => return None
  }
  let headers = match jget(json, "h") {
    Some(v) => restore_headers(v)
    None => []
  }
  Some({ offset, timestamp, key, value, headers })
}

///|
fn restore_retention(json : @core.JsonValue) -> LogRetention {
  let r = LogRetention::none()
  match jget(json, "max_records") {
    Some(v) =>
      match v.as_int() {
        Some(n) => r.max_records = Some(n)
        None => ()
      }
    None => ()
  }
  match jget(json, "max_age_ms") {
    Some(v) =>
      match v.as_int64() {
        Some(n) => r.max_age_ms = Some(n)
        None => ()
      }
    None => ()
  }
  r
}

///|
pub fn LogStore::deserialize(json_str : String) -> LogStore? {
  let json = match @core.parse_json(json_str) {
    Some(j) => j
    None => return None
  }
  let store = LogStore::new()

  // Restore topics
  match jget(json, "topics") {
    Some(arr_json) =>
      match arr_json.as_array() {
        None => ()
        Some(arr) =>
          for tj in arr {
            let name = match jget(tj, "name") {
              Some(v) =>
                match v.as_string() {
                  Some(s) => s
                  None => continue
                }
              None => continue
            }
            let t = store.ensure_topic(name)
            t.next_offset = match jget(tj, "next") {
              Some(v) =>
                match v.as_int64() {
                  Some(n) => n
                  None => 0L
                }
              None => 0L
            }
            match jget(tj, "ret") {
              Some(rj) => {
                let r = restore_retention(rj)
                t.retention.max_records = r.max_records
                t.retention.max_age_ms = r.max_age_ms
              }
              None => ()
            }
            match jget(tj, "records") {
              Some(rj) =>
                match rj.as_array() {
                  Some(rs) =>
                    for r_json in rs {
                      match restore_record(r_json) {
                        Some(r) => t.records.push(r)
                        None => ()
                      }
                    }
                  None => ()
                }
              None => ()
            }
          }
      }
    None => ()
  }

  // Restore consumer-group offsets
  match jget(json, "groups") {
    Some(arr_json) =>
      match arr_json.as_array() {
        None => ()
        Some(arr) =>
          for pair in arr {
            match pair.as_array() {
              Some(kv) =>
                if kv.length() == 2 {
                  match (kv[0].as_string(), kv[1].as_int64()) {
                    (Some(k), Some(off)) => store.group_offsets[k] = off
                    _ => ()
                  }
                }
              None => ()
            }
          }
      }
    None => ()
  }
  Some(store)
}
