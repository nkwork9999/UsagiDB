// Umbrella UsagiDB. Holds an optional handle to each storage mode. Today
// there's only `ts` (time-series); future modes (`kv`, `stream`, `vector`,
// ...) plug in here as additional `Option<...>` fields and `enable_*` methods.

///|
pub(all) struct UsagiDB {
  mut ts : @ts.TimeSeriesStore?
  mut stream : @stream.EventStore?
  mut log : @log.LogStore?
  mut search : @search.SearchIndex?
  mut vector : @vector.VectorStore?
  mut kv : @kv.KVStore?
}

///|
/// Empty umbrella with no modes enabled. Call `enable_*` to opt in.
pub fn UsagiDB::new() -> UsagiDB {
  { ts: None, stream: None, log: None, search: None, vector: None, kv: None }
}

///|
/// Enable the in-memory key/value store.
pub fn UsagiDB::enable_kv(self : UsagiDB) -> UsagiDB {
  self.kv = Some(@kv.KVStore::new())
  self
}

///|
fn UsagiDB::require_kv(self : UsagiDB) -> @kv.KVStore {
  match self.kv {
    Some(kv) => kv
    None => abort("UsagiDB: kv mode not enabled — call enable_kv() first")
  }
}

///|
pub fn UsagiDB::kv_put(
  self : UsagiDB,
  key : String,
  value : @core.Value,
) -> Unit {
  self.require_kv().put(key, value)
}

///|
pub fn UsagiDB::kv_get(self : UsagiDB, key : String) -> @core.Value? {
  self.require_kv().get(key)
}

///|
pub fn UsagiDB::kv_delete(self : UsagiDB, key : String) -> Bool {
  self.require_kv().delete(key)
}

///|
pub fn UsagiDB::kv_contains(self : UsagiDB, key : String) -> Bool {
  self.require_kv().contains(key)
}

///|
pub fn UsagiDB::kv_size(self : UsagiDB) -> Int {
  self.require_kv().size()
}

///|
pub fn UsagiDB::kv_is_empty(self : UsagiDB) -> Bool {
  self.require_kv().is_empty()
}

///|
pub fn UsagiDB::kv_keys(self : UsagiDB) -> Array[String] {
  self.require_kv().keys()
}

///|
pub fn UsagiDB::kv_values(self : UsagiDB) -> Array[@core.Value] {
  self.require_kv().values()
}

///|
pub fn UsagiDB::kv_entries(self : UsagiDB) -> Array[@kv.KVEntry] {
  self.require_kv().entries_snapshot()
}

///|
pub fn UsagiDB::kv_get_or(
  self : UsagiDB,
  key : String,
  fallback : @core.Value,
) -> @core.Value {
  self.require_kv().get_or(key, fallback)
}

///|
pub fn UsagiDB::kv_put_if_absent(
  self : UsagiDB,
  key : String,
  value : @core.Value,
) -> Bool {
  self.require_kv().put_if_absent(key, value)
}

///|
pub fn UsagiDB::kv_replace_existing(
  self : UsagiDB,
  key : String,
  value : @core.Value,
) -> Bool {
  self.require_kv().replace_existing(key, value)
}

///|
pub fn UsagiDB::kv_take(self : UsagiDB, key : String) -> @core.Value? {
  self.require_kv().take(key)
}

///|
pub fn UsagiDB::kv_clear(self : UsagiDB) -> Unit {
  self.require_kv().clear()
}

///|
pub fn UsagiDB::kv_first(self : UsagiDB) -> @kv.KVEntry? {
  self.require_kv().first()
}

///|
pub fn UsagiDB::kv_last(self : UsagiDB) -> @kv.KVEntry? {
  self.require_kv().last()
}

///|
pub fn UsagiDB::kv_key_at(self : UsagiDB, index : Int) -> String? {
  self.require_kv().key_at(index)
}

///|
pub fn UsagiDB::kv_value_at(self : UsagiDB, index : Int) -> @core.Value? {
  self.require_kv().value_at(index)
}

