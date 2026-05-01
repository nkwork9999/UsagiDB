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

