// ============================================
// Aggregation Functions
// ============================================

pub(all) enum AggResult {
  IntResult(Int64)
  FloatResult(Double)
  CountResult(Int)
  NullResult
} derive(Show)

pub(all) enum AggType {
  Sum
  Count
  Avg
  Min
  Max
} derive(Show)

pub fn TimeSeriesStore::sum(self : TimeSeriesStore, start : Int64, end : Int64, col_index : Int) -> AggResult {
  let rows = self.scan(start, end)
  
  let mut int_sum : Int64 = 0
  let mut float_sum : Double = 0.0
  let mut has_int = false
  let mut has_float = false
  
  for row in rows {
    if col_index < row.values.length() {
      match row.values[col_index] {
        @core.Value::Int(v) => {
          int_sum = int_sum + v
          has_int = true
        }
        @core.Value::Float(v) => {
          float_sum = float_sum + v
          has_float = true
        }
        _ => ()
      }
    }
  }
  
  if has_float {
    AggResult::FloatResult(float_sum + int_sum.to_double())
  } else if has_int {
    AggResult::IntResult(int_sum)
  } else {
    AggResult::NullResult
  }
}

pub fn TimeSeriesStore::count(self : TimeSeriesStore, start : Int64, end : Int64) -> AggResult {
  let rows = self.scan(start, end)
  AggResult::CountResult(rows.length())
}

pub fn TimeSeriesStore::count_col(self : TimeSeriesStore, start : Int64, end : Int64, col_index : Int) -> AggResult {
  let rows = self.scan(start, end)
  let mut count = 0
  
  for row in rows {
    if col_index < row.values.length() {
      match row.values[col_index] {
        @core.Value::Null => ()
        _ => count = count + 1
      }
    }
  }
  
  AggResult::CountResult(count)
}

pub fn TimeSeriesStore::avg(self : TimeSeriesStore, start : Int64, end : Int64, col_index : Int) -> AggResult {
  let rows = self.scan(start, end)
  
  let mut sum : Double = 0.0
  let mut count = 0
  
  for row in rows {
    if col_index < row.values.length() {
      match row.values[col_index] {
        @core.Value::Int(v) => {
          sum = sum + v.to_double()
          count = count + 1
        }
        @core.Value::Float(v) => {
          sum = sum + v
          count = count + 1
        }
        _ => ()
      }
    }
  }
  
  if count > 0 {
    AggResult::FloatResult(sum / count.to_double())
  } else {
    AggResult::NullResult
  }
}

pub fn TimeSeriesStore::min(self : TimeSeriesStore, start : Int64, end : Int64, col_index : Int) -> AggResult {
  let rows = self.scan(start, end)
  
  let mut min_int : Int64 = 9223372036854775807
  let mut min_float : Double = 1.7976931348623157e308
  let mut has_int = false
  let mut has_float = false
  
  for row in rows {
    if col_index < row.values.length() {
      match row.values[col_index] {
        @core.Value::Int(v) => {
          if v < min_int { min_int = v }
          has_int = true
        }
        @core.Value::Float(v) => {
          if v < min_float { min_float = v }
          has_float = true
        }
        _ => ()
      }
    }
  }
  
  if has_float {
    let int_as_float = min_int.to_double()
    if has_int && int_as_float < min_float {
      AggResult::FloatResult(int_as_float)
    } else {
      AggResult::FloatResult(min_float)
    }
  } else if has_int {
    AggResult::IntResult(min_int)
  } else {
    AggResult::NullResult
  }
}

pub fn TimeSeriesStore::max(self : TimeSeriesStore, start : Int64, end : Int64, col_index : Int) -> AggResult {
  let rows = self.scan(start, end)
  
  let mut max_int : Int64 = -9223372036854775808
  let mut max_float : Double = -1.7976931348623157e308
  let mut has_int = false
  let mut has_float = false
  
  for row in rows {
    if col_index < row.values.length() {
      match row.values[col_index] {
        @core.Value::Int(v) => {
          if v > max_int { max_int = v }
          has_int = true
        }
        @core.Value::Float(v) => {
          if v > max_float { max_float = v }
          has_float = true
        }
        _ => ()
      }
    }
  }
  
  if has_float {
    let int_as_float = max_int.to_double()
    if has_int && int_as_float > max_float {
      AggResult::FloatResult(int_as_float)
    } else {
      AggResult::FloatResult(max_float)
    }
  } else if has_int {
    AggResult::IntResult(max_int)
  } else {
    AggResult::NullResult
  }
}

