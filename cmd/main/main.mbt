// UsagiDB - Minimal Single File Implementation
// Lightweight HTAP Database for Time Series Data
// With Full Serialization/Deserialization Support

// ============================================
// Types
// ============================================

/// Value type for database cells
pub enum Value {
  Null
  Int(Int64)
  Float(Double)
  String(String)
  Timestamp(Int64)
} derive(Show, Eq)

/// A row with timestamp as primary key
pub struct Row {
  ts : Int64
  values : Array[Value]
} derive(Show)

// ============================================
// Delta Encoding (Compression)
// ============================================

pub fn delta_encode(values : Array[Int64]) -> (Int64, Array[Int64]) {
  if values.length() == 0 {
    return (0L, [])
  }
  
  let base = values[0]
  let deltas : Array[Int64] = []
  
  for i = 1; i < values.length(); i = i + 1 {
    deltas.push(values[i] - values[i - 1])
  }
  
  (base, deltas)
}

pub fn delta_decode(base : Int64, deltas : Array[Int64]) -> Array[Int64] {
  let result : Array[Int64] = [base]
  let mut current = base
  
  for delta in deltas {
    current = current + delta
    result.push(current)
  }
  
  result
}

pub fn compression_ratio(original : Array[Int64], deltas : Array[Int64]) -> Double {
  if original.length() == 0 {
    return 1.0
  }
  
  let mut max_original : Int64 = 0
  for v in original {
    let abs_v = if v < 0L { -v } else { v }
    if abs_v > max_original {
      max_original = abs_v
    }
  }
  
  let mut max_delta : Int64 = 0
  for d in deltas {
    let abs_d = if d < 0L { -d } else { d }
    if abs_d > max_delta {
      max_delta = abs_d
    }
  }
  
  if max_delta == 0L {
    return 10.0
  }
  
  let original_bits = bits_needed(max_original)
  let delta_bits = bits_needed(max_delta)
  
  if delta_bits == 0 {
    10.0
  } else {
    original_bits.to_double() / delta_bits.to_double()
  }
}

fn bits_needed(value : Int64) -> Int {
  if value == 0L {
    return 1
  }
  
  let mut v = if value < 0L { -value } else { value }
  let mut bits = 0
  
  while v > 0L {
    bits = bits + 1
    v = v / 2L
  }
  
  bits
}

// ============================================
// Change Log (for Sync)
// ============================================

/// Operation type for change log
pub enum Operation {
  Insert(Row)
  Delete(Int64)
} derive(Show)

/// A single change entry
pub struct ChangeLogEntry {
  seq : Int64
  timestamp : Int64
  op : Operation
} derive(Show)

/// Change log for tracking all modifications
struct ChangeLog {
  entries : Array[ChangeLogEntry]
  mut next_seq : Int64
}

fn ChangeLog::new() -> ChangeLog {
  { entries: [], next_seq: 1L }
}

fn ChangeLog::append(self : ChangeLog, op : Operation, timestamp : Int64) -> Int64 {
  let seq = self.next_seq
  self.entries.push({ seq, timestamp, op })
  self.next_seq = seq + 1L
  seq
}

fn ChangeLog::get_since(self : ChangeLog, since_seq : Int64) -> Array[ChangeLogEntry] {
  let result : Array[ChangeLogEntry] = []
  for entry in self.entries {
    if entry.seq > since_seq {
      result.push(entry)
    }
  }
  result
}

fn ChangeLog::last_seq(self : ChangeLog) -> Int64 {
  if self.entries.length() == 0 {
    0L
  } else {
    self.entries[self.entries.length() - 1].seq
  }
}

fn ChangeLog::len(self : ChangeLog) -> Int {
  self.entries.length()
}

// ============================================
// Sync State
// ============================================

/// Sync state tracking
pub struct SyncState {
  local_seq : Int64
  remote_seq : Int64
  pending : Int
}

/// Sync result
pub enum SyncResult {
  Success(Int)
  Conflict(Array[Int64])
  Error(String)
} derive(Show)

/// Changes to be synced
pub struct SyncPacket {
  from_seq : Int64
  to_seq : Int64
  changes : Array[ChangeLogEntry]
} derive(Show)

// ============================================
// Compressed Chunk
// ============================================

struct CompressedChunk {
  id : Int
  ts_base : Int64
  ts_deltas : Array[Int64]
  columns : Array[Array[Value]]
  min_ts : Int64
  max_ts : Int64
}

fn CompressedChunk::from_rows(id : Int, rows : Array[Row]) -> CompressedChunk? {
  if rows.length() == 0 {
    return None
  }
  
  let timestamps : Array[Int64] = []
  let mut min_ts = rows[0].ts
  let mut max_ts = rows[0].ts
  
  for row in rows {
    timestamps.push(row.ts)
    if row.ts < min_ts { min_ts = row.ts }
    if row.ts > max_ts { max_ts = row.ts }
  }
  
  let (ts_base, ts_deltas) = delta_encode(timestamps)
  
  let col_count = rows[0].values.length()
  let columns : Array[Array[Value]] = []
  for i = 0; i < col_count; i = i + 1 {
    columns.push([])
  }
  
  for row in rows {
    for i = 0; i < row.values.length() && i < col_count; i = i + 1 {
      columns[i].push(row.values[i])
    }
  }
  
  Some({ id, ts_base, ts_deltas, columns, min_ts, max_ts })
}

fn CompressedChunk::row_count(self : CompressedChunk) -> Int {
  self.ts_deltas.length() + 1
}

fn CompressedChunk::decompress_timestamps(self : CompressedChunk) -> Array[Int64] {
  delta_decode(self.ts_base, self.ts_deltas)
}

fn CompressedChunk::scan(self : CompressedChunk, start : Int64, end : Int64) -> Array[Row] {
  let result : Array[Row] = []
  
  if self.max_ts < start || self.min_ts > end {
    return result
  }
  
  let timestamps = self.decompress_timestamps()
  
  for i = 0; i < timestamps.length(); i = i + 1 {
    let ts = timestamps[i]
    if ts >= start && ts <= end {
      let values : Array[Value] = []
      for col in self.columns {
        values.push(col[i])
      }
      result.push({ ts, values })
    }
  }
  
  result
}

fn CompressedChunk::compression_stats(self : CompressedChunk) -> String {
  let original_count = self.row_count()
  let delta_count = self.ts_deltas.length()
  let timestamps = self.decompress_timestamps()
  let ratio = compression_ratio(timestamps, self.ts_deltas)
  
  "Chunk " + self.id.to_string() + " compression:\n" +
  "  Rows: " + original_count.to_string() + "\n" +
  "  Base: " + self.ts_base.to_string() + "\n" +
  "  Deltas: " + delta_count.to_string() + "\n" +
  "  Estimated ratio: " + ratio.to_string() + "x"
}

// ============================================
// Delta Store (Row-oriented, for writes)
// ============================================

struct DeltaStore {
  mut rows : Array[Row]
  mut next_id : Int
}

