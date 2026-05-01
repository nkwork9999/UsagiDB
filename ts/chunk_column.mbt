// ============================================
// Chunk (Columnar storage unit)
// ============================================

struct Chunk {
  id : Int
  compressed : CompressedChunk
}

fn Chunk::from_rows(id : Int, rows : Array[@core.Row]) -> Chunk? {
  match CompressedChunk::from_rows(id, rows) {
    Some(compressed) => Some({ id, compressed })
    None => None
  }
}

fn Chunk::row_count(self : Chunk) -> Int {
  self.compressed.row_count()
}

fn Chunk::max_ts(self : Chunk) -> Int64 {
  self.compressed.max_ts
}

fn Chunk::scan(self : Chunk, start : Int64, end : Int64) -> Array[@core.Row] {
  self.compressed.scan(start, end)
}

fn Chunk::compression_stats(self : Chunk) -> String {
  self.compressed.compression_stats()
}

