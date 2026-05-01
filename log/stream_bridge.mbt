// Bridge between log-mode (durable, multi-topic, offset-tracked) and
// stream-mode (in-memory, key-strategy compaction).
//
// Pattern: produce to log → drain into stream as a real-time projection.
// The log is the source of truth; the stream is a compact view (e.g. OHLC
// candles, KeepLastN window) that the UI can render.

///| Drain up to `max` records from `topic`/`group` and forward them to
/// `stream` as a `put(stream_key, value, time)` call. Only records whose
/// `value` is `Float` or `Int` translate to a stream sample; other variants
/// are silently skipped (the log retains them either way).
///
/// Returns the count of records that reached the stream.
pub fn LogStore::pipe_to_stream(
  self : LogStore,
  topic : String,
  group : String,
  stream : @stream.EventStore,
  stream_key : String,
  max~ : Int = 1024,
) -> Int {
  let records = self.poll(topic, group, max)
  let mut piped = 0
  for r in records {
    let v_opt : Double? = match r.value {
      @core.Value::Float(v) => Some(v)
      @core.Value::Int(v) => Some(v.to_double())
      _ => None
    }
    match v_opt {
      Some(v) => {
        let _ = stream.put(stream_key, v, r.timestamp)
        piped = piped + 1
      }
      None => ()
    }
  }
  piped
}
