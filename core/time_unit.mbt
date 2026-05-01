// ============================================
// Time Unit (for GROUP BY time)
// ============================================

pub(all) enum TimeUnit {
  Millisecond
  Second
  Minute
  Hour
  Day
  Week
} derive(Show)

pub fn TimeUnit::to_ms(self : TimeUnit) -> Int64 {
  match self {
    TimeUnit::Millisecond => 1L
    TimeUnit::Second => 1000L
    TimeUnit::Minute => 60000L
    TimeUnit::Hour => 3600000L
    TimeUnit::Day => 86400000L
    TimeUnit::Week => 604800000L
  }
}

