// Restore series state from JSON produced by `serialize()`. Config is
// untouched — the caller is expected to have rebuilt rules/triggers before
// calling this.

///|
fn d_pair_to_sample(j : @core.JsonValue) -> (Int64, Double)? {
  match j.as_array() {
    Some(arr) =>
      if arr.length() == 2 {
        match (arr[0].as_int64(), arr[1].as_number()) {
          (Some(t), Some(v)) => Some((t, v))
          _ => None
        }
      } else {
        None
      }
    None => None
  }
}

///|
fn d_samples(j : @core.JsonValue) -> Array[(Int64, Double)] {
  let result : Array[(Int64, Double)] = []
  match j.as_array() {
    Some(arr) =>
      for elem in arr {
        match d_pair_to_sample(elem) {
          Some(p) => result.push(p)
          None => ()
        }
      }
    None => ()
  }
  result
}

///|
fn d_bucket(j : @core.JsonValue) -> OHLCBucket? {
  let start = match j.get("s") {
    Some(v) =>
      match v.as_int64() {
        Some(n) => n
        None => return None
      }
    None => return None
  }
  let open = match j.get("o") {
    Some(v) => v.as_number().or(0.0)
    None => 0.0
  }
  let high = match j.get("h") {
    Some(v) => v.as_number().or(0.0)
    None => 0.0
  }
  let low = match j.get("l") {
    Some(v) => v.as_number().or(0.0)
    None => 0.0
  }
  let close = match j.get("c") {
    Some(v) => v.as_number().or(0.0)
    None => 0.0
  }
  let count = match j.get("n") {
    Some(v) => v.as_int().or(0)
    None => 0
  }
  let sum = match j.get("sum") {
    Some(v) => v.as_number().or(0.0)
    None => 0.0
  }
  Some({ start, open, high, low, close, count, sum })
}

///|
fn d_buckets(j : @core.JsonValue) -> Array[OHLCBucket] {
  let result : Array[OHLCBucket] = []
  match j.as_array() {
    Some(arr) =>
      for elem in arr {
        match d_bucket(elem) {
          Some(b) => result.push(b)
          None => ()
        }
      }
    None => ()
  }
  result
}

///| Restore data into an existing `EventStore`. Returns false on parse fail.
/// Series not present in the JSON keep their existing state; series in the
/// JSON overwrite local state for that key.
pub fn EventStore::restore_from(self : EventStore, json_str : String) -> Bool {
  let json = match @core.parse_json(json_str) {
    Some(j) => j
    None => return false
  }
  match json.get("series") {
    None => return true
    Some(arr_json) =>
      match arr_json.as_array() {
        None => return false
        Some(arr) =>
          for elem in arr {
            let key = match elem.get("key") {
              Some(v) =>
                match v.as_string() {
                  Some(s) => s
                  None => continue
                }
              None => continue
            }
            let st = self.ensure_series(key)
            st.samples = match elem.get("samples") {
              Some(v) => d_samples(v)
              None => []
            }
            st.buckets.clear()
            match elem.get("buckets") {
              Some(v) =>
                for b in d_buckets(v) {
                  st.buckets.push(b)
                }
              None => ()
            }
            st.pending.clear()
            match elem.get("pending") {
              Some(v) =>
                for p in d_samples(v) {
                  st.pending.push(p)
                }
              None => ()
            }
            st.last_kept_value = match elem.get("last_v") {
              Some(v) => v.as_number()
              None => None
            }
            st.last_kept_time = match elem.get("last_t") {
              Some(v) => v.as_int64()
              None => None
            }
            st.total_received = match elem.get("recv") {
              Some(v) => v.as_int().or(0)
              None => 0
            }
            st.total_kept = match elem.get("kept") {
              Some(v) => v.as_int().or(0)
              None => 0
            }
          }
      }
  }
  true
}
