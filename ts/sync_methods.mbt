// ============================================
// Sync Methods
// ============================================

pub fn TimeSeriesStore::sync_state(self : TimeSeriesStore) -> @core.SyncState {
  {
    local_seq: self.changelog.last_seq(),
    remote_seq: 0L,
    pending: self.changelog.len()
  }
}

///| Same as `get_changes_since` but only includes changes whose row matches
/// `shape`. Lets a remote subscribe to just a slice of the data instead of
/// the full firehose.
pub fn TimeSeriesStore::get_changes_since_shape(
  self : TimeSeriesStore,
  since_seq : Int64,
  shape : @core.Shape,
) -> @core.SyncPacket {
  let all_changes = self.changelog.get_since(since_seq)
  let changes : Array[@core.ChangeLogEntry] = []
  for entry in all_changes {
    if shape.matches_entry(entry) {
      changes.push(entry)
    }
  }
  let crdt_rows : Array[@core.CRDTRow] = if self.crdt_enabled {
    let copy : Array[@core.CRDTRow] = []
    for r in self.crdt_rows {
      // Re-use Shape's row predicate via to_row().
      if shape.matches_row(r.to_row()) {
        copy.push(r)
      }
    }
    copy
  } else {
    []
  }
  { from_seq: since_seq, to_seq: self.changelog.last_seq(), changes, crdt_rows }
}

pub fn TimeSeriesStore::get_changes_since(self : TimeSeriesStore, since_seq : Int64) -> @core.SyncPacket {
  let changes = self.changelog.get_since(since_seq)
  // Ship CRDT rows with the packet when CRDT is enabled — receivers that
  // don't care can simply ignore the field.
  let crdt_rows : Array[@core.CRDTRow] = if self.crdt_enabled {
    let copy : Array[@core.CRDTRow] = []
    for r in self.crdt_rows {
      copy.push(r)
    }
    copy
  } else {
    []
  }
  { from_seq: since_seq, to_seq: self.changelog.last_seq(), changes, crdt_rows }
}

pub fn TimeSeriesStore::apply_changes(self : TimeSeriesStore, packet : @core.SyncPacket) -> @core.SyncResult {
  let mut applied = 0
  let conflicts : Array[Int64] = []
  let was_enabled = self.sync_enabled
  self.sync_enabled = false
  for entry in packet.changes {
    match entry.op {
      @core.Operation::Insert(row) => {
        let existing = self.scan(row.ts, row.ts)
        if existing.length() > 0 {
          conflicts.push(row.ts)
        }
        let _ = self.delta.insert(row)
        applied = applied + 1
      }
      @core.Operation::Delete(ts) => {
        self.deleted.add(ts)
        applied = applied + 1
      }
    }
  }
  // Fold CRDT rows into the local set if CRDT is enabled here too.
  if self.crdt_enabled && packet.crdt_rows.length() > 0 {
    let _ = self.merge_crdt(packet.crdt_rows)

  }
  self.sync_enabled = was_enabled
  if conflicts.length() > 0 {
    @core.SyncResult::Conflict(conflicts)
  } else {
    @core.SyncResult::Success(applied)
  }
}

///| Fold remote CRDT rows into the local set using LWW (default policy).
pub fn TimeSeriesStore::merge_crdt(
  self : TimeSeriesStore,
  remote_rows : Array[@core.CRDTRow],
) -> Int {
  self.merge_crdt_with(remote_rows, @core.LastWriteWins)
}

///| Fold remote CRDT rows under an explicit conflict-resolution policy.
/// Use e.g. `MaxValue` for "always keep the highest reading", or
/// `PreferSite("server")` to defer to a primary node.
pub fn TimeSeriesStore::merge_crdt_with(
  self : TimeSeriesStore,
  remote_rows : Array[@core.CRDTRow],
  policy : @core.ConflictResolver,
) -> Int {
  let mut merged_count = 0
  for remote in remote_rows {
    let mut found = false
    for i = 0; i < self.crdt_rows.length(); i = i + 1 {
      if self.crdt_rows[i].ts == remote.ts {
        self.crdt_rows[i] = self.crdt_rows[i].merge_with(remote, policy)
        found = true
        merged_count = merged_count + 1
        break
      }
    }
    if not(found) {
      self.crdt_rows.push(remote)
      merged_count = merged_count + 1
    }
  }
  merged_count
}

pub fn TimeSeriesStore::pending_changes(self : TimeSeriesStore) -> Int {
  self.changelog.len()
}

pub fn TimeSeriesStore::ack_sync(self : TimeSeriesStore, up_to_seq : Int64) -> Unit {
  let _ = up_to_seq
  let _ = self
}


// =============================================================================
// JSON wire format for SyncPacket — used by the WebSocket / HTTP transport.
// =============================================================================

///|
fn lww_value_to_json(v : @core.LWWValue) -> String {
  "{\"v\":" + value_to_json(v.value) +
  ",\"ts\":" + v.timestamp.to_string() +
  ",\"sid\":" + json_string(v.site_id) + "}"
}

///|
fn json_string(s : String) -> String {
  "\"" + s + "\""
}

///|
fn crdt_row_to_json(r : @core.CRDTRow) -> String {
  let buf = StringBuilder::new()
  buf.write_string("{\"ts\":")
  buf.write_string(r.ts.to_string())
  buf.write_string(",\"cols\":[")
  let mut first = true
  for c in r.columns {
    if not(first) { buf.write_char(',') }
    first = false
    buf.write_string(lww_value_to_json(c))
  }
  buf.write_string("],\"deleted\":")
  buf.write_string(r.deleted.to_string())
  buf.write_string(",\"delete_ts\":")
  buf.write_string(r.delete_timestamp.to_string())
  buf.write_char('}')
  buf.to_string()
}

///| Encode a SyncPacket as JSON. Wire format includes ChangeLog entries and
/// (when CRDT enabled) the CRDTRow array.
pub fn sync_packet_to_json(packet : @core.SyncPacket) -> String {
  let buf = StringBuilder::new()
  buf.write_string("{\"from\":")
  buf.write_string(packet.from_seq.to_string())
  buf.write_string(",\"to\":")
  buf.write_string(packet.to_seq.to_string())
  buf.write_string(",\"changes\":[")
  let mut first = true
  for entry in packet.changes {
    if not(first) { buf.write_char(',') }
    first = false
    buf.write_string(changelog_entry_to_json(entry))
  }
  buf.write_string("],\"crdt_rows\":[")
  let mut first2 = true
  for r in packet.crdt_rows {
    if not(first2) { buf.write_char(',') }
    first2 = false
    buf.write_string(crdt_row_to_json(r))
  }
  buf.write_string("]}")
  buf.to_string()
}