fn DeltaStore::new() -> DeltaStore {
  { rows: [], next_id: 0 }
}

fn DeltaStore::insert(self : DeltaStore, row : Row) -> Int {
  let id = self.next_id
  self.rows.push(row)
  self.next_id = id + 1
  id
}

fn DeltaStore::len(self : DeltaStore) -> Int {
  self.rows.length()
}

fn DeltaStore::clear(self : DeltaStore) -> Array[Row] {
  let old = self.rows
  self.rows = []
  self.next_id = 0
  old
}

fn DeltaStore::scan(self : DeltaStore, start : Int64, end : Int64) -> Array[Row] {
  let result : Array[Row] = []
  for row in self.rows {
    if row.ts >= start && row.ts <= end {
      result.push(row)
    }
  }
  result
}

// ============================================
// Chunk (Columnar storage unit)
// ============================================

struct Chunk {
  id : Int
  compressed : CompressedChunk
}

fn Chunk::from_rows(id : Int, rows : Array[Row]) -> Chunk? {
  match CompressedChunk::from_rows(id, rows) {
    Some(compressed) => Some({ id, compressed })
    None => None
  }
}

fn Chunk::row_count(self : Chunk) -> Int {
  self.compressed.row_count()
}

fn Chunk::scan(self : Chunk, start : Int64, end : Int64) -> Array[Row] {
  self.compressed.scan(start, end)
}

fn Chunk::compression_stats(self : Chunk) -> String {
  self.compressed.compression_stats()
}

// ============================================
// Main Store (Column-oriented, for analytics)
// ============================================

struct MainStore {
  chunks : Array[Chunk]
  mut next_chunk_id : Int
}

fn MainStore::new() -> MainStore {
  { chunks: [], next_chunk_id: 0 }
}

fn MainStore::add_chunk(self : MainStore, rows : Array[Row]) -> Int? {
  match Chunk::from_rows(self.next_chunk_id, rows) {
    Some(chunk) => {
      let id = chunk.id
      self.chunks.push(chunk)
      self.next_chunk_id = id + 1
      Some(id)
    }
    None => None
  }
}

fn MainStore::scan(self : MainStore, start : Int64, end : Int64) -> Array[Row] {
  let result : Array[Row] = []
  for chunk in self.chunks {
    let rows = chunk.scan(start, end)
    for row in rows {
      result.push(row)
    }
  }
  result
}

fn MainStore::scan_chunks(self : MainStore, chunk_ids : Array[Int], start : Int64, end : Int64) -> Array[Row] {
  let result : Array[Row] = []
  for chunk in self.chunks {
    let mut found = false
    for id in chunk_ids {
      if chunk.id == id {
        found = true
        break
      }
    }
    if found {
      let rows = chunk.scan(start, end)
      for row in rows {
        result.push(row)
      }
    }
  }
  result
}

fn MainStore::total_rows(self : MainStore) -> Int {
  let mut total = 0
  for chunk in self.chunks {
    total = total + chunk.row_count()
  }
  total
}

// ============================================
// Delete Set (for logical deletion)
// ============================================

struct DeleteSet {
  timestamps : Array[Int64]
}

fn DeleteSet::new() -> DeleteSet {
  { timestamps: [] }
}

fn DeleteSet::add(self : DeleteSet, ts : Int64) -> Unit {
  for t in self.timestamps {
    if t == ts {
      return
    }
  }
  self.timestamps.push(ts)
}

fn DeleteSet::contains(self : DeleteSet, ts : Int64) -> Bool {
  for t in self.timestamps {
    if t == ts {
      return true
    }
  }
  false
}

fn DeleteSet::contains_any(deleted : Array[Int64], ts : Int64) -> Bool {
  for t in deleted {
    if t == ts {
      return true
    }
  }
  false
}

fn DeleteSet::count(self : DeleteSet) -> Int {
  self.timestamps.length()
}

fn DeleteSet::clone_timestamps(self : DeleteSet) -> Array[Int64] {
  let result : Array[Int64] = []
  for t in self.timestamps {
    result.push(t)
  }
  result
}

// ============================================
// Snapshot (for time travel)
// ============================================

struct Snapshot {
  id : Int
  chunk_ids : Array[Int]
  deleted_timestamps : Array[Int64]
}

fn Snapshot::new(id : Int, chunk_ids : Array[Int], deleted : Array[Int64]) -> Snapshot {
  { id, chunk_ids, deleted_timestamps: deleted }
}

// ============================================
// Filter (WHERE clause)
// ============================================

pub enum Filter {
  Eq(Int, Value)
  Ne(Int, Value)
  Gt(Int, Value)
  Gte(Int, Value)
  Lt(Int, Value)
  Lte(Int, Value)
  And(Filter, Filter)
  Or(Filter, Filter)
  Not(Filter)
  True
} derive(Show)

fn compare_values(a : Value, b : Value) -> Int {
  match (a, b) {
    (Value::Int(x), Value::Int(y)) => {
      if x < y { -1 } else if x > y { 1 } else { 0 }
    }
    (Value::Float(x), Value::Float(y)) => {
      if x < y { -1 } else if x > y { 1 } else { 0 }
    }
    (Value::Int(x), Value::Float(y)) => {
      let xf = x.to_double()
      if xf < y { -1 } else if xf > y { 1 } else { 0 }
    }
    (Value::Float(x), Value::Int(y)) => {
      let yf = y.to_double()
      if x < yf { -1 } else if x > yf { 1 } else { 0 }
    }
    (Value::String(x), Value::String(y)) => {
      if x < y { -1 } else if x > y { 1 } else { 0 }
    }
    _ => 0
  }
}

fn Filter::matches(self : Filter, row : Row) -> Bool {
  match self {
    Filter::True => true
    Filter::Eq(col, val) => {
      if col < row.values.length() {
        row.values[col] == val
      } else {
        false
      }
    }
    Filter::Ne(col, val) => {
      if col < row.values.length() {
        row.values[col] != val
      } else {
        true
      }
    }
    Filter::Gt(col, val) => {
      if col < row.values.length() {
        compare_values(row.values[col], val) > 0
      } else {
        false
      }
    }
    Filter::Gte(col, val) => {
      if col < row.values.length() {
        compare_values(row.values[col], val) >= 0
      } else {
        false
      }
    }
    Filter::Lt(col, val) => {
      if col < row.values.length() {
        compare_values(row.values[col], val) < 0
      } else {
        false
      }
    }
    Filter::Lte(col, val) => {
      if col < row.values.length() {
        compare_values(row.values[col], val) <= 0
      } else {
        false
      }
    }
    Filter::And(f1, f2) => f1.matches(row) && f2.matches(row)
    Filter::Or(f1, f2) => f1.matches(row) || f2.matches(row)
    Filter::Not(f) => !f.matches(row)
  }
}

// ============================================
// Time Unit (for GROUP BY time)
// ============================================

pub enum TimeUnit {
  Millisecond
  Second
  Minute
  Hour
  Day
  Week
} derive(Show)

