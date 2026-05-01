///|
/// Event Sourcing events. The design in `moonbit-compaction-realtime-sensor.md`
/// emphasizes that the transition function is *strategy-agnostic* — it just
/// calls `store.put` and the compaction rules decide what actually gets kept.
pub(all) enum Event {
  PriceReceived(String, Double, Int64)
  SensorReading(String, Double, Int64)
  SensorAnomaly(String, AnomalyReason, Int64)
  SensorAdded(String)
  SensorRemoved(String)
  ThresholdBreached(String, Double, Double, Int64)
} derive(Show)

///|
/// Apply a single event to the store. Returns the store (which is itself
/// mutated — returned for chain-style use and to mirror the design doc's
/// `transition(state, event) -> state` shape).
///
/// The function does **not** know which compaction strategy applies — the
/// config on the store decides. This is the core structural point of the
/// design: strategy changes never touch this function.
pub fn transition(store : EventStore, event : Event) -> EventStore {
  match event {
    PriceReceived(key, value, time) => {
      let _ = store.put(key, value, time)

    }
    SensorReading(key, value, time) => {
      let _ = store.put(key, value, time)

    }
    SensorAnomaly(_, _, _) => ()
    SensorAdded(_) => ()
    SensorRemoved(key) => store.series.remove(key)
    ThresholdBreached(_, _, _, _) => ()
  }
  store
}
