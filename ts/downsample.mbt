// ============================================
// Downsample
// ============================================

pub fn TimeSeriesStore::downsample(
  self : TimeSeriesStore,
  start : Int64,
  end : Int64,
  bucket_ms : Int64,
  col_index : Int,
  agg : AggType
) -> Array[(Int64, AggResult)] {
  let result : Array[(Int64, AggResult)] = []
  
  let mut bucket_start = start
  
  while bucket_start < end {
    let bucket_end = bucket_start + bucket_ms - 1
    let actual_end = if bucket_end > end { end } else { bucket_end }
    
    let agg_result = match agg {
      AggType::Sum => self.sum(bucket_start, actual_end, col_index)
      AggType::Count => self.count(bucket_start, actual_end)
      AggType::Avg => self.avg(bucket_start, actual_end, col_index)
      AggType::Min => self.min(bucket_start, actual_end, col_index)
      AggType::Max => self.max(bucket_start, actual_end, col_index)
    }
    
    match agg_result {
      AggResult::NullResult => ()
      _ => result.push((bucket_start, agg_result))
    }
    
    bucket_start = bucket_start + bucket_ms
  }
  
  result
}

pub fn TimeSeriesStore::group_by_time(
  self : TimeSeriesStore,
  start : Int64,
  end : Int64,
  unit : @core.TimeUnit,
  col_index : Int,
  agg : AggType
) -> Array[(Int64, AggResult)] {
  let bucket_ms = unit.to_ms()
  self.downsample(start, end, bucket_ms, col_index, agg)
}