fn TimeUnit::to_ms(self : TimeUnit) -> Int64 {
  match self {
    TimeUnit::Millisecond => 1L
    TimeUnit::Second => 1000L
    TimeUnit::Minute => 60000L
    TimeUnit::Hour => 3600000L
    TimeUnit::Day => 86400000L
    TimeUnit::Week => 604800000L
  }
}

// ============================================
// UsagiDB (Main Database)
// ============================================

pub struct UsagiDB {
  delta : DeltaStore
  main : MainStore
  deleted : DeleteSet
  snapshots : Array[Snapshot]
  mut next_snapshot_id : Int
  compact_threshold : Int
  changelog : ChangeLog
  mut sync_enabled : Bool
}

pub fn UsagiDB::new() -> UsagiDB {
  {
    delta: DeltaStore::new(),
    main: MainStore::new(),
    deleted: DeleteSet::new(),
    snapshots: [],
    next_snapshot_id: 0,
    compact_threshold: 100,
    changelog: ChangeLog::new(),
    sync_enabled: true
  }
}

pub fn UsagiDB::with_threshold(threshold : Int) -> UsagiDB {
  {
    delta: DeltaStore::new(),
    main: MainStore::new(),
    deleted: DeleteSet::new(),
    snapshots: [],
    next_snapshot_id: 0,
    compact_threshold: threshold,
    changelog: ChangeLog::new(),
    sync_enabled: true
  }
}

pub fn UsagiDB::set_sync_enabled(self : UsagiDB, enabled : Bool) -> Unit {
  self.sync_enabled = enabled
}

pub fn UsagiDB::insert(self : UsagiDB, ts : Int64, values : Array[Value]) -> Int {
  let row : Row = { ts, values }
  let id = self.delta.insert(row)
  
  if self.sync_enabled {
    let row_copy : Row = { ts, values }
    let _ = self.changelog.append(Operation::Insert(row_copy), ts)
  }
  
  if self.delta.len() >= self.compact_threshold {
    let _ = self.compact()
  }
  
  id
}

pub fn UsagiDB::delete(self : UsagiDB, ts : Int64) -> Bool {
  self.deleted.add(ts)
  
  if self.sync_enabled {
    let _ = self.changelog.append(Operation::Delete(ts), ts)
  }
  
  true
}

pub fn UsagiDB::is_deleted(self : UsagiDB, ts : Int64) -> Bool {
  self.deleted.contains(ts)
}

pub fn UsagiDB::deleted_count(self : UsagiDB) -> Int {
  self.deleted.count()
}

pub fn UsagiDB::compact(self : UsagiDB) -> Int? {
  let all_rows = self.delta.clear()
  if all_rows.length() == 0 {
    return None
  }
  
  let rows : Array[Row] = []
  for row in all_rows {
    if !self.deleted.contains(row.ts) {
      rows.push(row)
    }
  }
  
  if rows.length() == 0 {
    return None
  }
  
  match self.main.add_chunk(rows) {
    Some(chunk_id) => {
      let chunk_ids : Array[Int] = []
      for chunk in self.main.chunks {
        chunk_ids.push(chunk.id)
      }
      
      let deleted_copy = self.deleted.clone_timestamps()
      
      let snapshot = Snapshot::new(
        self.next_snapshot_id,
        chunk_ids,
        deleted_copy
      )
      self.snapshots.push(snapshot)
      self.next_snapshot_id = self.next_snapshot_id + 1
      
      Some(chunk_id)
    }
    None => None
  }
}

pub fn UsagiDB::scan(self : UsagiDB, start : Int64, end : Int64) -> Array[Row] {
  let result : Array[Row] = []
  
  let main_rows = self.main.scan(start, end)
  for row in main_rows {
    if !self.deleted.contains(row.ts) {
      result.push(row)
    }
  }
  
  let delta_rows = self.delta.scan(start, end)
  for row in delta_rows {
    if !self.deleted.contains(row.ts) {
      result.push(row)
    }
  }
  
  result.sort_by(fn(a, b) { 
    if a.ts < b.ts { -1 } 
    else if a.ts > b.ts { 1 } 
    else { 0 } 
  })
  
  result
}

pub fn UsagiDB::scan_where(self : UsagiDB, start : Int64, end : Int64, filter : Filter) -> Array[Row] {
  let all_rows = self.scan(start, end)
  let result : Array[Row] = []
  
  for row in all_rows {
    if filter.matches(row) {
      result.push(row)
    }
  }
  
  result
}

pub fn UsagiDB::scan_as_of(self : UsagiDB, snapshot_id : Int, start : Int64, end : Int64) -> Array[Row]? {
  let mut target_snapshot : Snapshot? = None
  for snap in self.snapshots {
    if snap.id == snapshot_id {
      target_snapshot = Some(snap)
      break
    }
  }
  
  match target_snapshot {
    None => None
    Some(snapshot) => {
      let result : Array[Row] = []
      
      let rows = self.main.scan_chunks(snapshot.chunk_ids, start, end)
      
      for row in rows {
        if !DeleteSet::contains_any(snapshot.deleted_timestamps, row.ts) {
          result.push(row)
        }
      }
      
      result.sort_by(fn(a, b) { 
        if a.ts < b.ts { -1 } 
        else if a.ts > b.ts { 1 } 
        else { 0 } 
      })
      
      Some(result)
    }
  }
}

pub fn UsagiDB::list_snapshots(self : UsagiDB) -> Array[Int] {
  let result : Array[Int] = []
  for snap in self.snapshots {
    result.push(snap.id)
  }
  result
}

pub fn UsagiDB::snapshot_info(self : UsagiDB, snapshot_id : Int) -> String? {
  for snap in self.snapshots {
    if snap.id == snapshot_id {
      return Some(
        "Snapshot " + snap.id.to_string() + ":\n" +
        "  Chunks: " + snap.chunk_ids.length().to_string() + "\n" +
        "  Deleted at that time: " + snap.deleted_timestamps.length().to_string()
      )
    }
  }
  None
}

pub fn UsagiDB::stats(self : UsagiDB) -> String {
  let delta_rows = self.delta.len()
  let main_rows = self.main.total_rows()
  let deleted = self.deleted.count()
  let chunks = self.main.chunks.length()
  let snapshots = self.snapshots.length()
  
  "UsagiDB Stats:\n" +
  "  Delta rows: " + delta_rows.to_string() + "\n" +
  "  Main rows: " + main_rows.to_string() + "\n" +
  "  Deleted: " + deleted.to_string() + "\n" +
  "  Visible rows: " + (delta_rows + main_rows - deleted).to_string() + "\n" +
  "  Chunks: " + chunks.to_string() + "\n" +
  "  Snapshots: " + snapshots.to_string() + "\n" +
  "  Changelog entries: " + self.changelog.len().to_string()
}

pub fn UsagiDB::compression_stats(self : UsagiDB) -> String {
  let mut result = "Compression Stats:\n"
  for chunk in self.main.chunks {
    result = result + chunk.compression_stats() + "\n"
  }
  result
}

