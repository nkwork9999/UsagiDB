///| Smoke test: per-key strategy + put/query round-trip.
test "stream_keep_last_n" {
  let config = CompactionConfig::new().rule("v", KeepLastN(3))
  let store = EventStore::new(config)
  let _ = store.put("v", 1.0, 1L)
  let _ = store.put("v", 2.0, 2L)
  let _ = store.put("v", 3.0, 3L)
  let _ = store.put("v", 4.0, 4L)
  inspect(
    store.query("v"),
    content="[Point(2, 2), Point(3, 3), Point(4, 4)]",
  )
}

///| Downsample collapses many samples into one OHLC bucket.
test "stream_downsample_ohlc" {
  let config = CompactionConfig::new().rule("p", Downsample(60000L, OHLC))
  let store = EventStore::new(config)
  let _ = store.put("p", 100.0, 1000L)
  let _ = store.put("p", 110.0, 30000L)
  let _ = store.put("p", 95.0, 50000L)
  let rows = store.query("p")
  inspect(rows.length(), content="1")
}

///| DeadBand drops samples within the threshold.
test "stream_deadband" {
  let config = CompactionConfig::new().rule("t", DeadBand(0.5))
  let store = EventStore::new(config)
  inspect(store.put("t", 20.00, 0L), content="Kept")
  inspect(store.put("t", 20.10, 100L), content="Dropped")
  inspect(store.put("t", 20.80, 200L), content="Kept")
}

///| OnRead defers compaction: pending grows on put, drains on query.
test "trigger_on_read_defers" {
  let config = CompactionConfig::new()
    .rule("v", KeepLastN(3))
    .trigger("v", OnRead)
  let store = EventStore::new(config)
  let _ = store.put("v", 1.0, 1L)
  let _ = store.put("v", 2.0, 2L)
  let _ = store.put("v", 3.0, 3L)
  let _ = store.put("v", 4.0, 4L)
  // Before query, no compaction has happened — samples is still empty.
  inspect(store.size("v"), content="0")
  // Query triggers flush; KeepLastN(3) trims to last 3.
  let rows = store.query("v")
  inspect(rows.length(), content="3")
}

///| EveryN(N) batches: flushes only when pending reaches N.
test "trigger_every_n_batches" {
  let config = CompactionConfig::new()
    .rule("v", KeepAll)
    .trigger("v", EveryN(3))
  let store = EventStore::new(config)
  let _ = store.put("v", 1.0, 1L)
  let _ = store.put("v", 2.0, 2L)
  // Only 2 in pending → still no flush.
  inspect(store.size("v"), content="0")
  let _ = store.put("v", 3.0, 3L)
  // Threshold reached → flushed.
  inspect(store.size("v"), content="3")
}

///| Manual trigger never flushes on its own; explicit compact() is required.
test "trigger_manual_requires_compact_call" {
  let config = CompactionConfig::new()
    .rule("v", KeepAll)
    .trigger("v", Manual)
  let store = EventStore::new(config)
  let _ = store.put("v", 1.0, 1L)
  let _ = store.put("v", 2.0, 2L)
  inspect(store.size("v"), content="0")
  store.compact("v")
  inspect(store.size("v"), content="2")
}
