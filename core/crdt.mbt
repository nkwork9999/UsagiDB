// CRDT primitives — Lamport clocks, vector clocks, last-write-wins values,
// CRDT rows. Cross-cutting: any storage mode can use these for distributed
// sync without depending on the storage layer.

// ============================================

pub(all) struct LamportClock {
  mut counter : Int64
  site_id : String
}

pub fn LamportClock::new(site_id : String) -> LamportClock {
  { counter: 0L, site_id }
}

pub fn LamportClock::tick(self : LamportClock) -> Int64 {
  self.counter = self.counter + 1L
  self.counter
}

pub fn LamportClock::update(self : LamportClock, remote : Int64) -> Unit {
  if remote > self.counter { self.counter = remote }
}

pub(all) struct LWWValue {
  value : Value
  timestamp : Int64
  site_id : String
} derive(Show)

///| Conflict resolution policy applied during merge. Default is LWW.
///   * `LastWriteWins` — newer timestamp wins; tie broken by site_id ordering.
///   * `FirstWriteWins` — oldest timestamp wins; effectively make values immutable.
///   * `MaxValue`/`MinValue` — pick the larger/smaller numeric value (Int/Float).
///                             Falls through to LWW for non-numeric.
///   * `PreferSite(id)` — always pick the value from `id` if present.
pub(all) enum ConflictResolver {
  LastWriteWins
  FirstWriteWins
  MaxValue
  MinValue
  PreferSite(String)
} derive(Show, Eq)

pub fn LWWValue::merge(self : LWWValue, other : LWWValue) -> LWWValue {
  self.merge_with(other, LastWriteWins)
}

///|
pub fn LWWValue::merge_with(
  self : LWWValue,
  other : LWWValue,
  policy : ConflictResolver,
) -> LWWValue {
  match policy {
    LastWriteWins =>
      if other.timestamp > self.timestamp {
        other
      } else if other.timestamp == self.timestamp &&
        other.site_id > self.site_id {
        other
      } else {
        self
      }
    FirstWriteWins =>
      if other.timestamp < self.timestamp {
        other
      } else if other.timestamp == self.timestamp &&
        other.site_id < self.site_id {
        other
      } else {
        self
      }
    MaxValue =>
      match (self.value, other.value) {
        (Int(a), Int(b)) => if b > a { other } else { self }
        (Float(a), Float(b)) => if b > a { other } else { self }
        (Int(a), Float(b)) =>
          if b > a.to_double() {
            other
          } else {
            self
          }
        (Float(a), Int(b)) =>
          if b.to_double() > a {
            other
          } else {
            self
          }
        // non-numeric → fall back to LWW
        _ => self.merge_with(other, LastWriteWins)
      }
    MinValue =>
      match (self.value, other.value) {
        (Int(a), Int(b)) => if b < a { other } else { self }
        (Float(a), Float(b)) => if b < a { other } else { self }
        (Int(a), Float(b)) =>
          if b < a.to_double() {
            other
          } else {
            self
          }
        (Float(a), Int(b)) =>
          if b.to_double() < a {
            other
          } else {
            self
          }
        _ => self.merge_with(other, LastWriteWins)
      }
    PreferSite(id) =>
      if other.site_id == id {
        other
      } else if self.site_id == id {
        self
      } else {
        self.merge_with(other, LastWriteWins)
      }
  }
}

pub(all) struct CRDTRow {
  ts : Int64
  columns : Array[LWWValue]
  mut deleted : Bool
  mut delete_timestamp : Int64
} derive(Show)

pub fn CRDTRow::new(ts : Int64, values : Array[Value], clock : Int64, site_id : String) -> CRDTRow {
  let columns : Array[LWWValue] = []
  for v in values {
    columns.push({ value: v, timestamp: clock, site_id })
  }
  { ts, columns, deleted: false, delete_timestamp: 0L }
}

pub fn CRDTRow::to_row(self : CRDTRow) -> Row {
  let values : Array[Value] = []
  for col in self.columns { values.push(col.value) }
  { ts: self.ts, values }
}

pub fn CRDTRow::merge(self : CRDTRow, other : CRDTRow) -> CRDTRow {
  self.merge_with(other, LastWriteWins)
}

///|
pub fn CRDTRow::merge_with(
  self : CRDTRow,
  other : CRDTRow,
  policy : ConflictResolver,
) -> CRDTRow {
  let merged_cols : Array[LWWValue] = []
  let max_len = if self.columns.length() > other.columns.length() {
    self.columns.length()
  } else {
    other.columns.length()
  }
  for i = 0; i < max_len; i = i + 1 {
    if i < self.columns.length() && i < other.columns.length() {
      merged_cols.push(self.columns[i].merge_with(other.columns[i], policy))
    } else if i < self.columns.length() {
      merged_cols.push(self.columns[i])
    } else {
      merged_cols.push(other.columns[i])
    }
  }
  let (deleted, delete_ts) = if other.delete_timestamp > self.delete_timestamp {
    (other.deleted, other.delete_timestamp)
  } else {
    (self.deleted, self.delete_timestamp)
  }
  { ts: self.ts, columns: merged_cols, deleted, delete_timestamp: delete_ts }
}

// ============================================

pub(all) struct VectorClock {
  clocks : Array[(String, Int64)]
}

pub fn VectorClock::new() -> VectorClock {
  { clocks: [] }
}

pub fn VectorClock::get(self : VectorClock, site_id : String) -> Int64 {
  for pair in self.clocks {
    if pair.0 == site_id { return pair.1 }
  }
  0L
}

pub fn VectorClock::increment(self : VectorClock, site_id : String) -> Unit {
  for i = 0; i < self.clocks.length(); i = i + 1 {
    if self.clocks[i].0 == site_id {
      self.clocks[i] = (site_id, self.clocks[i].1 + 1L)
      return
    }
  }
  self.clocks.push((site_id, 1L))
}

pub fn VectorClock::update(self : VectorClock, other : VectorClock) -> Unit {
  for pair in other.clocks {
    let current = self.get(pair.0)
    if pair.1 > current {
      let mut found = false
      for i = 0; i < self.clocks.length(); i = i + 1 {
        if self.clocks[i].0 == pair.0 {
          self.clocks[i] = (pair.0, pair.1)
          found = true
          break
        }
      }
      if not(found) { self.clocks.push(pair) }
    }
  }
}

pub fn VectorClock::to_string(self : VectorClock) -> String {
  let mut result = "{"
  for i, pair in self.clocks {
    if i > 0 { result = result + "," }
    result = result + pair.0 + ":" + pair.1.to_string()
  }
  result + "}"
}