// ============================================
// Sync Methods
// ============================================

pub fn UsagiDB::sync_state(self : UsagiDB) -> SyncState {
  {
    local_seq: self.changelog.last_seq(),
    remote_seq: 0L,
    pending: self.changelog.len()
  }
}

pub fn UsagiDB::get_changes_since(self : UsagiDB, since_seq : Int64) -> SyncPacket {
  let changes = self.changelog.get_since(since_seq)
  {
    from_seq: since_seq,
    to_seq: self.changelog.last_seq(),
    changes
  }
}

pub fn UsagiDB::apply_changes(self : UsagiDB, packet : SyncPacket) -> SyncResult {
  let mut applied = 0
  let conflicts : Array[Int64] = []
  
  let was_enabled = self.sync_enabled
  self.sync_enabled = false
  
  for entry in packet.changes {
    match entry.op {
      Operation::Insert(row) => {
        let existing = self.scan(row.ts, row.ts)
        if existing.length() > 0 {
          conflicts.push(row.ts)
        }
        let _ = self.delta.insert(row)
        applied = applied + 1
      }
      Operation::Delete(ts) => {
        self.deleted.add(ts)
        applied = applied + 1
      }
    }
  }
  
  self.sync_enabled = was_enabled
  
  if conflicts.length() > 0 {
    SyncResult::Conflict(conflicts)
  } else {
    SyncResult::Success(applied)
  }
}

pub fn UsagiDB::pending_changes(self : UsagiDB) -> Int {
  self.changelog.len()
}

pub fn UsagiDB::ack_sync(self : UsagiDB, up_to_seq : Int64) -> Unit {
  let _ = up_to_seq
  let _ = self
}

// ============================================
// Aggregation Functions
// ============================================

pub enum AggResult {
  IntResult(Int64)
  FloatResult(Double)
  CountResult(Int)
  NullResult
} derive(Show)

pub enum AggType {
  Sum
  Count
  Avg
  Min
  Max
} derive(Show)

pub fn UsagiDB::sum(self : UsagiDB, start : Int64, end : Int64, col_index : Int) -> AggResult {
  let rows = self.scan(start, end)
  
  let mut int_sum : Int64 = 0
  let mut float_sum : Double = 0.0
  let mut has_int = false
  let mut has_float = false
  
  for row in rows {
    if col_index < row.values.length() {
      match row.values[col_index] {
        Value::Int(v) => {
          int_sum = int_sum + v
          has_int = true
        }
        Value::Float(v) => {
          float_sum = float_sum + v
          has_float = true
        }
        _ => ()
      }
    }
  }
  
  if has_float {
    AggResult::FloatResult(float_sum + int_sum.to_double())
  } else if has_int {
    AggResult::IntResult(int_sum)
  } else {
    AggResult::NullResult
  }
}

pub fn UsagiDB::count(self : UsagiDB, start : Int64, end : Int64) -> AggResult {
  let rows = self.scan(start, end)
  AggResult::CountResult(rows.length())
}

pub fn UsagiDB::count_col(self : UsagiDB, start : Int64, end : Int64, col_index : Int) -> AggResult {
  let rows = self.scan(start, end)
  let mut count = 0
  
  for row in rows {
    if col_index < row.values.length() {
      match row.values[col_index] {
        Value::Null => ()
        _ => count = count + 1
      }
    }
  }
  
  AggResult::CountResult(count)
}

pub fn UsagiDB::avg(self : UsagiDB, start : Int64, end : Int64, col_index : Int) -> AggResult {
  let rows = self.scan(start, end)
  
  let mut sum : Double = 0.0
  let mut count = 0
  
  for row in rows {
    if col_index < row.values.length() {
      match row.values[col_index] {
        Value::Int(v) => {
          sum = sum + v.to_double()
          count = count + 1
        }
        Value::Float(v) => {
          sum = sum + v
          count = count + 1
        }
        _ => ()
      }
    }
  }
  
  if count > 0 {
    AggResult::FloatResult(sum / count.to_double())
  } else {
    AggResult::NullResult
  }
}

pub fn UsagiDB::min(self : UsagiDB, start : Int64, end : Int64, col_index : Int) -> AggResult {
  let rows = self.scan(start, end)
  
  let mut min_int : Int64 = 9223372036854775807
  let mut min_float : Double = 1.7976931348623157e308
  let mut has_int = false
  let mut has_float = false
  
  for row in rows {
    if col_index < row.values.length() {
      match row.values[col_index] {
        Value::Int(v) => {
          if v < min_int { min_int = v }
          has_int = true
        }
        Value::Float(v) => {
          if v < min_float { min_float = v }
          has_float = true
        }
        _ => ()
      }
    }
  }
  
  if has_float {
    let int_as_float = min_int.to_double()
    if has_int && int_as_float < min_float {
      AggResult::FloatResult(int_as_float)
    } else {
      AggResult::FloatResult(min_float)
    }
  } else if has_int {
    AggResult::IntResult(min_int)
  } else {
    AggResult::NullResult
  }
}

pub fn UsagiDB::max(self : UsagiDB, start : Int64, end : Int64, col_index : Int) -> AggResult {
  let rows = self.scan(start, end)
  
  let mut max_int : Int64 = -9223372036854775808
  let mut max_float : Double = -1.7976931348623157e308
  let mut has_int = false
  let mut has_float = false
  
  for row in rows {
    if col_index < row.values.length() {
      match row.values[col_index] {
        Value::Int(v) => {
          if v > max_int { max_int = v }
          has_int = true
        }
        Value::Float(v) => {
          if v > max_float { max_float = v }
          has_float = true
        }
        _ => ()
      }
    }
  }
  
  if has_float {
    let int_as_float = max_int.to_double()
    if has_int && int_as_float > max_float {
      AggResult::FloatResult(int_as_float)
    } else {
      AggResult::FloatResult(max_float)
    }
  } else if has_int {
    AggResult::IntResult(max_int)
  } else {
    AggResult::NullResult
  }
}

// ============================================
// Downsample
// ============================================

pub fn UsagiDB::downsample(
  self : UsagiDB,
  start : Int64,
  end : Int64,
  bucket_ms : Int64,
  col_index : Int,
  agg : AggType
) -> Array[(Int64, AggResult)] {
  let result : Array[(Int64, AggResult)] = []
  
  let mut bucket_start = start
  
  while bucket_start < end {
    let bucket_end = bucket_start + bucket_ms - 1
    let actual_end = if bucket_end > end { end } else { bucket_end }
    
    let agg_result = match agg {
      AggType::Sum => self.sum(bucket_start, actual_end, col_index)
      AggType::Count => self.count(bucket_start, actual_end)
      AggType::Avg => self.avg(bucket_start, actual_end, col_index)
      AggType::Min => self.min(bucket_start, actual_end, col_index)
      AggType::Max => self.max(bucket_start, actual_end, col_index)
    }
    
    match agg_result {
      AggResult::NullResult => ()
      _ => result.push((bucket_start, agg_result))
    }
    
    bucket_start = bucket_start + bucket_ms
  }
  
  result
}

