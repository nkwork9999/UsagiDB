// ============================================
// Delta Store (@core.Row-oriented, for writes)
// ============================================

struct DeltaStore {
  mut rows : Array[@core.Row]
  mut next_id : Int
}

fn DeltaStore::new() -> DeltaStore {
  { rows: [], next_id: 0 }
}

fn DeltaStore::insert(self : DeltaStore, row : @core.Row) -> Int {
  let id = self.next_id
  self.rows.push(row)
  self.next_id = id + 1
  id
}

fn DeltaStore::len(self : DeltaStore) -> Int {
  self.rows.length()
}

fn DeltaStore::clear(self : DeltaStore) -> Array[@core.Row] {
  let old = self.rows
  self.rows = []
  self.next_id = 0
  old
}

fn DeltaStore::scan(self : DeltaStore, start : Int64, end : Int64) -> Array[@core.Row] {
  let result : Array[@core.Row] = []
  for row in self.rows {
    if row.ts >= start && row.ts <= end {
      result.push(row)
    }
  }
  result
}

