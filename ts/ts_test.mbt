///| Insert + scan round-trip on a single sensor stream.
test "insert_scan_basic" {
  let db = TimeSeriesStore::with_threshold(50)
  for i = 0; i < 5; i = i + 1 {
    let ts = (i * 1000).to_int64()
    let temp = 20.0 + i.to_double()
    let _ = db.insert(ts, [@core.Value::Float(temp)])

  }
  let rows = db.scan(0L, 10000L)
  inspect(rows.length(), content="5")
}

///| Compaction triggers once delta-store exceeds the threshold; scan must still
/// return everything (delta + main combined).
test "compaction_then_scan" {
  let db = TimeSeriesStore::with_threshold(3)
  for i = 0; i < 7; i = i + 1 {
    let ts = (i * 1000).to_int64()
    let _ = db.insert(ts, [@core.Value::Int(i.to_int64())])

  }
  let _ = db.compact()
  let rows = db.scan(0L, 10000L)
  inspect(rows.length(), content="7")
}

///| Logical delete excludes a timestamp from subsequent scans.
test "delete_hides_row" {
  let db = TimeSeriesStore::with_threshold(50)
  let _ = db.insert(0L, [@core.Value::Int(100L)])
  let _ = db.insert(1000L, [@core.Value::Int(200L)])
  inspect(db.scan(0L, 10000L).length(), content="2")
  let _ = db.delete(0L)
  inspect(db.scan(0L, 10000L).length(), content="1")
}

///| Filter::Eq narrows a scan to matching rows.
test "scan_where_filter" {
  let db = TimeSeriesStore::with_threshold(50)
  let _ = db.insert(0L, [@core.Value::String("a")])
  let _ = db.insert(1000L, [@core.Value::String("b")])
  let _ = db.insert(2000L, [@core.Value::String("a")])
  let rows = db.scan_where(0L, 10000L, @core.Filter::Eq(0, @core.Value::String("a")))
  inspect(rows.length(), content="2")
}

///| Serialize then deserialize must reproduce the same row count.
test "serialize_deserialize_roundtrip" {
  let db = TimeSeriesStore::with_threshold(50)
  for i = 0; i < 4; i = i + 1 {
    let _ = db.insert((i * 1000).to_int64(), [@core.Value::Int(i.to_int64())])

  }
  let json = db.serialize()
  let restored = TimeSeriesStore::deserialize(json).unwrap()
  inspect(
    restored.scan(0L, 10000L).length(),
    content=db.scan(0L, 10000L).length().to_string(),
  )
}

///| Retention drops rows whose timestamp is older than `now - duration`.
test "retention_drops_old_rows" {
  let db = TimeSeriesStore::with_threshold(50)
  let _ = db.insert(0L, [@core.Value::Int(1L)])
  let _ = db.insert(60000L, [@core.Value::Int(2L)])
  let _ = db.insert(120000L, [@core.Value::Int(3L)])
  inspect(db.scan(0L, 1000000L).length(), content="3")
  // 1-minute retention. At now=180000ms, cutoff is 120000 — only the latest
  // sample survives.
  db.set_retention(@core.TimeUnit::Minute, 1)
  let dropped = db.apply_retention(180000L)
  inspect(dropped, content="2")
  inspect(db.scan(0L, 1000000L).length(), content="1")
}

///| Continuous aggregate registration + refresh + query.
test "continuous_aggregate" {
  let db = TimeSeriesStore::with_threshold(50)
  for i = 0; i < 6; i = i + 1 {
    let ts = (i * 1000).to_int64()
    let v = (10 + i).to_int64()
    let _ = db.insert(ts, [@core.Value::Int(v)])

  }
  db.register_aggregate("sum_1s", @core.TimeUnit::Second, 0, AggType::Sum)
  let ok = db.refresh_aggregate("sum_1s", 0L, 6000L)
  inspect(ok, content="true")
  let data = db.query_aggregate("sum_1s")
  inspect(data.length(), content="6")
  inspect(db.list_aggregates(), content="[\"sum_1s\"]")
}

///| With CRDT disabled, insert leaves crdt_rows empty.
test "crdt_disabled_by_default" {
  let db = TimeSeriesStore::with_config(50, "siteA")
  let _ = db.insert(0L, [@core.Value::Int(1L)])
  inspect(db.crdt_rows.length(), content="0")
  inspect(db.crdt_enabled, content="false")
}