pub fn UsagiDB::group_by_time(
  self : UsagiDB,
  start : Int64,
  end : Int64,
  unit : TimeUnit,
  col_index : Int,
  agg : AggType
) -> Array[(Int64, AggResult)] {
  let bucket_ms = unit.to_ms()
  self.downsample(start, end, bucket_ms, col_index, agg)
}

// ============================================
// Serialization - JSON Export
// ============================================

fn escape_json_string(s : String) -> String {
  let mut result = ""
  for i = 0; i < s.length(); i = i + 1 {
    let c = s[i]
    if c == '"' {
      result = result + "\\\""
    } else if c == '\\' {
      result = result + "\\\\"
    } else if c == '\n' {
      result = result + "\\n"
    } else if c == '\r' {
      result = result + "\\r"
    } else if c == '\t' {
      result = result + "\\t"
    } else {
      result = result + c.to_string()
    }
  }
  result
}

fn value_to_json(v : Value) -> String {
  match v {
    Value::Null => "{\"t\":0}"
    Value::Int(n) => "{\"t\":1,\"v\":" + n.to_string() + "}"
    Value::Float(n) => "{\"t\":2,\"v\":" + n.to_string() + "}"
    Value::String(s) => "{\"t\":3,\"v\":\"" + escape_json_string(s) + "\"}"
    Value::Timestamp(n) => "{\"t\":4,\"v\":" + n.to_string() + "}"
  }
}

fn row_to_json(row : Row) -> String {
  let mut values_json = "["
  for i, v in row.values {
    if i > 0 { values_json = values_json + "," }
    values_json = values_json + value_to_json(v)
  }
  values_json = values_json + "]"
  "{\"ts\":" + row.ts.to_string() + ",\"values\":" + values_json + "}"
}

fn int64_array_to_json(arr : Array[Int64]) -> String {
  let mut result = "["
  for i, v in arr {
    if i > 0 { result = result + "," }
    result = result + v.to_string()
  }
  result + "]"
}

fn int_array_to_json(arr : Array[Int]) -> String {
  let mut result = "["
  for i, v in arr {
    if i > 0 { result = result + "," }
    result = result + v.to_string()
  }
  result + "]"
}

fn value_array_to_json(arr : Array[Value]) -> String {
  let mut result = "["
  for i, v in arr {
    if i > 0 { result = result + "," }
    result = result + value_to_json(v)
  }
  result + "]"
}

fn compressed_chunk_to_json(chunk : CompressedChunk) -> String {
  let mut cols_json = "["
  for i, col in chunk.columns {
    if i > 0 { cols_json = cols_json + "," }
    cols_json = cols_json + value_array_to_json(col)
  }
  cols_json = cols_json + "]"
  
  "{\"id\":" + chunk.id.to_string() + 
  ",\"ts_base\":" + chunk.ts_base.to_string() +
  ",\"ts_deltas\":" + int64_array_to_json(chunk.ts_deltas) +
  ",\"columns\":" + cols_json +
  ",\"min_ts\":" + chunk.min_ts.to_string() +
  ",\"max_ts\":" + chunk.max_ts.to_string() + "}"
}

fn chunk_to_json(chunk : Chunk) -> String {
  "{\"id\":" + chunk.id.to_string() + 
  ",\"compressed\":" + compressed_chunk_to_json(chunk.compressed) + "}"
}

fn changelog_entry_to_json(entry : ChangeLogEntry) -> String {
  let op_json = match entry.op {
    Operation::Insert(row) => "{\"type\":\"insert\",\"row\":" + row_to_json(row) + "}"
    Operation::Delete(ts) => "{\"type\":\"delete\",\"ts\":" + ts.to_string() + "}"
  }
  "{\"seq\":" + entry.seq.to_string() + 
  ",\"timestamp\":" + entry.timestamp.to_string() +
  ",\"op\":" + op_json + "}"
}

fn snapshot_to_json(snap : Snapshot) -> String {
  "{\"id\":" + snap.id.to_string() +
  ",\"chunk_ids\":" + int_array_to_json(snap.chunk_ids) +
  ",\"deleted_timestamps\":" + int64_array_to_json(snap.deleted_timestamps) + "}"
}

/// Serialize entire UsagiDB to JSON string
pub fn UsagiDB::serialize(self : UsagiDB) -> String {
  // Delta rows
  let mut delta_rows_json = "["
  for i, row in self.delta.rows {
    if i > 0 { delta_rows_json = delta_rows_json + "," }
    delta_rows_json = delta_rows_json + row_to_json(row)
  }
  delta_rows_json = delta_rows_json + "]"
  
  // Chunks
  let mut chunks_json = "["
  for i, chunk in self.main.chunks {
    if i > 0 { chunks_json = chunks_json + "," }
    chunks_json = chunks_json + chunk_to_json(chunk)
  }
  chunks_json = chunks_json + "]"
  
  // Deleted timestamps
  let deleted_json = int64_array_to_json(self.deleted.timestamps)
  
  // Snapshots
  let mut snapshots_json = "["
  for i, snap in self.snapshots {
    if i > 0 { snapshots_json = snapshots_json + "," }
    snapshots_json = snapshots_json + snapshot_to_json(snap)
  }
  snapshots_json = snapshots_json + "]"
  
  // Changelog
  let mut changelog_json = "["
  for i, entry in self.changelog.entries {
    if i > 0 { changelog_json = changelog_json + "," }
    changelog_json = changelog_json + changelog_entry_to_json(entry)
  }
  changelog_json = changelog_json + "]"
  
  // Complete JSON
  "{\"version\":1" +
  ",\"delta_rows\":" + delta_rows_json +
  ",\"delta_next_id\":" + self.delta.next_id.to_string() +
  ",\"chunks\":" + chunks_json +
  ",\"next_chunk_id\":" + self.main.next_chunk_id.to_string() +
  ",\"deleted\":" + deleted_json +
  ",\"snapshots\":" + snapshots_json +
  ",\"next_snapshot_id\":" + self.next_snapshot_id.to_string() +
  ",\"changelog\":" + changelog_json +
  ",\"next_seq\":" + self.changelog.next_seq.to_string() +
  ",\"compact_threshold\":" + self.compact_threshold.to_string() +
  ",\"sync_enabled\":" + self.sync_enabled.to_string() + "}"
}

// ============================================
// JSON Parser
// ============================================

enum JsonValue {
  JsonNull
  JsonBool(Bool)
  JsonNumber(Double)
  JsonString(String)
  JsonArray(Array[JsonValue])
  JsonObject(Array[(String, JsonValue)])
}

struct JsonParser {
  input : String
  mut pos : Int
}

fn JsonParser::new(input : String) -> JsonParser {
  { input: input, pos: 0 }
}

