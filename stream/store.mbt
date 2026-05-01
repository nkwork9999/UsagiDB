///|
/// Per-series mutable state owned by the `EventStore`.
pub struct SeriesState {
  mut samples : Array[(Int64, Double)]
  buckets : Array[OHLCBucket]
  mut last_kept_value : Double?
  mut last_kept_time : Int64?
  validation : ValidationState
  anomalies : Array[(Int64, AnomalyReason)]
  mut total_received : Int
  mut total_kept : Int
  // Trigger-driven lazy compaction: buffered samples awaiting `apply_strategy`.
  // Empty unless a non-default trigger is configured for this series.
  pending : Array[(Int64, Double)]
}

///|
pub fn SeriesState::new() -> SeriesState {
  {
    samples: Array::new(),
    buckets: Array::new(),
    last_kept_value: None,
    last_kept_time: None,
    validation: ValidationState::new(),
    anomalies: Array::new(),
    total_received: 0,
    total_kept: 0,
    pending: Array::new(),
  }
}

///|
/// Outcome of a `put` call — useful for integrating with Event Sourcing so
/// the transition function can emit `SensorAnomaly` events.
pub(all) enum PutResult {
  Kept
  Dropped
  Anomalous(AnomalyReason)
} derive(Show, Eq)

///|
/// Central store. Writes go through `put`; reads through `query`.
/// The same store handles keys with different compaction strategies.
pub struct EventStore {
  config : CompactionConfig
  series : Map[String, SeriesState]
}

///|
pub fn EventStore::new(config : CompactionConfig) -> EventStore {
  { config, series: Map::new() }
}

///| Add a per-key compaction rule on the underlying config. Mirrors the
/// `CompactionConfig` builder so callers don't need to expose the config field.
pub fn EventStore::set_rule(
  self : EventStore,
  key : String,
  strategy : CompactionStrategy,
) -> Unit {
  let _ = self.config.rule(key, strategy)

}

///| Register a trigger (eager / batch / lazy) for `key`.
pub fn EventStore::set_trigger(
  self : EventStore,
  key : String,
  trigger : CompactionTrigger,
) -> Unit {
  let _ = self.config.trigger(key, trigger)

}

///|
fn EventStore::ensure_series(self : EventStore, key : String) -> SeriesState {
  match self.series.get(key) {
    Some(s) => s
    None => {
      let s = SeriesState::new()
      self.series[key] = s
      s
    }
  }
}

///|
/// Absolute value of a Double — core lacks a visible `.abs()` in this version.
fn fabs(x : Double) -> Double {
  if x < 0.0 {
    -x
  } else {
    x
  }
}

///|
/// Insert `value` at time `time` for series `key`. Returns whether the sample
/// was kept, dropped by a filter-style strategy, or flagged anomalous.
///
/// When a non-default `CompactionTrigger` is configured for the key (`OnRead`,
/// `Manual`, `EveryN`), the sample is buffered into `state.pending` instead of
/// applying the strategy eagerly. The actual `apply_strategy` runs at flush
/// time. In that mode `put` always returns `Kept` (the sample was accepted),
/// even though the strategy might later drop it during flush.
pub fn EventStore::put(
  self : EventStore,
  key : String,
  value : Double,
  time : Int64,
) -> PutResult {
  let state = self.ensure_series(key)
  state.total_received = state.total_received + 1
  let rules = self.config.validators_for(key)
  match run_validators(state.validation, rules, value, time) {
    Some(reason) => {
      state.anomalies.push((time, reason))
      state.validation.last_value = Some(value)
      state.validation.last_time = Some(time)
      return Anomalous(reason)
    }
    None => ()
  }
  state.validation.last_value = Some(value)
  state.validation.last_time = Some(time)
  let strategy = self.config.strategy_for(key)
  match self.config.trigger_for(key) {
    None => {
      // Eager: apply strategy immediately (default).
      let kept = apply_strategy(state, strategy, value, time)
      if kept {
        state.total_kept = state.total_kept + 1
        Kept
      } else {
        Dropped
      }
    }
    Some(EveryN(n)) => {
      // Batch: buffer until n pending, then drain.
      state.pending.push((time, value))
      if state.pending.length() >= n {
        flush_pending(state, strategy)
      }
      Kept
    }
    Some(EveryDuration(window_ms)) => {
      state.pending.push((time, value))
      let oldest = state.pending[0].0
      if time - oldest >= window_ms {
        flush_pending(state, strategy)
      }
      Kept
    }
    Some(OnRead) | Some(Manual) => {
      // Defer until query() (OnRead) or compact() (Manual).
      state.pending.push((time, value))
      Kept
    }
  }
}

///| Drain `state.pending` through `apply_strategy`, in order.
fn flush_pending(
  state : SeriesState,
  strategy : CompactionStrategy,
) -> Unit {
  for s in state.pending {
    let (t, v) = s
    if apply_strategy(state, strategy, v, t) {
      state.total_kept = state.total_kept + 1
    }
  }
  state.pending.clear()
}

///| Manually flush a key's pending buffer (useful for `Manual` trigger or to
/// force a checkpoint without waiting for a count/time threshold).
pub fn EventStore::compact(self : EventStore, key : String) -> Unit {
  match self.series.get(key) {
    None => ()
    Some(state) => {
      let strategy = self.config.strategy_for(key)
      flush_pending(state, strategy)
    }
  }
}

