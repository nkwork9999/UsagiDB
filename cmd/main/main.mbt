// UsagiDB demo entry + browser JS bindings.
// Library lives at the top of the module; this file is the thin entrypoint.

///|
extern "js" fn js_log(msg : String) -> Unit =
  #|(msg) => console.log(msg)

///|
fn main {
  let db = @lib.UsagiDB::with_threshold(5)
  println("🐰 UsagiDB Demo (with Serialization)")
  println("=====================================")
  for i = 0; i < 12; i = i + 1 {
    let ts = (i * 1000).to_int64()
    let temp = 20.0 + i.to_double() * 0.5
    let sensor = if i % 2 == 0 { "sensor-1" } else { "sensor-2" }
    let _ = db.insert(ts, [
      @core.Value::Float(temp),
      @core.Value::String(sensor),
    ])

  }
  println(db.stats())
  println("\n--- Serialization Demo ---")
  let json = db.serialize()
  println("Serialized JSON length: " + json.length().to_string() + " bytes")
  println("\n--- Deserialization Demo ---")
  match @lib.UsagiDB::deserialize(json) {
    Some(db2) => {
      println("Deserialized successfully!")
      println(db2.stats())
      let original_rows = db.scan(0L, 100000L)
      let restored_rows = db2.scan(0L, 100000L)
      println("Original rows: " + original_rows.length().to_string())
      println("Restored rows: " + restored_rows.length().to_string())
    }
    None => println("Deserialization failed!")
  }
}

///|
fn init {
  js_log("🐰 UsagiDB loaded")
}

// =============================================================================
// Browser JS exports — listed in moon.pkg.json `link.js.exports` and imported
// from index.html via ESM. Names match the public README so callers don't
// have to care about MoonBit internals.
// =============================================================================

///| Construct a TS-mode UsagiDB with the given compaction threshold.
pub fn create(threshold : Int) -> @lib.UsagiDB {
  @lib.UsagiDB::with_threshold(threshold)
}

///| Convert a JS Number to an Int64 handle (`{hi, lo}` shape on the JS side).
pub fn to_int64(n : Int) -> Int64 {
  n.to_int64()
}

///| Build a `Value::Float` cell.
pub fn value_float(v : Double) -> @core.Value {
  @core.Value::Float(v)
}

///| Build a `Value::String` cell.
pub fn value_string(s : String) -> @core.Value {
  @core.Value::String(s)
}

///| Build a `Value::Int` cell.
pub fn value_int(v : Int64) -> @core.Value {
  @core.Value::Int(v)
}

///|
pub fn insert(
  db : @lib.UsagiDB,
  ts : Int64,
  values : Array[@core.Value],
) -> Int {
  db.insert(ts, values)
}

///|
pub fn scan(
  db : @lib.UsagiDB,
  start : Int64,
  end : Int64,
) -> Array[@core.Row] {
  db.scan(start, end)
}

///|
pub fn stats(db : @lib.UsagiDB) -> String {
  db.stats()
}

///|
pub fn serialize(db : @lib.UsagiDB) -> String {
  db.serialize()
}

///| Returns `null` (JS) on parse failure since MoonBit `Option<T>` becomes a
/// nullable on the JS side.
pub fn deserialize(json : String) -> @lib.UsagiDB? {
  @lib.UsagiDB::deserialize(json)
}

// =============================================================================
// Stream-mode preset wrappers — JS callers can't easily build MoonBit enum
// variants, so we expose one function per strategy.
// =============================================================================

fn ensure_stream(db : @lib.UsagiDB) -> @stream.EventStore {
  match db.stream {
    Some(s) => s
    None => {
      let _ = db.enable_stream()
      db.stream.unwrap()
    }
  }
}

///| Configure key with `KeepLastN(n)`.
pub fn stream_keep_last_n(
  db : @lib.UsagiDB,
  key : String,
  n : Int,
) -> Unit {
  ensure_stream(db).set_rule(key, @stream.KeepLastN(n))
}

///| Configure key with `Downsample(bucket_ms, OHLC)`.
pub fn stream_downsample_ohlc(
  db : @lib.UsagiDB,
  key : String,
  bucket_ms : Int64,
) -> Unit {
  ensure_stream(db).set_rule(key, @stream.Downsample(bucket_ms, @stream.OHLC))
}