fn JsonParser::skip_whitespace(self : JsonParser) -> Unit {
  while self.pos < self.input.length() {
    let c = self.input[self.pos]
    if c == ' ' || c == '\n' || c == '\r' || c == '\t' {
      self.pos = self.pos + 1
    } else {
      break
    }
  }
}

fn JsonParser::peek_char(self : JsonParser) -> Char {
  if self.pos < self.input.length() {
    self.input[self.pos].to_int().unsafe_to_char()
  } else {
    '\u0000'
  }
}

fn JsonParser::consume_char(self : JsonParser) -> Char {
  let c = self.peek_char()
  self.pos = self.pos + 1
  c
}

fn JsonParser::expect_char(self : JsonParser, expected : Char) -> Bool {
  self.skip_whitespace()
  if self.peek_char() == expected {
    self.pos = self.pos + 1
    true
  } else {
    false
  }
}

fn JsonParser::parse_string(self : JsonParser) -> String? {
  self.skip_whitespace()
  if self.peek_char() != '"' {
    return None
  }
  self.pos = self.pos + 1
  
  let mut result = ""
  while self.pos < self.input.length() {
    let c = self.consume_char()
    if c == '"' {
      return Some(result)
    } else if c == '\\' {
      let escaped = self.consume_char()
      if escaped == 'n' {
        result = result + "\n"
      } else if escaped == 'r' {
        result = result + "\r"
      } else if escaped == 't' {
        result = result + "\t"
      } else if escaped == '"' {
        result = result + "\""
      } else if escaped == '\\' {
        result = result + "\\"
      } else {
        result = result + escaped.to_string()
      }
    } else {
      result = result + c.to_string()
    }
  }
  None
}

fn JsonParser::parse_number(self : JsonParser) -> Double? {
  self.skip_whitespace()
  let start = self.pos
  
  if self.peek_char() == '-' {
    self.pos = self.pos + 1
  }
  
  while self.pos < self.input.length() {
    let c = self.peek_char()
    if c >= '0' && c <= '9' {
      self.pos = self.pos + 1
    } else {
      break
    }
  }
  
  if self.peek_char() == '.' {
    self.pos = self.pos + 1
    while self.pos < self.input.length() {
      let c = self.peek_char()
      if c >= '0' && c <= '9' {
        self.pos = self.pos + 1
      } else {
        break
      }
    }
  }
  
  if self.peek_char() == 'e' || self.peek_char() == 'E' {
    self.pos = self.pos + 1
    if self.peek_char() == '+' || self.peek_char() == '-' {
      self.pos = self.pos + 1
    }
    while self.pos < self.input.length() {
      let c = self.peek_char()
      if c >= '0' && c <= '9' {
        self.pos = self.pos + 1
      } else {
        break
      }
    }
  }
  
  if self.pos > start {
    let num_str = substring_manual(self.input, start, self.pos)
    Some(parse_double(num_str))
  } else {
    None
  }
}

fn substring_manual(s : String, start : Int, end : Int) -> String {
  let mut result = ""
  for i = start; i < end && i < s.length(); i = i + 1 {
    result = result + s[i].to_int().unsafe_to_char().to_string()
  }
  result
}

fn parse_double(s : String) -> Double {
  let mut result = 0.0
  let mut decimal_place = 0.0
  let mut is_negative = false
  let mut i = 0
  
  if i < s.length() && s[i] == '-' {
    is_negative = true
    i = i + 1
  }
  
  while i < s.length() {
    let c = s[i].to_int().unsafe_to_char()
    if c >= '0' && c <= '9' {
      result = result * 10.0 + (c.to_int() - '0'.to_int()).to_double()
      i = i + 1
    } else if c == '.' {
      i = i + 1
      decimal_place = 0.1
      break
    } else {
      break
    }
  }
  
  while i < s.length() && decimal_place > 0.0 {
    let c = s[i].to_int().unsafe_to_char()
    if c >= '0' && c <= '9' {
      result = result + (c.to_int() - '0'.to_int()).to_double() * decimal_place
      decimal_place = decimal_place * 0.1
      i = i + 1
    } else {
      break
    }
  }
  
  if is_negative { -result } else { result }
}

fn JsonParser::check_keyword(self : JsonParser, keyword : String) -> Bool {
  let len = keyword.length()
  if self.pos + len > self.input.length() {
    return false
  }
  for i = 0; i < len; i = i + 1 {
    if self.input[self.pos + i] != keyword[i] {
      return false
    }
  }
  self.pos = self.pos + len
  true
}

fn JsonParser::parse_value(self : JsonParser) -> JsonValue? {
  self.skip_whitespace()
  let c = self.peek_char()
  
  if c == '"' {
    match self.parse_string() {
      Some(s) => Some(JsonValue::JsonString(s))
      None => None
    }
  } else if c == '-' || (c >= '0' && c <= '9') {
    match self.parse_number() {
      Some(n) => Some(JsonValue::JsonNumber(n))
      None => None
    }
  } else if c == '{' {
    self.parse_object()
  } else if c == '[' {
    self.parse_array()
  } else if c == 't' {
    if self.check_keyword("true") {
      Some(JsonValue::JsonBool(true))
    } else {
      None
    }
  } else if c == 'f' {
    if self.check_keyword("false") {
      Some(JsonValue::JsonBool(false))
    } else {
      None
    }
  } else if c == 'n' {
    if self.check_keyword("null") {
      Some(JsonValue::JsonNull)
    } else {
      None
    }
  } else {
    None
  }
}

fn JsonParser::parse_array(self : JsonParser) -> JsonValue? {
  if not(self.expect_char('[')) {
    return None
  }
  
  let arr : Array[JsonValue] = []
  self.skip_whitespace()
  
  if self.peek_char() == ']' {
    self.pos = self.pos + 1
    return Some(JsonValue::JsonArray(arr))
  }
  
  while true {
    match self.parse_value() {
      Some(v) => arr.push(v)
      None => return None
    }
    
    self.skip_whitespace()
    if self.peek_char() == ',' {
      self.pos = self.pos + 1
    } else if self.peek_char() == ']' {
      self.pos = self.pos + 1
      break
    } else {
      return None
    }
  }
  
  Some(JsonValue::JsonArray(arr))
}

fn JsonParser::parse_object(self : JsonParser) -> JsonValue? {
  if not(self.expect_char('{')) {
    return None
  }
  
  let obj : Array[(String, JsonValue)] = []
  self.skip_whitespace()
  
  if self.peek_char() == '}' {
    self.pos = self.pos + 1
    return Some(JsonValue::JsonObject(obj))
  }
  
  while true {
    let key = match self.parse_string() {
      Some(s) => s
      None => return None
    }
    
    if not(self.expect_char(':')) {
      return None
    }
    
    let value = match self.parse_value() {
      Some(v) => v
      None => return None
    }
    
    obj.push((key, value))
    
    self.skip_whitespace()
    if self.peek_char() == ',' {
      self.pos = self.pos + 1
    } else if self.peek_char() == '}' {
      self.pos = self.pos + 1
      break
    } else {
      return None
    }
  }
  
  Some(JsonValue::JsonObject(obj))
}

