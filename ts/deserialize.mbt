// ============================================
// Deserialization Helper Functions
// ============================================

fn get_int(json : @core.JsonValue, key : String) -> Int? {
  match json.get(key) {
    Some(v) => v.as_int()
    None => None
  }
}

fn get_int64(json : @core.JsonValue, key : String) -> Int64? {
  match json.get(key) {
    Some(v) => v.as_int64()
    None => None
  }
}

fn get_string(json : @core.JsonValue, key : String) -> String? {
  match json.get(key) {
    Some(v) => v.as_string()
    None => None
  }
}

fn get_bool(json : @core.JsonValue, key : String) -> Bool? {
  match json.get(key) {
    Some(v) => v.as_bool()
    None => None
  }
}

fn get_array(json : @core.JsonValue, key : String) -> Array[@core.JsonValue]? {
  match json.get(key) {
    Some(v) => v.as_array()
    None => None
  }
}

// ============================================
// Deserialization
// ============================================

fn restore_value_from_json(json : @core.JsonValue) -> @core.Value? {
  let t = match get_int(json, "t") {
    Some(i) => i
    None => return None
  }
  
  if t == 0 {
    return Some(@core.Value::Null)
  }
  
  let v = match json.get("v") {
    Some(val) => val
    None => return None
  }
  
  if t == 1 {
    match v.as_int64() {
      Some(n) => Some(@core.Value::Int(n))
      None => None
    }
  } else if t == 2 {
    match v.as_number() {
      Some(n) => Some(@core.Value::Float(n))
      None => None
    }
  } else if t == 3 {
    match v.as_string() {
      Some(s) => Some(@core.Value::String(s))
      None => None
    }
  } else if t == 4 {
    match v.as_int64() {
      Some(n) => Some(@core.Value::Timestamp(n))
      None => None
    }
  } else {
    None
  }
}

fn restore_row_from_json(json : @core.JsonValue) -> @core.Row? {
  let ts = match get_int64(json, "ts") {
    Some(n) => n
    None => return None
  }
  
  let values_json = match get_array(json, "values") {
    Some(arr) => arr
    None => return None
  }
  
  let values : Array[@core.Value] = []
  for vj in values_json {
    match restore_value_from_json(vj) {
      Some(v) => values.push(v)
      None => return None
    }
  }
  
  Some({ ts: ts, values: values })
}

fn restore_int64_array_from_json(json : @core.JsonValue) -> Array[Int64]? {
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

fn restore_int_array_from_json(json : @core.JsonValue) -> Array[Int]? {
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

fn restore_value_array_from_json(json : @core.JsonValue) -> Array[@core.Value]? {
  match json.as_array() {
    Some(arr) => {
      let result : Array[@core.Value] = []
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

fn restore_compressed_chunk_from_json(json : @core.JsonValue) -> CompressedChunk? {
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
  
  let columns : Array[Array[@core.Value]] = []
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

fn restore_chunk_from_json(json : @core.JsonValue) -> Chunk? {
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

fn restore_snapshot_from_json(json : @core.JsonValue) -> Snapshot? {
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

fn restore_changelog_entry_from_json(json : @core.JsonValue) -> @core.ChangeLogEntry? {
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
    @core.Operation::Insert(row)
  } else if op_type == "delete" {
    let ts = match get_int64(op_json, "ts") {
      Some(n) => n
      None => return None
    }
    @core.Operation::Delete(ts)
  } else {
    return None
  }
  
  Some({ seq: seq, timestamp: timestamp, op: op })
}

/// Deserialize TimeSeriesStore from JSON string (full state restore)
pub fn TimeSeriesStore::deserialize(json_str : String) -> TimeSeriesStore? {
  let json = match @core.parse_json(json_str) {
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
  
  // v0.2 fields — fall back to defaults so v0.1 JSON still loads.
  let site_id = match get_string(json, "site_id") {
    Some(s) => s
    None => "default"
  }
  let crdt_enabled = match get_bool(json, "crdt_enabled") {
    Some(b) => b
    None => false
  }
  let retention_enabled = match get_bool(json, "retention_enabled") {
    Some(b) => b
    None => false
  }
  let retention_duration_ms = match get_int64(json, "retention_duration_ms") {
    Some(n) => n
    None => 0L
  }
  let db = TimeSeriesStore::with_config(compact_threshold, site_id)
  db.sync_enabled = sync_enabled
  db.crdt_enabled = crdt_enabled
  db.retention.enabled = retention_enabled
  db.retention.duration_ms = retention_duration_ms
  
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

// =============================================================================
// SyncPacket JSON parser — counterpart to sync_packet_to_json.
// =============================================================================

///|
fn restore_lww_value(json : @core.JsonValue) -> @core.LWWValue? {
  let value = match json.get("v") {
    Some(j) => match restore_value_from_json(j) {
      Some(v) => v
      None => return None
    }
    None => return None
  }
  let timestamp = match json.get("ts") {
    Some(j) => match j.as_int64() {
      Some(n) => n
      None => return None
    }
    None => return None
  }
  let site_id = match json.get("sid") {
    Some(j) => match j.as_string() {
      Some(s) => s
      None => ""
    }
    None => ""
  }
  Some({ value, timestamp, site_id })
}

///|
fn restore_crdt_row(json : @core.JsonValue) -> @core.CRDTRow? {
  let ts = match json.get("ts") {
    Some(j) => match j.as_int64() {
      Some(n) => n
      None => return None
    }
    None => return None
  }
  let columns : Array[@core.LWWValue] = []
  match json.get("cols") {
    Some(arr_json) => match arr_json.as_array() {
      Some(arr) => for c in arr {
        match restore_lww_value(c) {
          Some(lww) => columns.push(lww)
          None => ()
        }
      }
      None => ()
    }
    None => ()
  }
  let deleted = match json.get("deleted") {
    Some(j) => j.as_bool().or(false)
    None => false
  }
  let delete_timestamp = match json.get("delete_ts") {
    Some(j) => j.as_int64().or(0L)
    None => 0L
  }
  Some({ ts, columns, deleted, delete_timestamp })
}

///| Parse a JSON SyncPacket. Returns `None` if the JSON is malformed.
pub fn sync_packet_from_json(json_str : String) -> @core.SyncPacket? {
  let json = match @core.parse_json(json_str) {
    Some(j) => j
    None => return None
  }
  let from_seq = match json.get("from") {
    Some(j) => j.as_int64().or(0L)
    None => 0L
  }
  let to_seq = match json.get("to") {
    Some(j) => j.as_int64().or(0L)
    None => 0L
  }
  let changes : Array[@core.ChangeLogEntry] = []
  match json.get("changes") {
    Some(arr_json) => match arr_json.as_array() {
      Some(arr) => for c in arr {
        match restore_changelog_entry_from_json(c) {
          Some(e) => changes.push(e)
          None => ()
        }
      }
      None => ()
    }
    None => ()
  }
  let crdt_rows : Array[@core.CRDTRow] = []
  match json.get("crdt_rows") {
    Some(arr_json) => match arr_json.as_array() {
      Some(arr) => for r in arr {
        match restore_crdt_row(r) {
          Some(rr) => crdt_rows.push(rr)
          None => ()
        }
      }
      None => ()
    }
    None => ()
  }
  Some({ from_seq, to_seq, changes, crdt_rows })
}
