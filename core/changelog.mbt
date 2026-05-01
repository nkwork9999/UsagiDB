// ============================================
// Change Log (for Sync)
// ============================================

/// Operation type for change log
pub(all) enum Operation {
  Insert(Row)
  Delete(Int64)
} derive(Show)

/// A single change entry
pub(all) struct ChangeLogEntry {
  seq : Int64
  timestamp : Int64
  op : Operation
} derive(Show)

/// Change log for tracking all modifications
pub(all) struct ChangeLog {
  entries : Array[ChangeLogEntry]
  mut next_seq : Int64
}

pub fn ChangeLog::new() -> ChangeLog {
  { entries: [], next_seq: 1L }
}

pub fn ChangeLog::append(self : ChangeLog, op : Operation, timestamp : Int64) -> Int64 {
  let seq = self.next_seq
  self.entries.push({ seq, timestamp, op })
  self.next_seq = seq + 1L
  seq
}

pub fn ChangeLog::get_since(self : ChangeLog, since_seq : Int64) -> Array[ChangeLogEntry] {
  let result : Array[ChangeLogEntry] = []
  for entry in self.entries {
    if entry.seq > since_seq {
      result.push(entry)
    }
  }
  result
}

pub fn ChangeLog::last_seq(self : ChangeLog) -> Int64 {
  if self.entries.length() == 0 {
    0L
  } else {
    self.entries[self.entries.length() - 1].seq
  }
}

pub fn ChangeLog::len(self : ChangeLog) -> Int {
  self.entries.length()
}