fn parse_json(input : String) -> JsonValue? {
  let parser = JsonParser::new(input)
  parser.parse_value()
}

// ============================================
// JsonValue Helpers
// ============================================

fn JsonValue::get(self : JsonValue, key : String) -> JsonValue? {
  match self {
    JsonObject(pairs) => {
      for pair in pairs {
        if pair.0 == key {
          return Some(pair.1)
        }
      }
      None
    }
    _ => None
  }
}

fn JsonValue::as_array(self : JsonValue) -> Array[JsonValue]? {
  match self {
    JsonArray(arr) => Some(arr)
    _ => None
  }
}

fn JsonValue::as_number(self : JsonValue) -> Double? {
  match self {
    JsonNumber(n) => Some(n)
    _ => None
  }
}

fn JsonValue::as_string(self : JsonValue) -> String? {
  match self {
    JsonString(s) => Some(s)
    _ => None
  }
}

fn JsonValue::as_bool(self : JsonValue) -> Bool? {
  match self {
    JsonBool(b) => Some(b)
    _ => None
  }
}

fn JsonValue::as_int(self : JsonValue) -> Int? {
  match self {
    JsonNumber(n) => Some(n.to_int())
    _ => None
  }
}

fn JsonValue::as_int64(self : JsonValue) -> Int64? {
  match self {
    JsonNumber(n) => Some(n.to_int64())
    _ => None
  }
}

// ============================================
// Deserialization Helper Functions
// ============================================

fn get_int(json : JsonValue, key : String) -> Int? {
  match json.get(key) {
    Some(v) => v.as_int()
    None => None
  }
}

fn get_int64(json : JsonValue, key : String) -> Int64? {
  match json.get(key) {
    Some(v) => v.as_int64()
    None => None
  }
}

fn get_string(json : JsonValue, key : String) -> String? {
  match json.get(key) {
    Some(v) => v.as_string()
    None => None
  }
}

fn get_bool(json : JsonValue, key : String) -> Bool? {
  match json.get(key) {
    Some(v) => v.as_bool()
    None => None
  }
}

fn get_array(json : JsonValue, key : String) -> Array[JsonValue]? {
  match json.get(key) {
    Some(v) => v.as_array()
    None => None
  }
}

// ============================================
// Deserialization
// ============================================

fn restore_value_from_json(json : JsonValue) -> Value? {
  let t = match get_int(json, "t") {
    Some(i) => i
    None => return None
  }
  
  if t == 0 {
    return Some(Value::Null)
  }
  
  let v = match json.get("v") {
    Some(val) => val
    None => return None
  }
  
  if t == 1 {
    match v.as_int64() {
      Some(n) => Some(Value::Int(n))
      None => None
    }
  } else if t == 2 {
    match v.as_number() {
      Some(n) => Some(Value::Float(n))
      None => None
    }
  } else if t == 3 {
    match v.as_string() {
      Some(s) => Some(Value::String(s))
      None => None
    }
  } else if t == 4 {
    match v.as_int64() {
      Some(n) => Some(Value::Timestamp(n))
      None => None
    }
  } else {
    None
  }
}

fn restore_row_from_json(json : JsonValue) -> Row? {
  let ts = match get_int64(json, "ts") {
    Some(n) => n
    None => return None
  }
  
  let values_json = match get_array(json, "values") {
    Some(arr) => arr
    None => return None
  }
  
  let values : Array[Value] = []
  for vj in values_json {
    match restore_value_from_json(vj) {
      Some(v) => values.push(v)
      None => return None
    }
  }
  
  Some({ ts: ts, values: values })
}

fn restore_int64_array_from_json(json : JsonValue) -> Array[Int64]? {
  match json.as_array() {
    Some(arr) => {
      let result : Array[Int64] = []
      for item in arr {
        match item.as_int64() {
          Some(n) => result.push(n)
          None => return None
        }
      }
      Some(result)
    }
    None => None
  }
}

fn restore_int_array_from_json(json : JsonValue) -> Array[Int]? {
  match json.as_array() {
    Some(arr) => {
      let result : Array[Int] = []
      for item in arr {
        match item.as_int() {
          Some(n) => result.push(n)
          None => return None
        }
      }
      Some(result)
    }
    None => None
  }
}

fn restore_value_array_from_json(json : JsonValue) -> Array[Value]? {
  match json.as_array() {
    Some(arr) => {
      let result : Array[Value] = []
      for item in arr {
        match restore_value_from_json(item) {
          Some(v) => result.push(v)
          None => return None
        }
      }
      Some(result)
    }
    None => None
  }
}

fn restore_compressed_chunk_from_json(json : JsonValue) -> CompressedChunk? {
  let id = match get_int(json, "id") {
    Some(n) => n
    None => return None
  }
  
  let ts_base = match get_int64(json, "ts_base") {
    Some(n) => n
    None => return None
  }
  
  let ts_deltas_json = match json.get("ts_deltas") {
    Some(v) => v
    None => return None
  }
  let ts_deltas = match restore_int64_array_from_json(ts_deltas_json) {
    Some(arr) => arr
    None => return None
  }
  
  let columns_json = match get_array(json, "columns") {
    Some(arr) => arr
    None => return None
  }
  
  let columns : Array[Array[Value]] = []
  for col_json in columns_json {
    match restore_value_array_from_json(col_json) {
      Some(col) => columns.push(col)
      None => return None
    }
  }
  
  let min_ts = match get_int64(json, "min_ts") {
    Some(n) => n
    None => return None
  }
  
  let max_ts = match get_int64(json, "max_ts") {
    Some(n) => n
    None => return None
  }
  
  Some({
    id: id,
    ts_base: ts_base,
    ts_deltas: ts_deltas,
    columns: columns,
    min_ts: min_ts,
    max_ts: max_ts
  })
}

fn restore_chunk_from_json(json : JsonValue) -> Chunk? {
  let id = match get_int(json, "id") {
    Some(n) => n
    None => return None
  }
  
  let compressed_json = match json.get("compressed") {
    Some(v) => v
    None => return None
  }
  let compressed = match restore_compressed_chunk_from_json(compressed_json) {
    Some(c) => c
    None => return None
  }
  
  Some({ id: id, compressed: compressed })
}

fn restore_snapshot_from_json(json : JsonValue) -> Snapshot? {
  let id = match get_int(json, "id") {
    Some(n) => n
    None => return None
  }
  
  let chunk_ids_json = match json.get("chunk_ids") {
    Some(v) => v
    None => return None
  }
  let chunk_ids = match restore_int_array_from_json(chunk_ids_json) {
    Some(arr) => arr
    None => return None
  }
  
  let deleted_json = match json.get("deleted_timestamps") {
    Some(v) => v
    None => return None
  }
  let deleted_timestamps = match restore_int64_array_from_json(deleted_json) {
    Some(arr) => arr
    None => return None
  }
  
  Some({ id: id, chunk_ids: chunk_ids, deleted_timestamps: deleted_timestamps })
}