///|
pub fn UsagiDB::kv_index_of(self : UsagiDB, key : String) -> Int {
  self.require_kv().index_of(key)
}

///|
pub fn UsagiDB::kv_rename(self : UsagiDB, from : String, to : String) -> Bool {
  self.require_kv().rename(from, to)
}

///|
pub fn UsagiDB::kv_swap(self : UsagiDB, left : String, right : String) -> Bool {
  self.require_kv().swap(left, right)
}

///|
pub fn UsagiDB::kv_keys_with_prefix(
  self : UsagiDB,
  prefix : String,
) -> Array[String] {
  self.require_kv().keys_with_prefix(prefix)
}

///|
pub fn UsagiDB::kv_count_prefix(self : UsagiDB, prefix : String) -> Int {
  self.require_kv().count_prefix(prefix)
}

///|
pub fn UsagiDB::kv_delete_prefix(self : UsagiDB, prefix : String) -> Int {
  self.require_kv().delete_prefix(prefix)
}

///|
pub fn UsagiDB::kv_retain_prefix(self : UsagiDB, prefix : String) -> Int {
  self.require_kv().retain_prefix(prefix)
}

///|
pub fn UsagiDB::kv_merge_from(self : UsagiDB, other : @kv.KVStore) -> Int {
  self.require_kv().merge_from(other)
}

///|
/// Enable the vector store with a fixed embedding dimension.
pub fn UsagiDB::enable_vector(
  self : UsagiDB,
  dim : Int,
  metric? : @vector.DistanceMetric = Cosine,
) -> UsagiDB {
  self.vector = Some(@vector.VectorStore::new(dim, metric~))
  self
}

///|
fn UsagiDB::require_vector(self : UsagiDB) -> @vector.VectorStore {
  match self.vector {
    Some(v) => v
    None =>
      abort("UsagiDB: vector mode not enabled — call enable_vector() first")
  }
}

///|
pub fn UsagiDB::vector_insert(
  self : UsagiDB,
  id : String,
  embedding : Array[Double],
) -> Bool {
  self.require_vector().insert(id, embedding)
}

///|
pub fn UsagiDB::vector_search(
  self : UsagiDB,
  query : Array[Double],
  k : Int,
) -> Array[(String, Double)] {
  self.require_vector().search(query, k)
}

// =============================================================================
// SQL-ish builder. `db.query()` returns a `Query` you fluent-build, then
// `.execute(db.ts)` (or umbrella-level shortcut below).
// =============================================================================

///|
pub fn UsagiDB::query(self : UsagiDB) -> @sql.Query {
  let _ = self
  @sql.Query::from_ts()
}

///|
/// Convenience: run a built `Query` against this DB's ts store.
pub fn UsagiDB::query_run(self : UsagiDB, q : @sql.Query) -> @sql.QueryResult {
  q.execute(self.require_ts())
}

///|
/// Enable the full-text search index.
pub fn UsagiDB::enable_search(self : UsagiDB) -> UsagiDB {
  self.search = Some(@search.SearchIndex::new())
  self
}

///|
fn UsagiDB::require_search(self : UsagiDB) -> @search.SearchIndex {
  match self.search {
    Some(s) => s
    None =>
      abort("UsagiDB: search mode not enabled — call enable_search() first")
  }
}

///|
pub fn UsagiDB::search_index(
  self : UsagiDB,
  doc_id : String,
  text : String,
) -> Unit {
  self.require_search().index(doc_id, text)
}

///|
pub fn UsagiDB::search_query(
  self : UsagiDB,
  query : String,
) -> Array[(String, Int)] {
  self.require_search().search(query)
}

///|
/// Enable the time-series mode. `threshold` controls compaction.
pub fn UsagiDB::enable_ts(self : UsagiDB, threshold? : Int = 100) -> UsagiDB {
  self.ts = Some(@ts.TimeSeriesStore::with_threshold(threshold))
  self
}

