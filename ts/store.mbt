// ============================================
// TimeSeriesStore (Main Database)
// ============================================

pub struct TimeSeriesStore {
  delta : DeltaStore
  main : MainStore
  deleted : DeleteSet
  snapshots : Array[Snapshot]
  mut next_snapshot_id : Int
  compact_threshold : Int
  changelog : @core.ChangeLog
  mut sync_enabled : Bool
  // v0.2 additions
  retention : RetentionPolicy
  aggregates : Array[ContinuousAggregate]
  // v0.2 CRDT — opt-in: stays inert until enable_crdt() is called.
  mut site_id : String
  clock : @core.LamportClock
  vector_clock : @core.VectorClock
  crdt_rows : Array[@core.CRDTRow]
  mut crdt_enabled : Bool
}

pub fn TimeSeriesStore::new() -> TimeSeriesStore {
  TimeSeriesStore::with_config(100, "default")
}

pub fn TimeSeriesStore::with_threshold(threshold : Int) -> TimeSeriesStore {
  TimeSeriesStore::with_config(threshold, "default")
}

pub fn TimeSeriesStore::with_config(
  threshold : Int,
  site_id : String,
) -> TimeSeriesStore {
  {
    delta: DeltaStore::new(),
    main: MainStore::new(),
    deleted: DeleteSet::new(),
    snapshots: [],
    next_snapshot_id: 0,
    compact_threshold: threshold,
    changelog: @core.ChangeLog::new(),
    sync_enabled: true,
    retention: RetentionPolicy::new(),
    aggregates: [],
    site_id,
    clock: @core.LamportClock::new(site_id),
    vector_clock: @core.VectorClock::new(),
    crdt_rows: [],
    crdt_enabled: false,
  }
}

pub fn TimeSeriesStore::enable_crdt(self : TimeSeriesStore) -> Unit {
  self.crdt_enabled = true
}

pub fn TimeSeriesStore::set_site_id(
  self : TimeSeriesStore,
  site_id : String,
) -> Unit {
  self.site_id = site_id
}

pub fn TimeSeriesStore::get_site_id(self : TimeSeriesStore) -> String {
  self.site_id
}

pub fn TimeSeriesStore::get_vector_clock(self : TimeSeriesStore) -> String {
  self.vector_clock.to_string()
}

pub fn TimeSeriesStore::set_sync_enabled(self : TimeSeriesStore, enabled : Bool) -> Unit {
  self.sync_enabled = enabled
}

pub fn TimeSeriesStore::insert(self : TimeSeriesStore, ts : Int64, values : Array[@core.Value]) -> Int {
  let row : @core.Row = { ts, values }
  let id = self.delta.insert(row)
  if self.sync_enabled {
    let row_copy : @core.Row = { ts, values }
    let _ = self.changelog.append(@core.Operation::Insert(row_copy), ts)
  }
  if self.crdt_enabled {
    let clock_val = self.clock.tick()
    self.vector_clock.increment(self.site_id)
    let crdt_row = @core.CRDTRow::new(ts, values, clock_val, self.site_id)
    self.crdt_rows.push(crdt_row)
  }
  if self.delta.len() >= self.compact_threshold {
    let _ = self.compact()
  }
  id
}

pub fn TimeSeriesStore::delete(self : TimeSeriesStore, ts : Int64) -> Bool {
  self.deleted.add(ts)
  if self.sync_enabled {
    let _ = self.changelog.append(@core.Operation::Delete(ts), ts)
  }
  if self.crdt_enabled {
    let _ = self.clock.tick()
    self.vector_clock.increment(self.site_id)
  }
  
  true
}

pub fn TimeSeriesStore::is_deleted(self : TimeSeriesStore, ts : Int64) -> Bool {
  self.deleted.contains(ts)
}

pub fn TimeSeriesStore::deleted_count(self : TimeSeriesStore) -> Int {
  self.deleted.count()
}

pub fn TimeSeriesStore::compact(self : TimeSeriesStore) -> Int? {
  let all_rows = self.delta.clear()
  if all_rows.length() == 0 {
    return None
  }
  
  let rows : Array[@core.Row] = []
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

pub fn TimeSeriesStore::scan(self : TimeSeriesStore, start : Int64, end : Int64) -> Array[@core.Row] {
  let result : Array[@core.Row] = []
  
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

pub fn TimeSeriesStore::scan_where(self : TimeSeriesStore, start : Int64, end : Int64, filter : @core.Filter) -> Array[@core.Row] {
  let all_rows = self.scan(start, end)
  let result : Array[@core.Row] = []
  
  for row in all_rows {
    if filter.matches(row) {
      result.push(row)
    }
  }
  
  result
}

pub fn TimeSeriesStore::scan_as_of(self : TimeSeriesStore, snapshot_id : Int, start : Int64, end : Int64) -> Array[@core.Row]? {
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
      let result : Array[@core.Row] = []
      
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

pub fn TimeSeriesStore::list_snapshots(self : TimeSeriesStore) -> Array[Int] {
  let result : Array[Int] = []
  for snap in self.snapshots {
    result.push(snap.id)
  }
  result
}

pub fn TimeSeriesStore::snapshot_info(self : TimeSeriesStore, snapshot_id : Int) -> String? {
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

pub fn TimeSeriesStore::stats(self : TimeSeriesStore) -> String {
  let delta_rows = self.delta.len()
  let main_rows = self.main.total_rows()
  let deleted = self.deleted.count()
  let chunks = self.main.chunks.length()
  let snapshots = self.snapshots.length()
  
  "TimeSeriesStore Stats:\n" +
  "  Delta rows: " + delta_rows.to_string() + "\n" +
  "  Main rows: " + main_rows.to_string() + "\n" +
  "  Deleted: " + deleted.to_string() + "\n" +
  "  Visible rows: " + (delta_rows + main_rows - deleted).to_string() + "\n" +
  "  Chunks: " + chunks.to_string() + "\n" +
  "  Snapshots: " + snapshots.to_string() + "\n" +
  "  Changelog entries: " + self.changelog.len().to_string()
}

pub fn TimeSeriesStore::compression_stats(self : TimeSeriesStore) -> String {
  let mut result = "Compression Stats:\n"
  for chunk in self.main.chunks {
    result = result + chunk.compression_stats() + "\n"
  }
  result
}

