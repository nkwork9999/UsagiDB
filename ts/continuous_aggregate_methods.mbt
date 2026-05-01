// Continuous aggregate API on TimeSeriesStore. Register a named bucket-based
// aggregate, then `refresh_aggregate` recomputes its data over a time range.

///|
pub fn TimeSeriesStore::register_aggregate(
  self : TimeSeriesStore,
  name : String,
  unit : @core.TimeUnit,
  col_index : Int,
  agg_type : AggType,
) -> Unit {
  let agg = ContinuousAggregate::new(name, unit, col_index, agg_type)
  self.aggregates.push(agg)
}

///| Recompute the aggregate's `data` over `[start, end)` using the existing
/// `downsample` helper. Returns `false` if the named aggregate isn't found.
pub fn TimeSeriesStore::refresh_aggregate(
  self : TimeSeriesStore,
  name : String,
  start : Int64,
  end : Int64,
) -> Bool {
  for agg in self.aggregates {
    if agg.name == name {
      let results = self.downsample(
        start, end, agg.bucket_ms, agg.col_index, agg.agg_type,
      )
      agg.data = results
      agg.last_updated = end
      return true
    }
  }
  false
}

///|
pub fn TimeSeriesStore::query_aggregate(
  self : TimeSeriesStore,
  name : String,
) -> Array[(Int64, AggResult)] {
  for agg in self.aggregates {
    if agg.name == name {
      return agg.data
    }
  }
  []
}

///|
pub fn TimeSeriesStore::list_aggregates(
  self : TimeSeriesStore,
) -> Array[String] {
  let result : Array[String] = []
  for agg in self.aggregates {
    result.push(agg.name)
  }
  result
}
