// ============================================
// Sync State
// ============================================

/// Sync state tracking
pub(all) struct SyncState {
  local_seq : Int64
  remote_seq : Int64
  pending : Int
}

/// Sync result
pub(all) enum SyncResult {
  Success(Int)
  Conflict(Array[Int64])
  Error(String)
} derive(Show)

/// Changes to be synced. `crdt_rows` is empty unless the source had CRDT
/// enabled, so a v0.1 receiver can ignore it without breaking anything.
pub(all) struct SyncPacket {
  from_seq : Int64
  to_seq : Int64
  changes : Array[ChangeLogEntry]
  crdt_rows : Array[CRDTRow]
} derive(Show)

