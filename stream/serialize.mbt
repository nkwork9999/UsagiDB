// In-memory state JSON. The compaction config (rules / triggers / validators)
// is **not** serialized — callers reconstruct it programmatically and then
// call `restore_from(json)` to replay the per-series sample/bucket state.

///|
fn s_escape(s : String) -> String {
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
fn s_sample_pair(p : (Int64, Double)) -> String {
  let (t, v) = p
  "[" + t.to_string() + "," + v.to_string() + "]"
}

///|
fn s_bucket(b : OHLCBucket) -> String {
  "{\"s\":" +
  b.start.to_string() +
  ",\"o\":" +
  b.open.to_string() +
  ",\"h\":" +
  b.high.to_string() +
  ",\"l\":" +
  b.low.to_string() +
  ",\"c\":" +
  b.close.to_string() +
  ",\"n\":" +
  b.count.to_string() +
  ",\"sum\":" +
  b.sum.to_string() +
  "}"
}

///|
fn s_opt_double(x : Double?) -> String {
  match x {
    None => "null"
    Some(v) => v.to_string()
  }
}

///|
fn s_opt_int64(x : Int64?) -> String {
  match x {
    None => "null"
    Some(v) => v.to_string()
  }
}

///|
fn s_join_samples(samples : Array[(Int64, Double)]) -> String {
  let buf = StringBuilder::new()
  buf.write_char('[')
  let mut first = true
  for p in samples {
    if not(first) {
      buf.write_char(',')
    }
    first = false
    buf.write_string(s_sample_pair(p))
  }
  buf.write_char(']')
  buf.to_string()
}

///|
fn s_join_buckets(buckets : Array[OHLCBucket]) -> String {
  let buf = StringBuilder::new()
  buf.write_char('[')
  let mut first = true
  for b in buckets {
    if not(first) {
      buf.write_char(',')
    }
    first = false
    buf.write_string(s_bucket(b))
  }
  buf.write_char(']')
  buf.to_string()
}

///| Serialize all series state to a JSON string. Config is omitted by design.
pub fn EventStore::serialize(self : EventStore) -> String {
  let buf = StringBuilder::new()
  buf.write_string("{\"series\":[")
  let mut first = true
  for entry in self.series {
    let (k, st) = entry
    if not(first) {
      buf.write_char(',')
    }
    first = false
    buf.write_string("{\"key\":")
    buf.write_string(s_escape(k))
    buf.write_string(",\"samples\":")
    buf.write_string(s_join_samples(st.samples))
    buf.write_string(",\"buckets\":")
    buf.write_string(s_join_buckets(st.buckets))
    buf.write_string(",\"pending\":")
    buf.write_string(s_join_samples(st.pending))
    buf.write_string(",\"last_v\":")
    buf.write_string(s_opt_double(st.last_kept_value))
    buf.write_string(",\"last_t\":")
    buf.write_string(s_opt_int64(st.last_kept_time))
    buf.write_string(",\"recv\":")
    buf.write_string(st.total_received.to_string())
    buf.write_string(",\"kept\":")
    buf.write_string(st.total_kept.to_string())
    buf.write_char('}')
  }
  buf.write_string("]}")
  buf.to_string()
}