///|
/// Enable the stream mode (jellyfish_moon-style realtime compaction).
/// Pass a pre-built `CompactionConfig` to set per-key strategies up front,
/// or omit it for an empty config that the caller can mutate afterwards
/// via `db.stream.unwrap()`.
pub fn UsagiDB::enable_stream(
  self : UsagiDB,
  config? : @stream.CompactionConfig,
) -> UsagiDB {
  let cfg = match config {
    Some(c) => c
    None => @stream.CompactionConfig::new()
  }
  self.stream = Some(@stream.EventStore::new(cfg))
  self
}

///|
/// v0.1 compatibility shortcut — `UsagiDB::with_threshold(t)` is now
/// `new().enable_ts(threshold=t)`.
pub fn UsagiDB::with_threshold(threshold : Int) -> UsagiDB {
  UsagiDB::new().enable_ts(threshold~)
}

// =============================================================================
// Facade methods — delegate to the ts mode (panic if not enabled).
// =============================================================================

///|
fn UsagiDB::require_ts(self : UsagiDB) -> @ts.TimeSeriesStore {
  match self.ts {
    Some(t) => t
    None => abort("UsagiDB: ts mode not enabled — call enable_ts() first")
  }
}

///|
pub fn UsagiDB::insert(
  self : UsagiDB,
  ts : Int64,
  values : Array[@core.Value],
) -> Int {
  self.require_ts().insert(ts, values)
}

///|
pub fn UsagiDB::scan(
  self : UsagiDB,
  start : Int64,
  end : Int64,
) -> Array[@core.Row] {
  self.require_ts().scan(start, end)
}

///|
pub fn UsagiDB::stats(self : UsagiDB) -> String {
  self.require_ts().stats()
}

///|
pub fn UsagiDB::serialize(self : UsagiDB) -> String {
  self.require_ts().serialize()
}

///|
/// Round-trip a serialized TS-mode UsagiDB. Mode flags must match the source.
pub fn UsagiDB::deserialize(json_str : String) -> UsagiDB? {
  match @ts.TimeSeriesStore::deserialize(json_str) {
    Some(t) =>
      Some({
        ts: Some(t),
        stream: None,
        log: None,
        search: None,
        vector: None,
        kv: None,
      })
    None => None
  }
}

// =============================================================================
// Stream-mode facade. The stream store is in-memory only — no persistence,
// just compaction. Forward `put` for the most common use; advanced ops go
// through `db.stream.unwrap()` directly.
// =============================================================================

// =============================================================================
// Stream-mode facade. The stream store is in-memory only — no persistence,
// just compaction. Forward `put` for the most common use; advanced ops go
// through `db.stream.unwrap()` directly.
// =============================================================================

///|
fn UsagiDB::require_stream(self : UsagiDB) -> @stream.EventStore {
  match self.stream {
    Some(s) => s
    None =>
      abort("UsagiDB: stream mode not enabled — call enable_stream() first")
  }
}

///|
pub fn UsagiDB::stream_put(
  self : UsagiDB,
  key : String,
  value : Double,
  time : Int64,
) -> @stream.PutResult {
  self.require_stream().put(key, value, time)
}

///|
pub fn UsagiDB::stream_query(
  self : UsagiDB,
  key : String,
) -> Array[@stream.Row] {
  self.require_stream().query(key)
}

// =============================================================================
// Log-mode facade. Kafka-like multi-topic, multi-consumer-group append log.
// =============================================================================

///|
pub fn UsagiDB::enable_log(self : UsagiDB) -> UsagiDB {
  self.log = Some(@log.LogStore::new())
  self
}

///|
fn UsagiDB::require_log(self : UsagiDB) -> @log.LogStore {
  match self.log {
    Some(l) => l
    None => abort("UsagiDB: log mode not enabled — call enable_log() first")
  }
}

///|
pub fn UsagiDB::log_produce(
  self : UsagiDB,
  topic : String,
  value : @core.Value,
  key? : String? = None,
  timestamp? : Int64 = 0L,
) -> Int64 {
  self.require_log().produce(topic, value, key~, timestamp~)
}

