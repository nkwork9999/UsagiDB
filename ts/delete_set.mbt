// ============================================
// Delete Set (for logical deletion)
// ============================================

struct DeleteSet {
  timestamps : Array[Int64]
}

fn DeleteSet::new() -> DeleteSet {
  { timestamps: [] }
}

fn DeleteSet::add(self : DeleteSet, ts : Int64) -> Unit {
  for t in self.timestamps {
    if t == ts {
      return
    }
  }
  self.timestamps.push(ts)
}

fn DeleteSet::contains(self : DeleteSet, ts : Int64) -> Bool {
  for t in self.timestamps {
    if t == ts {
      return true
    }
  }
  false
}

fn DeleteSet::contains_any(deleted : Array[Int64], ts : Int64) -> Bool {
  for t in deleted {
    if t == ts {
      return true
    }
  }
  false
}

fn DeleteSet::count(self : DeleteSet) -> Int {
  self.timestamps.length()
}

fn DeleteSet::clone_timestamps(self : DeleteSet) -> Array[Int64] {
  let result : Array[Int64] = []
  for t in self.timestamps {
    result.push(t)
  }
  result
}

