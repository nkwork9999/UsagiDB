// ============================================
// Main Store (Column-oriented, for analytics)
// ============================================

struct MainStore {
  mut chunks : Array[Chunk]
  mut next_chunk_id : Int
}

fn MainStore::new() -> MainStore {
  { chunks: [], next_chunk_id: 0 }
}

fn MainStore::add_chunk(self : MainStore, rows : Array[@core.Row]) -> Int? {
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

fn MainStore::scan(self : MainStore, start : Int64, end : Int64) -> Array[@core.Row] {
  let result : Array[@core.Row] = []
  for chunk in self.chunks {
    let rows = chunk.scan(start, end)
    for row in rows {
      result.push(row)
    }
  }
  result
}

fn MainStore::scan_chunks(self : MainStore, chunk_ids : Array[Int], start : Int64, end : Int64) -> Array[@core.Row] {
  let result : Array[@core.Row] = []
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