///|
pub fn UsagiDB::log_subscribe(
  self : UsagiDB,
  topic : String,
  group : String,
) -> Unit {
  self.require_log().subscribe(topic, group)
}

///|
pub fn UsagiDB::log_poll(
  self : UsagiDB,
  topic : String,
  group : String,
  max : Int,
) -> Array[@log.LogRecord] {
  self.require_log().poll(topic, group, max)
}

///|
pub fn UsagiDB::log_commit(
  self : UsagiDB,
  topic : String,
  group : String,
  offset : Int64,
) -> Unit {
  self.require_log().commit(topic, group, offset)
}

///|
pub fn UsagiDB::log_seek(
  self : UsagiDB,
  topic : String,
  group : String,
  offset : Int64,
) -> Unit {
  self.require_log().seek(topic, group, offset)
}

///|
/// Bridge log → stream: drain `topic` for `group`, forward Float/Int values
/// to the stream store under `stream_key`. Returns piped count. Requires
/// both log and stream modes enabled.
pub fn UsagiDB::log_to_stream(
  self : UsagiDB,
  topic : String,
  group : String,
  stream_key : String,
  max? : Int = 1024,
) -> Int {
  self
  .require_log()
  .pipe_to_stream(topic, group, self.require_stream(), stream_key, max~)
}

///|
/// Serialize the log mode (topics + records + group offsets) to JSON. Use
/// this as the source bytes for OPFS / IndexedDB / network sync.
pub fn UsagiDB::log_serialize(self : UsagiDB) -> String {
  self.require_log().serialize()
}

///|
/// Replace this DB's log store with one parsed from `json_str`. Returns
/// `false` if the JSON didn't parse; ts/stream modes are unchanged.
pub fn UsagiDB::log_deserialize(self : UsagiDB, json_str : String) -> Bool {
  match @log.LogStore::deserialize(json_str) {
    Some(restored) => {
      self.log = Some(restored)
      true
    }
    None => false
  }
}

// =============================================================================
// Stream-mode serialize/restore. Note: config (rules/triggers/validators) is
// NOT persisted; the caller rebuilds it before calling `stream_restore_from`.
// =============================================================================

///|
pub fn UsagiDB::stream_serialize(self : UsagiDB) -> String {
  self.require_stream().serialize()
}

///|
pub fn UsagiDB::stream_restore_from(self : UsagiDB, json_str : String) -> Bool {
  self.require_stream().restore_from(json_str)
}

// =============================================================================
// Sync transport facades. Pair with a WebSocket / HTTP / WebRTC transport in
// JS. The packet itself is JSON; transport is the host's choice.
// =============================================================================

///|
/// Build a JSON SyncPacket carrying changes since `since_seq`. Send this to
/// the remote over your transport of choice.
pub fn UsagiDB::sync_pull_json(self : UsagiDB, since_seq : Int64) -> String {
  let packet = self.require_ts().get_changes_since(since_seq)
  @ts.sync_packet_to_json(packet)
}

///|
/// Like `sync_pull_json` but filtered through a `Shape` — only changes that
/// match the shape's time range / column filter are sent.
pub fn UsagiDB::sync_pull_shape_json(
  self : UsagiDB,
  since_seq : Int64,
  shape : @core.Shape,
) -> String {
  let packet = self.require_ts().get_changes_since_shape(since_seq, shape)
  @ts.sync_packet_to_json(packet)
}

///|
/// Apply a JSON SyncPacket received from a remote. Returns the SyncResult
/// (`Success(n)` / `Conflict([ts...])` / `Error(...)`).
pub fn UsagiDB::sync_apply_json(
  self : UsagiDB,
  json_str : String,
) -> @core.SyncResult {
  match @ts.sync_packet_from_json(json_str) {
    None => @core.SyncResult::Error("invalid sync packet")
    Some(pkt) => self.require_ts().apply_changes(pkt)
  }
}
