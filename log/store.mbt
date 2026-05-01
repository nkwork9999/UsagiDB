// LogStore — Kafka-like local broker.
//
// Design notes (vs. core.ChangeLog which is single-stream):
//   * topics:    Map[String, Topic]
//   * groups:    committed offset per (group_id, topic)
//   * retention: per-topic time/size bound
//   * produce:   accepts arbitrary Value + headers, no TS-DB row required

///|
struct Topic {
  name : String
  records : Array[LogRecord]
  mut next_offset : Int64
  retention : LogRetention
}

///|
fn Topic::new(name : String) -> Topic {
  { name, records: [], next_offset: 0L, retention: LogRetention::none() }
}

///|
pub struct LogStore {
  topics : Map[String, Topic]
  // Composite key "group\x1ftopic" → committed offset for that group on that
  // topic. Composite-key map keeps the API uniform without nested maps.
  group_offsets : Map[String, Int64]
}

///|
pub fn LogStore::new() -> LogStore {
  { topics: Map::new(), group_offsets: Map::new() }
}

///|
fn LogStore::ensure_topic(self : LogStore, name : String) -> Topic {
  match self.topics.get(name) {
    Some(t) => t
    None => {
      let t = Topic::new(name)
      self.topics[name] = t
      t
    }
  }
}

///| Composite group×topic key. The `\x1f` (Unit Separator) is unlikely to
/// appear in either string and avoids clashes that "groupA-topic" could have.
fn group_key(group : String, topic : String) -> String {
  group + "\u{1f}" + topic
}

///| Create a topic up front (optional — produce will auto-create).
pub fn LogStore::create_topic(self : LogStore, name : String) -> Unit {
  let _ = self.ensure_topic(name)

}

///| Set retention. Either argument may be `None` to mean unbounded.
pub fn LogStore::set_retention(
  self : LogStore,
  topic : String,
  max_records~ : Int? = None,
  max_age_ms~ : Int64? = None,
) -> Unit {
  let t = self.ensure_topic(topic)
  t.retention.max_records = max_records
  t.retention.max_age_ms = max_age_ms
}

///| Append a record to `topic`, return the assigned offset. Auto-creates the
/// topic if it doesn't exist. Eagerly applies `max_records` retention.
pub fn LogStore::produce(
  self : LogStore,
  topic : String,
  value : @core.Value,
  key~ : String? = None,
  timestamp~ : Int64 = 0L,
  headers~ : Array[(String, String)] = [],
) -> Int64 {
  let t = self.ensure_topic(topic)
  let offset = t.next_offset
  t.records.push({ offset, timestamp, key, value, headers })
  t.next_offset = offset + 1L
  // Eager max_records retention — drop the head when the topic exceeds it.
  match t.retention.max_records {
    Some(n) =>
      while t.records.length() > n {
        let _ = t.records.remove(0)

      }
    None => ()
  }
  offset
}

///| Register a consumer group on a topic at offset 0 (idempotent — does
/// nothing if already subscribed). Future `poll` calls advance from that
/// committed offset.
pub fn LogStore::subscribe(
  self : LogStore,
  topic : String,
  group : String,
) -> Unit {
  let _ = self.ensure_topic(topic)
  let k = group_key(group, topic)
  if self.group_offsets.get(k) is None {
    self.group_offsets[k] = 0L
  }
}

///| Read up to `max` records from the consumer group's committed offset.
/// Auto-advances the committed offset (use `peek` + `commit` for manual
/// control). Returns an empty array if the topic doesn't exist.
pub fn LogStore::poll(
  self : LogStore,
  topic : String,
  group : String,
  max : Int,
) -> Array[LogRecord] {
  let k = group_key(group, topic)
  let committed = match self.group_offsets.get(k) {
    Some(o) => o
    None => 0L
  }
  let result : Array[LogRecord] = []
  match self.topics.get(topic) {
    None => return result
    Some(t) => {
      let mut taken = 0
      let mut new_offset = committed
      for r in t.records {
        if taken >= max {
          break
        }
        if r.offset >= committed {
          result.push(r)
          new_offset = r.offset + 1L
          taken = taken + 1
        }
      }
      self.group_offsets[k] = new_offset
    }
  }
  result
}

///| Peek without advancing the committed offset.
pub fn LogStore::peek(
  self : LogStore,
  topic : String,
  group : String,
  max : Int,
) -> Array[LogRecord] {
  let k = group_key(group, topic)
  let committed = match self.group_offsets.get(k) {
    Some(o) => o
    None => 0L
  }
  let result : Array[LogRecord] = []
  match self.topics.get(topic) {
    None => return result
    Some(t) => {
      let mut taken = 0
      for r in t.records {
        if taken >= max {
          break
        }
        if r.offset >= committed {
          result.push(r)
          taken = taken + 1
        }
      }
    }
  }
  result
}

///| Manually commit the consumer group's offset. After `commit(t, g, N)`,
/// next `poll` returns records with `offset > N`.
pub fn LogStore::commit(
  self : LogStore,
  topic : String,
  group : String,
  offset : Int64,
) -> Unit {
  self.group_offsets[group_key(group, topic)] = offset + 1L
}

///| Move the consumer group's offset to `offset` (rewind or fast-forward).
pub fn LogStore::seek(
  self : LogStore,
  topic : String,
  group : String,
  offset : Int64,
) -> Unit {
  self.group_offsets[group_key(group, topic)] = offset
}

///| Current committed offset (= next offset to read) for the group.
pub fn LogStore::current_offset(
  self : LogStore,
  topic : String,
  group : String,
) -> Int64 {
  match self.group_offsets.get(group_key(group, topic)) {
    Some(o) => o
    None => 0L
  }
}

///| Names of all topics in the store.
pub fn LogStore::list_topics(self : LogStore) -> Array[String] {
  let names : Array[String] = []
  for entry in self.topics {
    names.push(entry.0)
  }
  names
}

///| (earliest_offset, latest_offset, count) for a topic, or `None`.
pub fn LogStore::topic_info(
  self : LogStore,
  topic : String,
) -> (Int64, Int64, Int)? {
  match self.topics.get(topic) {
    None => None
    Some(t) =>
      if t.records.length() == 0 {
        Some((0L, 0L, 0))
      } else {
        let earliest = t.records[0].offset
        let latest = t.records[t.records.length() - 1].offset
        Some((earliest, latest, t.records.length()))
      }
  }
}

///| Drop records older than `now - max_age_ms`. Returns the count removed.
/// Has no effect if the topic has no `max_age_ms` set.
pub fn LogStore::apply_retention(
  self : LogStore,
  topic : String,
  now : Int64,
) -> Int {
  match self.topics.get(topic) {
    None => 0
    Some(t) =>
      match t.retention.max_age_ms {
        None => 0
        Some(window) => {
          let cutoff = now - window
          let mut dropped = 0
          let kept : Array[LogRecord] = []
          for r in t.records {
            if r.timestamp >= cutoff {
              kept.push(r)
            } else {
              dropped = dropped + 1
            }
          }
          // Rebuild the records array — using `clear` + `push` keeps the same
          // array reference so any external aliases (none here, but defensive)
          // stay valid.
          t.records.clear()
          for r in kept {
            t.records.push(r)
          }
          dropped
        }
      }
  }
}
