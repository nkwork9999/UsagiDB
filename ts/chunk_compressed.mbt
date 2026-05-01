// ============================================
// Compressed Chunk
// ============================================

struct CompressedChunk {
  id : Int
  ts_base : Int64
  ts_deltas : Array[Int64]
  columns : Array[Array[@core.Value]]
  min_ts : Int64
  max_ts : Int64
}

fn CompressedChunk::from_rows(id : Int, rows : Array[@core.Row]) -> CompressedChunk? {
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
  
  let (ts_base, ts_deltas) = @core.delta_encode(timestamps)
  
  let col_count = rows[0].values.length()
  let columns : Array[Array[@core.Value]] = []
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
  @core.delta_decode(self.ts_base, self.ts_deltas)
}

fn CompressedChunk::scan(self : CompressedChunk, start : Int64, end : Int64) -> Array[@core.Row] {
  let result : Array[@core.Row] = []
  
  if self.max_ts < start || self.min_ts > end {
    return result
  }
  
  let timestamps = self.decompress_timestamps()
  
  for i = 0; i < timestamps.length(); i = i + 1 {
    let ts = timestamps[i]
    if ts >= start && ts <= end {
      let values : Array[@core.Value] = []
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
  let ratio = @core.compression_ratio(timestamps, self.ts_deltas)
  
  "Chunk " + self.id.to_string() + " compression:\n" +
  "  Rows: " + original_count.to_string() + "\n" +
  "  Base: " + self.ts_base.to_string() + "\n" +
  "  Deltas: " + delta_count.to_string() + "\n" +
  "  Estimated ratio: " + ratio.to_string() + "x"
}