///| With CRDT enabled, every insert pushes a CRDTRow and bumps both clocks.
test "crdt_enabled_records_rows" {
  let db = TimeSeriesStore::with_config(50, "siteA")
  db.enable_crdt()
  let _ = db.insert(0L, [@core.Value::Int(1L)])
  let _ = db.insert(1000L, [@core.Value::Int(2L)])
  inspect(db.crdt_rows.length(), content="2")
  // Lamport clock has ticked at least twice. Check it's >= 2.
  let bumped = db.clock.tick() >= 3L
  inspect(bumped, content="true")
}

///| Gap-filling produces one row per `interval_ms` slot, filling missing ones.
test "scan_with_fill_previous" {
  let db = TimeSeriesStore::with_threshold(50)
  let _ = db.insert(0L, [@core.Value::Int(10L)])
  let _ = db.insert(2000L, [@core.Value::Int(20L)])
  // Slots: 0, 1000, 2000 → 3 rows. The 1000 slot is missing → filled with previous.
  let rows = db.scan_with_fill(0L, 2000L, 1000L, FillMethod::Previous)
  inspect(rows.length(), content="3")
  match rows[1].values[0] {
    @core.Value::Int(v) => inspect(v, content="10")
    _ => abort("expected int")
  }
}

///| Round-trip: serialize includes v0.2 fields and deserialize restores them.
test "serialize_includes_v02_fields" {
  let db = TimeSeriesStore::with_config(50, "siteB")
  db.enable_crdt()
  db.set_retention(@core.TimeUnit::Hour, 3)
  let _ = db.insert(0L, [@core.Value::Int(7L)])
  let json = db.serialize()
  let has_site = json.contains("\"site_id\":\"siteB\"")
  let has_crdt = json.contains("\"crdt_enabled\":true")
  let has_retention = json.contains("\"retention_enabled\":true")
  inspect(has_site, content="true")
  inspect(has_crdt, content="true")
  inspect(has_retention, content="true")
  let restored = TimeSeriesStore::deserialize(json).unwrap()
  inspect(restored.site_id, content="siteB")
  inspect(restored.crdt_enabled, content="true")
  inspect(restored.retention.enabled, content="true")
}

///| merge_crdt: matching ts merges (LWW), new ts appends.
test "merge_crdt_basic" {
  let a = TimeSeriesStore::with_config(50, "siteA")
  a.enable_crdt()
  let _ = a.insert(0L, [@core.Value::Int(1L)])
  let _ = a.insert(1000L, [@core.Value::Int(2L)])
  inspect(a.crdt_rows.length(), content="2")
  // Remote rows: one with same ts (should merge), one new.
  let remote_match = @core.CRDTRow::new(
    0L, [@core.Value::Int(99L)], 100L, "siteB",
  )
  let remote_new = @core.CRDTRow::new(
    2000L, [@core.Value::Int(3L)], 101L, "siteB",
  )
  let merged = a.merge_crdt([remote_match, remote_new])
  inspect(merged, content="2")
  inspect(a.crdt_rows.length(), content="3")
}

///| Sync packet carries crdt_rows when CRDT enabled, empty otherwise.
test "sync_packet_includes_crdt_when_enabled" {
  let db = TimeSeriesStore::with_config(50, "siteA")
  db.enable_crdt()
  let _ = db.insert(0L, [@core.Value::Int(1L)])
  let _ = db.insert(1000L, [@core.Value::Int(2L)])
  let pkt = db.get_changes_since(0L)
  inspect(pkt.crdt_rows.length(), content="2")
  let db2 = TimeSeriesStore::with_threshold(50)
  let _ = db2.insert(0L, [@core.Value::Int(99L)])
  let pkt2 = db2.get_changes_since(0L)
  // CRDT off → empty
  inspect(pkt2.crdt_rows.length(), content="0")
}

///| Shape-based pull only sends changes within the time range.
test "shape_pull_filters_by_range" {
  let db = TimeSeriesStore::with_threshold(50)
  let _ = db.insert(100L, [@core.Value::Int(1L)])
  let _ = db.insert(500L, [@core.Value::Int(2L)])
  let _ = db.insert(1500L, [@core.Value::Int(3L)])
  let _ = db.insert(2500L, [@core.Value::Int(4L)])
  let shape = @core.Shape::time_range(400L, 1600L)
  let pkt = db.get_changes_since_shape(0L, shape)
  inspect(pkt.changes.length(), content="2") // ts=500 and 1500
}
