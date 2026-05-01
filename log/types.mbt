// Public types for the log mode. Records are looser than `core.Operation`:
// any `Value` can ride, plus a string key and free-form headers — closer to a
// Kafka record than to a TS-DB change entry.

///| A single record in a topic. `offset` is monotonic per topic; `timestamp`
/// is producer-supplied (may be the wall clock or a logical time).
pub(all) struct LogRecord {
  offset : Int64
  timestamp : Int64
  key : String?
  value : @core.Value
  headers : Array[(String, String)]
} derive(Show)

///| Per-topic retention policy. Either bound may be `None` to mean "unbounded".
/// `max_records` is enforced eagerly on `produce`; `max_age_ms` requires an
/// explicit `apply_retention(topic, now)` since the store has no clock.
pub(all) struct LogRetention {
  mut max_records : Int?
  mut max_age_ms : Int64?
} derive(Show)

///|
pub fn LogRetention::none() -> LogRetention {
  { max_records: None, max_age_ms: None }
}
