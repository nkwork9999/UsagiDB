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

fn value_to_json(v : @core.Value) -> String {
  match v {
    @core.Value::Null => "{\"t\":0}"
    @core.Value::Int(n) => "{\"t\":1,\"v\":" + n.to_string() + "}"
    @core.Value::Float(n) => "{\"t\":2,\"v\":" + n.to_string() + "}"
    @core.Value::String(s) => "{\"t\":3,\"v\":\"" + escape_json_string(s) + "\"}"
    @core.Value::Timestamp(n) => "{\"t\":4,\"v\":" + n.to_string() + "}"
  }
}

fn row_to_json(row : @core.Row) -> String {
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

fn value_array_to_json(arr : Array[@core.Value]) -> String {
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

fn changelog_entry_to_json(entry : @core.ChangeLogEntry) -> String {
  let op_json = match entry.op {
    @core.Operation::Insert(row) => "{\"type\":\"insert\",\"row\":" + row_to_json(row) + "}"
    @core.Operation::Delete(ts) => "{\"type\":\"delete\",\"ts\":" + ts.to_string() + "}"
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

/// Serialize entire TimeSeriesStore to JSON string
pub fn TimeSeriesStore::serialize(self : TimeSeriesStore) -> String {
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
  ",\"sync_enabled\":" + self.sync_enabled.to_string() +
  ",\"site_id\":\"" + self.site_id + "\"" +
  ",\"crdt_enabled\":" + self.crdt_enabled.to_string() +
  ",\"retention_enabled\":" + self.retention.enabled.to_string() +
  ",\"retention_duration_ms\":" + self.retention.duration_ms.to_string() + "}"
}