///|
fn apply_strategy(
  state : SeriesState,
  strategy : CompactionStrategy,
  value : Double,
  time : Int64,
) -> Bool {
  match strategy {
    KeepLatest => {
      state.samples = [(time, value)]
      state.last_kept_value = Some(value)
      state.last_kept_time = Some(time)
      true
    }
    KeepLastN(n) => {
      state.samples.push((time, value))
      while state.samples.length() > n {
        let _ = state.samples.remove(0)

      }
      state.last_kept_value = Some(value)
      state.last_kept_time = Some(time)
      true
    }
    KeepWindow(window_ms) => {
      state.samples.push((time, value))
      let cutoff = time - window_ms
      state.samples = state.samples.filter(fn(s) {
        let (t, _) = s
        t >= cutoff
      })
      state.last_kept_value = Some(value)
      state.last_kept_time = Some(time)
      true
    }
    KeepAll => {
      state.samples.push((time, value))
      state.last_kept_value = Some(value)
      state.last_kept_time = Some(time)
      true
    }
    Downsample(bucket_ms, _) => {
      update_bucket(state, time, value, bucket_ms)
      state.last_kept_value = Some(value)
      state.last_kept_time = Some(time)
      true
    }
    DeadBand(threshold) => {
      let keep = match state.last_kept_value {
        None => true
        Some(prev) => fabs(value - prev) > threshold
      }
      if keep {
        state.samples.push((time, value))
        state.last_kept_value = Some(value)
        state.last_kept_time = Some(time)
      }
      keep
    }
    RateLimit(window) => {
      let keep = match state.last_kept_time {
        None => true
        Some(prev_t) => time - prev_t > window
      }
      if keep {
        state.samples.push((time, value))
        state.last_kept_value = Some(value)
        state.last_kept_time = Some(time)
      }
      keep
    }
    ExceptionBased(threshold, heartbeat) => {
      let keep = match state.last_kept_value {
        None => true
        Some(pv) =>
          match state.last_kept_time {
            None => true
            Some(pt) => fabs(value - pv) > threshold || time - pt > heartbeat
          }
      }
      if keep {
        state.samples.push((time, value))
        state.last_kept_value = Some(value)
        state.last_kept_time = Some(time)
      }
      keep
    }
  }
}

///|
/// Bucket merge for `Downsample`. Uses `OHLCBucket` to store every field any
/// aggregation kind could need — the choice of aggregation is deferred to
/// `query`-time so the same raw buckets can be re-read under any aggregation.
fn update_bucket(
  state : SeriesState,
  time : Int64,
  value : Double,
  bucket_ms : Int64,
) -> Unit {
  let start = time / bucket_ms * bucket_ms
  let n = state.buckets.length()
  if n > 0 && state.buckets[n - 1].start == start {
    let b = state.buckets[n - 1]
    if value > b.high {
      b.high = value
    }
    if value < b.low {
      b.low = value
    }
    b.close = value
    b.sum = b.sum + value
    b.count = b.count + 1
    return
  }
  if n == 0 || state.buckets[n - 1].start < start {
    state.buckets.push({
      start,
      open: value,
      high: value,
      low: value,
      close: value,
      sum: value,
      count: 1,
    })
    return
  }
  // Out-of-order sample: linear scan from the tail.
  let mut i = n - 1
  while i >= 0 && state.buckets[i].start > start {
    i = i - 1
  }
  if i >= 0 && state.buckets[i].start == start {
    let b = state.buckets[i]
    if value > b.high {
      b.high = value
    }
    if value < b.low {
      b.low = value
    }
    // `close` left alone because `time` is older than what's already in the
    // bucket; only `high`/`low`/`sum`/`count` are order-independent.
    b.sum = b.sum + value
    b.count = b.count + 1
  } else {
    state.buckets.insert(i + 1, {
      start,
      open: value,
      high: value,
      low: value,
      close: value,
      sum: value,
      count: 1,
    })
  }
}

///|
/// Return the stored rows for `key`. The return type is uniform (`Row`) so
/// the renderer doesn't need to know the strategy.
pub fn EventStore::query(self : EventStore, key : String) -> Array[Row] {
  match self.series.get(key) {
    None => []
    Some(state) => {
      let strategy = self.config.strategy_for(key)
      // For OnRead trigger, drain pending first so the read sees fresh data.
      match self.config.trigger_for(key) {
        Some(OnRead) => flush_pending(state, strategy)
        _ => ()
      }
      match strategy {
        Downsample(_, agg) => state.buckets.map(fn(b) { bucket_to_row(b, agg) })
        _ => state.samples.map(fn(s) { Point(s.0, s.1) })
      }
    }
  }
}

///|
fn bucket_to_row(b : OHLCBucket, agg : Aggregation) -> Row {
  match agg {
    OHLC => Candle(b)
    Average => Point(b.start, b.sum / b.count.to_double())
    Max => Point(b.start, b.high)
    Min => Point(b.start, b.low)
    First => Point(b.start, b.open)
    Last => Point(b.start, b.close)
  }
}

///|
/// Return recorded anomalies for `key` (empty if none).
pub fn EventStore::anomalies(
  self : EventStore,
  key : String,
) -> Array[(Int64, AnomalyReason)] {
  match self.series.get(key) {
    None => []
    Some(state) => state.anomalies
  }
}

///|
/// Received / kept counters for `key`, useful for memory-budget assertions.
pub fn EventStore::stats(self : EventStore, key : String) -> (Int, Int) {
  match self.series.get(key) {
    None => (0, 0)
    Some(state) => (state.total_received, state.total_kept)
  }
}

///|
/// Raw sample count actually retained (points + buckets).
pub fn EventStore::size(self : EventStore, key : String) -> Int {
  match self.series.get(key) {
    None => 0
    Some(state) => state.samples.length() + state.buckets.length()
  }
}
