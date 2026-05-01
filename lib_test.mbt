///| Umbrella with no modes enabled by default.
test "umbrella_starts_empty" {
  let db = UsagiDB::new()
  inspect(db.ts.is_empty(), content="true")
  inspect(db.stream.is_empty(), content="true")
}

///| `with_threshold` enables TS mode and TS facade methods work.
test "umbrella_with_threshold_uses_ts" {
  let db = UsagiDB::with_threshold(50)
  inspect(db.ts.is_empty(), content="false")
  let _ = db.insert(0L, [@core.Value::Int(7L)])
  let _ = db.insert(1000L, [@core.Value::Int(8L)])
  let rows = db.scan(0L, 10000L)
  inspect(rows.length(), content="2")
}

///| Two modes coexist on the same umbrella.
test "umbrella_ts_and_stream_coexist" {
  let db = UsagiDB::new().enable_ts(threshold=10).enable_stream()
  let _ = db.insert(0L, [@core.Value::Float(20.0)])
  let _ = db.stream_put("temp", 20.5, 100L)
  let _ = db.stream_put("temp", 21.0, 200L)
  inspect(db.scan(0L, 1000L).length(), content="1")
  inspect(db.stream_query("temp").length(), content="2")
}

///| Log mode coexists with ts and stream.
test "umbrella_log_mode" {
  let db = UsagiDB::new().enable_log()
  let _ = db.log_produce("temp", @core.Value::Float(20.5))
  let _ = db.log_produce("temp", @core.Value::Float(21.0))
  db.log_subscribe("temp", "g")
  let records = db.log_poll("temp", "g", 10)
  inspect(records.length(), content="2")
}

///| log_to_stream bridges Float values from a topic into the stream view.
test "umbrella_log_to_stream_bridge" {
  let db = UsagiDB::new().enable_stream().enable_log()
  // Configure stream to keep last 100 raw points.
  db.stream.unwrap().set_rule("price", @stream.KeepLastN(100))
  let _ = db.log_produce(
    "ticks", @core.Value::Float(100.0), timestamp=0L,
  )
  let _ = db.log_produce(
    "ticks", @core.Value::Float(101.0), timestamp=100L,
  )
  let piped = db.log_to_stream("ticks", "stream-view", "price")
  inspect(piped, content="2")
  inspect(db.stream_query("price").length(), content="2")
}
