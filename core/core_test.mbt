///| Delta encoding round-trips losslessly on a strictly-increasing sequence
/// of timestamps — the common shape for time-series data.
test "delta_encode_decode_roundtrip" {
  let xs : Array[Int64] = [1000L, 1001L, 1003L, 1010L, 1100L]
  let (base, deltas) = delta_encode(xs)
  inspect(base, content="1000")
  inspect(delta_decode(base, deltas), content="[1000, 1001, 1003, 1010, 1100]")
}

///| Compression ratio is > 1 when deltas are smaller than absolute values.
test "delta_compression_ratio" {
  let xs : Array[Int64] = [10000L, 10001L, 10002L, 10003L]
  let (_, deltas) = delta_encode(xs)
  let ratio = compression_ratio(xs, deltas)
  inspect(ratio > 1.0, content="true")
}

///| Round-trip a JSON object → JsonValue → field accessors.
test "json_parse_object" {
  let input = "{\"name\":\"foo\",\"count\":42,\"active\":true}"
  let json = parse_json(input).unwrap()
  inspect(json.get("name").unwrap().as_string(), content="Some(\"foo\")")
  inspect(json.get("count").unwrap().as_int(), content="Some(42)")
  inspect(json.get("active").unwrap().as_bool(), content="Some(true)")
}

///| ChangeLog appends, gives back entries since a sequence number.
test "changelog_append_and_replay" {
  let log = ChangeLog::new()
  let r1 : Row = { ts: 100L, values: [Value::Int(1L)] }
  let r2 : Row = { ts: 200L, values: [Value::Int(2L)] }
  let _ = log.append(Insert(r1), 100L)
  let _ = log.append(Insert(r2), 200L)
  let _ = log.append(Delete(100L), 300L)
  inspect(log.len(), content="3")
  let since_first = log.get_since(0L)
  inspect(since_first.length(), content="3")
  let after_two = log.get_since(2L)
  inspect(after_two.length(), content="1")
}

///| Filter::Eq matches rows whose column equals a literal.
test "filter_eq" {
  let row : Row = { ts: 0L, values: [Value::Int(7L), Value::String("alpha")] }
  let f1 = Filter::Eq(0, Value::Int(7L))
  inspect(f1.matches(row), content="true")
  let f2 = Filter::Eq(0, Value::Int(8L))
  inspect(f2.matches(row), content="false")
  let f3 = Filter::Eq(1, Value::String("alpha"))
  inspect(f3.matches(row), content="true")
}

///| TimeUnit conversion is the same as the well-known constants.
test "time_unit_to_ms" {
  inspect(TimeUnit::Second.to_ms(), content="1000")
  inspect(TimeUnit::Minute.to_ms(), content="60000")
  inspect(TimeUnit::Hour.to_ms(), content="3600000")
}

///| LamportClock advances on tick and on update with remote.
test "lamport_clock" {
  let clk = LamportClock::new("siteA")
  inspect(clk.tick(), content="1")
  inspect(clk.tick(), content="2")
  clk.update(10L)
  inspect(clk.tick(), content="11")
}

///| LWW merge picks the higher timestamp; tie broken by site_id.
test "lww_merge" {
  let a : LWWValue = { value: Value::Int(1L), timestamp: 5L, site_id: "a" }
  let b : LWWValue = { value: Value::Int(2L), timestamp: 7L, site_id: "b" }
  let merged = a.merge(b)
  inspect(merged.timestamp, content="7")
}

///| VectorClock per-site counter increments + merges.
test "vector_clock" {
  let v = VectorClock::new()
  v.increment("a")
  v.increment("a")
  v.increment("b")
  inspect(v.get("a"), content="2")
  inspect(v.get("b"), content="1")
  let other = VectorClock::new()
  other.increment("b")
  other.increment("c")
  v.update(other)
  inspect(v.get("c"), content="1")
}

///| FirstWriteWins keeps the older timestamp's value.
test "fww_keeps_older" {
  let a : LWWValue = { value: Value::Int(1L), timestamp: 5L, site_id: "a" }
  let b : LWWValue = { value: Value::Int(2L), timestamp: 7L, site_id: "b" }
  let merged = a.merge_with(b, FirstWriteWins)
  inspect(merged.timestamp, content="5")
}

///| MaxValue picks the larger numeric, regardless of clock.
test "max_value_picks_larger" {
  let small : LWWValue = { value: Value::Int(10L), timestamp: 100L, site_id: "a" }
  let large : LWWValue = { value: Value::Int(99L), timestamp: 50L, site_id: "b" }
  let merged = small.merge_with(large, MaxValue)
  match merged.value {
    Value::Int(v) => inspect(v, content="99")
    _ => abort("expected int")
  }
}

///| PreferSite biases toward a specific writer regardless of clock.
test "prefer_site_overrides_clock" {
  let a : LWWValue = { value: Value::Int(1L), timestamp: 99L, site_id: "primary" }
  let b : LWWValue = { value: Value::Int(2L), timestamp: 1L, site_id: "replica" }
  let merged = a.merge_with(b, PreferSite("primary"))
  inspect(merged.site_id, content="primary")
  inspect(merged.timestamp, content="99")
}
