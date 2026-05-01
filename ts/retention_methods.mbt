// Retention API on TimeSeriesStore. Mirrors v0.2 semantics: enable, disable,
// and `apply_retention(now)` deletes rows whose timestamp is older than
// `now - duration_ms` from both delta and main stores.

///|
pub fn TimeSeriesStore::set_retention(
  self : TimeSeriesStore,
  unit : @core.TimeUnit,
  count : Int,
) -> Unit {
  self.retention.enabled = true
  self.retention.duration_ms = unit.to_ms() * count.to_int64()
}

///|
pub fn TimeSeriesStore::disable_retention(self : TimeSeriesStore) -> Unit {
  self.retention.enabled = false
}

///| Drop rows older than `current_time - duration_ms`. Returns the number of
/// rows that were dropped (delta + chunk).
pub fn TimeSeriesStore::apply_retention(
  self : TimeSeriesStore,
  current_time : Int64,
) -> Int {
  if not(self.retention.enabled) {
    return 0
  }
  let cutoff = current_time - self.retention.duration_ms
  let mut deleted_count = 0
  let new_rows : Array[@core.Row] = []
  for row in self.delta.rows {
    if row.ts >= cutoff {
      new_rows.push(row)
    } else {
      deleted_count = deleted_count + 1
    }
  }
  self.delta.rows = new_rows
  let new_chunks : Array[Chunk] = []
  for chunk in self.main.chunks {
    if chunk.max_ts() >= cutoff {
      new_chunks.push(chunk)
    } else {
      deleted_count = deleted_count + chunk.row_count()
    }
  }
  self.main.chunks = new_chunks
  self.retention.last_applied = current_time
  deleted_count
}

///|
pub fn TimeSeriesStore::retention_info(self : TimeSeriesStore) -> String {
  if self.retention.enabled {
    "Retention: " + self.retention.duration_ms.to_string() + "ms"
  } else {
    "Retention: disabled"
  }
}
