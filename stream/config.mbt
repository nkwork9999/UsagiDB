///|
/// Runtime-configurable per-key compaction / validation / trigger rules.
///
/// Methods mutate and return `self` so the builder chain from the design doc
/// works (`config.rule("price", ...).rule("volume", ...)`).
pub struct CompactionConfig {
  rules : Map[String, CompactionStrategy]
  validators : Map[String, Array[ValidationRule]]
  triggers : Map[String, CompactionTrigger]
  mut default_strategy : CompactionStrategy
}

///|
pub fn CompactionConfig::new() -> CompactionConfig {
  {
    rules: Map::new(),
    validators: Map::new(),
    triggers: Map::new(),
    default_strategy: KeepAll,
  }
}

///|
/// Fall-back for keys that have no explicit rule.
pub fn CompactionConfig::default(
  self : CompactionConfig,
  strategy : CompactionStrategy,
) -> CompactionConfig {
  self.default_strategy = strategy
  self
}

///|
/// Register the strategy for `key`.
pub fn CompactionConfig::rule(
  self : CompactionConfig,
  key : String,
  strategy : CompactionStrategy,
) -> CompactionConfig {
  self.rules[key] = strategy
  self
}

///|
/// Register a trigger (when compaction runs). Currently advisory — the store
/// compacts on every `put` — but exposed for future batching.
pub fn CompactionConfig::trigger(
  self : CompactionConfig,
  key : String,
  trigger : CompactionTrigger,
) -> CompactionConfig {
  self.triggers[key] = trigger
  self
}

///|
/// Append a validation rule to the chain for `key`. Multiple rules run in
/// registration order and the first failure produces an anomaly.
pub fn CompactionConfig::validate(
  self : CompactionConfig,
  key : String,
  rule : ValidationRule,
) -> CompactionConfig {
  match self.validators.get(key) {
    Some(arr) => arr.push(rule)
    None => {
      let arr : Array[ValidationRule] = Array::new()
      arr.push(rule)
      self.validators[key] = arr
    }
  }
  self
}

///|
/// Look up the strategy for `key`, falling back to `default_strategy`.
pub fn CompactionConfig::strategy_for(
  self : CompactionConfig,
  key : String,
) -> CompactionStrategy {
  match self.rules.get(key) {
    Some(s) => s
    None => self.default_strategy
  }
}

///|
/// Look up the trigger for `key`. `None` means the default (eager apply on
/// every `put`); other values defer per the design doc.
pub fn CompactionConfig::trigger_for(
  self : CompactionConfig,
  key : String,
) -> CompactionTrigger? {
  self.triggers.get(key)
}

///|
/// Look up validators for `key`, or an empty list if none registered.
pub fn CompactionConfig::validators_for(
  self : CompactionConfig,
  key : String,
) -> Array[ValidationRule] {
  match self.validators.get(key) {
    Some(v) => v
    None => []
  }
}
