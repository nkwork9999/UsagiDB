// ============================================
// Retention Policy (NEW)
// ============================================

pub(all) struct RetentionPolicy {
  mut enabled : Bool
  mut duration_ms : Int64
  mut last_applied : Int64
}

pub fn RetentionPolicy::new() -> RetentionPolicy {
  { enabled: false, duration_ms: 0L, last_applied: 0L }
}