///| Configure key with `DeadBand(threshold)`.
pub fn stream_dead_band(
  db : @lib.UsagiDB,
  key : String,
  threshold : Double,
) -> Unit {
  ensure_stream(db).set_rule(key, @stream.DeadBand(threshold))
}

///| Push a sample into stream mode.
pub fn stream_put(
  db : @lib.UsagiDB,
  key : String,
  value : Double,
  time : Int64,
) -> @stream.PutResult {
  db.stream_put(key, value, time)
}

///| Query stream rows (returns `Array[Row]` — JS sees `[{$tag, ...}]`).
pub fn stream_query(
  db : @lib.UsagiDB,
  key : String,
) -> Array[@stream.Row] {
  db.stream_query(key)
}

// =============================================================================
// Log-mode JS exports.
// =============================================================================

///| Enable log mode (idempotent). Returns the same db.
pub fn log_enable(db : @lib.UsagiDB) -> @lib.UsagiDB {
  match db.log {
    Some(_) => db
    None => db.enable_log()
  }
}

///| Produce a string-valued record. (JS doesn't easily build other Value
/// variants, so this is the common case for browser demos.)
pub fn log_produce_string(
  db : @lib.UsagiDB,
  topic : String,
  key : String,
  value : String,
  timestamp : Int64,
) -> Int64 {
  let _ = log_enable(db)
  db.log_produce(
    topic, @core.Value::String(value), key=Some(key), timestamp~,
  )
}

///| Subscribe a consumer group to a topic.
pub fn log_subscribe(
  db : @lib.UsagiDB,
  topic : String,
  group : String,
) -> Unit {
  let _ = log_enable(db)
  db.log_subscribe(topic, group)
}

///| Poll up to `max` records from `topic`/`group`. Returns array of LogRecord
/// (`{offset, timestamp, key, value, headers}` shape on the JS side).
pub fn log_poll(
  db : @lib.UsagiDB,
  topic : String,
  group : String,
  max : Int,
) -> Array[@log.LogRecord] {
  db.log_poll(topic, group, max)
}

///| List all known topics in the log store.
pub fn log_list_topics(db : @lib.UsagiDB) -> Array[String] {
  match db.log {
    Some(l) => l.list_topics()
    None => []
  }
}

///| Whole log mode → JSON string. Use this from JS to push to OPFS / network.
pub fn log_serialize(db : @lib.UsagiDB) -> String {
  db.log_serialize()
}

///| Replace log mode with the contents of `json_str`. Returns true on success.
pub fn log_deserialize(db : @lib.UsagiDB, json_str : String) -> Bool {
  db.log_deserialize(json_str)
}

///| Serialize stream-mode series state to JSON (config not included).
pub fn stream_serialize(db : @lib.UsagiDB) -> String {
  db.stream_serialize()
}

///| Replay serialized stream state into the existing EventStore. The caller
/// must have already configured rules/triggers as desired.
pub fn stream_restore(db : @lib.UsagiDB, json_str : String) -> Bool {
  db.stream_restore_from(json_str)
}

///| Build a JSON SyncPacket of ts-mode changes since `since_seq`.
pub fn sync_pull(db : @lib.UsagiDB, since_seq : Int64) -> String {
  db.sync_pull_json(since_seq)
}

///| Apply a JSON SyncPacket from a remote. Returns SyncResult enum to JS.
pub fn sync_apply(db : @lib.UsagiDB, json_str : String) -> @core.SyncResult {
  db.sync_apply_json(json_str)
}

///| Current ts-mode local sequence (high water mark). JS callers use this as
/// the `since_seq` for the next pull.
pub fn sync_local_seq(db : @lib.UsagiDB) -> Int64 {
  match db.ts {
    Some(t) => t.sync_state().local_seq
    None => 0L
  }
}

///| Pull only changes within `[ts_min, ts_max]` (shape subscription).
pub fn sync_pull_range(
  db : @lib.UsagiDB,
  since_seq : Int64,
  ts_min : Int64,
  ts_max : Int64,
) -> String {
  db.sync_pull_shape_json(since_seq, @core.Shape::time_range(ts_min, ts_max))
}