fn restore_changelog_entry_from_json(json : JsonValue) -> ChangeLogEntry? {
  let seq = match get_int64(json, "seq") {
    Some(n) => n
    None => return None
  }
  
  let timestamp = match get_int64(json, "timestamp") {
    Some(n) => n
    None => return None
  }
  
  let op_json = match json.get("op") {
    Some(v) => v
    None => return None
  }
  
  let op_type = match get_string(op_json, "type") {
    Some(s) => s
    None => return None
  }
  
  let op = if op_type == "insert" {
    let row_json = match op_json.get("row") {
      Some(v) => v
      None => return None
    }
    let row = match restore_row_from_json(row_json) {
      Some(r) => r
      None => return None
    }
    Operation::Insert(row)
  } else if op_type == "delete" {
    let ts = match get_int64(op_json, "ts") {
      Some(n) => n
      None => return None
    }
    Operation::Delete(ts)
  } else {
    return None
  }
  
  Some({ seq: seq, timestamp: timestamp, op: op })
}

/// Deserialize UsagiDB from JSON string (full state restore)
pub fn UsagiDB::deserialize(json_str : String) -> UsagiDB? {
  let json = match parse_json(json_str) {
    Some(j) => j
    None => return None
  }
  
  let compact_threshold = match get_int(json, "compact_threshold") {
    Some(n) => n
    None => 100
  }
  
  let sync_enabled = match get_bool(json, "sync_enabled") {
    Some(b) => b
    None => true
  }
  
  let db = UsagiDB::with_threshold(compact_threshold)
  db.sync_enabled = sync_enabled
  
  // Restore delta rows
  match get_array(json, "delta_rows") {
    Some(arr) => {
      for row_json in arr {
        match restore_row_from_json(row_json) {
          Some(row) => db.delta.rows.push(row)
          None => ()
        }
      }
    }
    None => ()
  }
  
  // Restore delta next_id
  match get_int(json, "delta_next_id") {
    Some(n) => db.delta.next_id = n
    None => ()
  }
  
  // Restore chunks
  match get_array(json, "chunks") {
    Some(arr) => {
      for chunk_json in arr {
        match restore_chunk_from_json(chunk_json) {
          Some(chunk) => db.main.chunks.push(chunk)
          None => ()
        }
      }
    }
    None => ()
  }
  
  // Restore next_chunk_id
  match get_int(json, "next_chunk_id") {
    Some(n) => db.main.next_chunk_id = n
    None => ()
  }
  
  // Restore deleted timestamps
  match json.get("deleted") {
    Some(v) => {
      match restore_int64_array_from_json(v) {
        Some(arr) => {
          for ts in arr {
            db.deleted.timestamps.push(ts)
          }
        }
        None => ()
      }
    }
    None => ()
  }
  
  // Restore snapshots
  match get_array(json, "snapshots") {
    Some(arr) => {
      for snap_json in arr {
        match restore_snapshot_from_json(snap_json) {
          Some(snap) => db.snapshots.push(snap)
          None => ()
        }
      }
    }
    None => ()
  }
  
  // Restore next_snapshot_id
  match get_int(json, "next_snapshot_id") {
    Some(n) => db.next_snapshot_id = n
    None => ()
  }
  
  // Restore changelog
  match get_array(json, "changelog") {
    Some(arr) => {
      for entry_json in arr {
        match restore_changelog_entry_from_json(entry_json) {
          Some(entry) => db.changelog.entries.push(entry)
          None => ()
        }
      }
    }
    None => ()
  }
  
  // Restore next_seq
  match get_int64(json, "next_seq") {
    Some(n) => db.changelog.next_seq = n
    None => ()
  }
  
  Some(db)
}

// ============================================
// JS FFI Helper Functions
// ============================================

pub fn create_db_default() -> UsagiDB {
  UsagiDB::with_threshold(100)
}

pub fn create_db_with_threshold(threshold : Int) -> UsagiDB {
  UsagiDB::with_threshold(threshold)
}

pub fn value_float(v : Double) -> Value {
  Value::Float(v)
}

pub fn value_string(s : String) -> Value {
  Value::String(s)
}

pub fn value_int(v : Int64) -> Value {
  Value::Int(v)
}

// ============================================
// Main / Init
// ============================================

extern "js" fn js_log(msg : String) -> Unit =
  #|(msg) => console.log(msg)

fn main {
  let db = UsagiDB::with_threshold(5)
  
  println("🐰 UsagiDB Demo (with Serialization)")
  println("=====================================")
  
  // Insert sensor data
  for i = 0; i < 12; i = i + 1 {
    let ts = (i * 1000).to_int64()
    let temp = 20.0 + i.to_double() * 0.5
    let sensor = if i % 2 == 0 { "sensor-1" } else { "sensor-2" }
    let _ = db.insert(ts, [Value::Float(temp), Value::String(sensor)])
  }
  
  println(db.stats())
  
  // Serialize
  println("\n--- Serialization Demo ---")
  let json = db.serialize()
  println("Serialized JSON length: " + json.length().to_string() + " bytes")
  
  // Deserialize
  println("\n--- Deserialization Demo ---")
  match UsagiDB::deserialize(json) {
    Some(db2) => {
      println("Deserialized successfully!")
      println(db2.stats())
      
      // Verify data integrity
      let original_rows = db.scan(0L, 100000L)
      let restored_rows = db2.scan(0L, 100000L)
      println("Original rows: " + original_rows.length().to_string())
      println("Restored rows: " + restored_rows.length().to_string())
    }
    None => println("Deserialization failed!")
  }
}

fn init {
  js_log("🐰 UsagiDB with Serialization loaded")
}

// ============================================
// JS FFI Exports (ブラウザから呼び出し用)
// ============================================

// グローバル変数としてDBインスタンスを保持
let global_db : Ref[UsagiDB?] = { val: None }

pub fn js_create_db(threshold : Int) -> Unit {
  global_db.val = Some(UsagiDB::with_threshold(threshold))
  js_log("DB created with threshold: " + threshold.to_string())
}

pub fn js_insert(ts : Int, val : Double, sensor : String) -> Unit {
  match global_db.val {
    Some(db) => {
      let _ = db.insert(ts.to_int64(), [Value::Float(val), Value::String(sensor)])
    }
    None => js_log("DB not initialized")
  }
}

pub fn js_scan_all() -> String {
  match global_db.val {
    Some(db) => {
      let rows = db.scan(0L, 9999999999999L)
      // JSON形式で返す
      rows.length().to_string() + " rows"
    }
    None => "DB not initialized"
  }
}

pub fn js_stats() -> String {
  match global_db.val {
    Some(db) => db.stats()
    None => "DB not initialized"
  }
}

pub fn js_serialize() -> String {
  match global_db.val {
    Some(db) => db.serialize()
    None => "{}"
  }
}