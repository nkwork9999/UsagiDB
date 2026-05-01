///|
/// Aggregation kinds used by `Downsample`.
pub(all) enum Aggregation {
  Average
  Max
  Min
  First
  Last
  OHLC
} derive(Show, Eq)

///|
/// Compaction strategy selected per key.
///
/// Duration-valued variants carry milliseconds.
pub(all) enum CompactionStrategy {
  /// Keep only the newest sample.
  KeepLatest
  /// Keep the last `n` samples.
  KeepLastN(Int)
  /// Keep samples within the last `window_ms` milliseconds.
  KeepWindow(Int64)
  /// Keep every sample.
  KeepAll
  /// Bucket samples into `bucket_ms`-wide windows and aggregate.
  Downsample(Int64, Aggregation)
  /// Drop new samples whose delta from the last kept sample is <= threshold.
  DeadBand(Double)
  /// Drop new samples that arrive within `window_ms` of the previous one.
  RateLimit(Int64)
  /// Keep transitions that differ by > threshold, plus a heartbeat every
  /// `heartbeat_ms` milliseconds regardless of change.
  ExceptionBased(Double, Int64)
} derive(Show, Eq)

///|
/// When compaction is executed for a key.
pub(all) enum CompactionTrigger {
  EveryN(Int)
  EveryDuration(Int64)
  OnRead
  Manual
} derive(Show, Eq)

///|
/// Per-sample validation rules applied before compaction.
pub(all) enum ValidationRule {
  /// Accept values within [min, max] (inclusive).
  Range(Double, Double)
  /// Reject if |value - previous| / dt_seconds exceeds `max_rate`.
  RateOfChange(Double)
  /// Emit timeout if no sample for `window_ms`.
  Timeout(Int64)
  /// Emit anomaly when the same value has been seen `n` consecutive times.
  Frozen(Int)
} derive(Show, Eq)

///|
/// Reason a sample was flagged as anomalous.
pub(all) enum AnomalyReason {
  OutOfRange(Double, Double, Double) // value, min, max
  RateExceeded(Double) // observed rate
  FrozenValue(Int) // repeat count
  TimedOut(Int64) // gap in ms
} derive(Show, Eq)

///|
/// A candlestick bucket for OHLC downsampling.
pub(all) struct OHLCBucket {
  start : Int64
  open : Double
  mut high : Double
  mut low : Double
  mut close : Double
  mut count : Int
  mut sum : Double
} derive(Show)

///|
/// The output row type of `query` — uniform across strategies so that
/// renderers do not need to know how a series was compacted.
pub(all) enum Row {
  Point(Int64, Double)
  Candle(OHLCBucket)
} derive(Show)
