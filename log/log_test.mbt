///| Produce assigns monotonic offsets starting at 0.
test "produce_assigns_offsets" {
  let log = LogStore::new()
  let o0 = log.produce("temp", @core.Value::Float(20.0))
  let o1 = log.produce("temp", @core.Value::Float(21.0))
  let o2 = log.produce("temp", @core.Value::Float(22.0))
  inspect(o0, content="0")
  inspect(o1, content="1")
  inspect(o2, content="2")
}

///| Poll advances the consumer group's committed offset.
test "poll_advances_offset" {
  let log = LogStore::new()
  log.subscribe("t", "g")
  let _ = log.produce("t", @core.Value::Int(1L))
  let _ = log.produce("t", @core.Value::Int(2L))
  let _ = log.produce("t", @core.Value::Int(3L))
  let first = log.poll("t", "g", 2)
  inspect(first.length(), content="2")
  let second = log.poll("t", "g", 2)
  inspect(second.length(), content="1")
  let third = log.poll("t", "g", 2)
  inspect(third.length(), content="0")
}

///| Two consumer groups read the same topic independently.
test "multiple_consumer_groups" {
  let log = LogStore::new()
  log.subscribe("topic", "dashboard")
  log.subscribe("topic", "archive")
  let _ = log.produce("topic", @core.Value::Int(10L))
  let _ = log.produce("topic", @core.Value::Int(20L))
  let _ = log.produce("topic", @core.Value::Int(30L))
  // Dashboard reads everything.
  let dash = log.poll("topic", "dashboard", 100)
  inspect(dash.length(), content="3")
  // Archive only takes the first.
  let arch = log.poll("topic", "archive", 1)
  inspect(arch.length(), content="1")
  inspect(log.current_offset("topic", "dashboard"), content="3")
  inspect(log.current_offset("topic", "archive"), content="1")
}

///| Seek rewinds the offset so subsequent polls re-read.
test "seek_rewinds" {
  let log = LogStore::new()
  log.subscribe("t", "g")
  let _ = log.produce("t", @core.Value::Int(1L))
  let _ = log.produce("t", @core.Value::Int(2L))
  let _ = log.poll("t", "g", 100)
  inspect(log.current_offset("t", "g"), content="2")
  log.seek("t", "g", 0L)
  inspect(log.poll("t", "g", 100).length(), content="2")
}

///| Commit explicitly sets the offset to skip past records.
test "commit_explicit" {
  let log = LogStore::new()
  log.subscribe("t", "g")
  let _ = log.produce("t", @core.Value::Int(1L))
  let _ = log.produce("t", @core.Value::Int(2L))
  let _ = log.produce("t", @core.Value::Int(3L))
  log.commit("t", "g", 1L) // mark offset 1 as last consumed
  let rest = log.poll("t", "g", 100)
  inspect(rest.length(), content="1") // only offset 2
}

///| max_records retention drops the oldest records on overflow.
test "retention_max_records" {
  let log = LogStore::new()
  log.set_retention("t", max_records=Some(3))
  for i = 0; i < 5; i = i + 1 {
    let _ = log.produce("t", @core.Value::Int(i.to_int64()))

  }
  let info = log.topic_info("t").unwrap()
  let (_, _, count) = info
  inspect(count, content="3")
}

///| max_age_ms retention drops records older than `now - window`.
test "retention_max_age" {
  let log = LogStore::new()
  log.set_retention("t", max_age_ms=Some(1000L))
  let _ = log.produce("t", @core.Value::Int(1L), timestamp=0L)
  let _ = log.produce("t", @core.Value::Int(2L), timestamp=500L)
  let _ = log.produce("t", @core.Value::Int(3L), timestamp=1500L)
  let dropped = log.apply_retention("t", 2000L) // cutoff = 1000
  inspect(dropped, content="2")
  let (_, _, count) = log.topic_info("t").unwrap()
  inspect(count, content="1")
}

///| Headers and key are preserved on the record.
test "headers_and_key" {
  let log = LogStore::new()
  let _ = log.produce(
    "events",
    @core.Value::String("clicked"),
    key=Some("user_42"),
    timestamp=12345L,
    headers=[("source", "web"), ("priority", "high")],
  )
  let rows = log.peek("events", "g", 10)
  inspect(rows.length(), content="1")
  inspect(rows[0].key, content="Some(\"user_42\")")
  inspect(rows[0].headers.length(), content="2")
}

///| Bridge: log records flow into a stream EventStore as Float samples.
test "pipe_to_stream" {
  let log = LogStore::new()
  let cfg = @stream.CompactionConfig::new()
  let _ = cfg.rule("price", @stream.KeepLastN(10))
  let stream = @stream.EventStore::new(cfg)
  let _ = log.produce("ticks", @core.Value::Float(100.0), timestamp=0L)
  let _ = log.produce("ticks", @core.Value::Float(101.5), timestamp=1L)
  let _ = log.produce("ticks", @core.Value::String("noise"), timestamp=2L)
  let _ = log.produce("ticks", @core.Value::Int(102L), timestamp=3L)
  let piped = log.pipe_to_stream("ticks", "stream", stream, "price")
  inspect(piped, content="3") // String skipped, the other 3 forwarded
  inspect(stream.query("price").length(), content="3")
}

///| List topics shows all created topics.
test "list_topics" {
  let log = LogStore::new()
  let _ = log.produce("a", @core.Value::Null)
  let _ = log.produce("b", @core.Value::Null)
  log.create_topic("c")
  let topics = log.list_topics()
  inspect(topics.length(), content="3")
}

///| Serialize → deserialize round-trip preserves topics, records, and offsets.
test "serialize_deserialize_roundtrip" {
  let log = LogStore::new()
  log.set_retention("temp", max_records=Some(100))
  log.subscribe("temp", "g")
  let _ = log.produce(
    "temp",
    @core.Value::Float(20.5),
    key=Some("sensor-a"),
    timestamp=1000L,
    headers=[("source", "lab1")],
  )
  let _ = log.produce("temp", @core.Value::Float(21.0), timestamp=2000L)
  let _ = log.poll("temp", "g", 1) // bumps committed offset to 1
  let json = log.serialize()
  let restored = LogStore::deserialize(json).unwrap()
  inspect(restored.list_topics().length(), content="1")
  let (_, _, count) = restored.topic_info("temp").unwrap()
  inspect(count, content="2")
  inspect(restored.current_offset("temp", "g"), content="1")
  // Re-poll on the restored store should pick up where the original left off.
  let next = restored.poll("temp", "g", 10)
  inspect(next.length(), content="1")
  inspect(next[0].offset, content="1")
}
