// ============================================
// Continuous Aggregate (NEW)
// ============================================

pub(all) struct ContinuousAggregate {
  name : String
  bucket_ms : Int64
  col_index : Int
  agg_type : AggType
  mut data : Array[(Int64, AggResult)]
  mut last_updated : Int64
}

pub fn ContinuousAggregate::new(name : String, unit : @core.TimeUnit, col_index : Int, agg_type : AggType) -> ContinuousAggregate {
  { name, bucket_ms: unit.to_ms(), col_index, agg_type, data: [], last_updated: 0L }
}
