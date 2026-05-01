///|
/// Per-key validation state carried across `put` calls.
pub struct ValidationState {
  mut last_value : Double?
  mut last_time : Int64?
  mut frozen_count : Int
  mut frozen_value : Double?
}

///|
pub fn ValidationState::new() -> ValidationState {
  { last_value: None, last_time: None, frozen_count: 0, frozen_value: None }
}

///|
/// Run every rule for a key against a new sample. Returns `Some(reason)`
/// for the first failure, `None` when the sample is acceptable.
///
/// The state's `frozen_count` / `frozen_value` are updated whichever way the
/// check goes, so consecutive-repeat detection survives valid samples.
pub fn run_validators(
  state : ValidationState,
  rules : Array[ValidationRule],
  value : Double,
  time : Int64,
) -> AnomalyReason? {
  // Frozen-count bookkeeping needs to run even when no Frozen rule is set?
  // We only update it when a Frozen rule exists so unrelated series don't
  // pay for it — track whether any rule needs it.
  let mut frozen_limit : Int? = None
  for rule in rules {
    match rule {
      Frozen(n) => frozen_limit = Some(n)
      _ => ()
    }
  }
  match frozen_limit {
    Some(_) =>
      match state.frozen_value {
        Some(v) if v == value => state.frozen_count = state.frozen_count + 1
        _ => {
          state.frozen_value = Some(value)
          state.frozen_count = 1
        }
      }
    None => ()
  }
  for rule in rules {
    match rule {
      Range(lo, hi) =>
        if value < lo || value > hi {
          return Some(OutOfRange(value, lo, hi))
        }
      RateOfChange(max_rate) =>
        match (state.last_value, state.last_time) {
          (Some(prev_v), Some(prev_t)) => {
            let dt_ms = time - prev_t
            if dt_ms > 0L {
              let dt_s = dt_ms.to_double() / 1000.0
              let delta = value - prev_v
              let abs_delta = if delta < 0.0 { -delta } else { delta }
              let rate = abs_delta / dt_s
              if rate > max_rate {
                return Some(RateExceeded(rate))
              }
            }
          }
          _ => ()
        }
      Timeout(window) =>
        match state.last_time {
          Some(prev_t) => {
            let gap = time - prev_t
            if gap > window {
              return Some(TimedOut(gap))
            }
          }
          None => ()
        }
      Frozen(n) =>
        if state.frozen_count >= n {
          return Some(FrozenValue(state.frozen_count))
        }
    }
  }
  None
}
