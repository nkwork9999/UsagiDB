pub fn TimeSeriesStore::scan_with_fill(
  self : TimeSeriesStore,
  start : Int64,
  end : Int64,
  interval_ms : Int64,
  method : FillMethod
) -> Array[@core.Row] {
  let raw_rows = self.scan(start, end)
  let result : Array[@core.Row] = []
  
  let row_map : Array[(Int64, @core.Row)] = []
  for row in raw_rows { row_map.push((row.ts, row)) }
  
  let col_count = if raw_rows.length() > 0 { raw_rows[0].values.length() } else { 0 }
  if col_count == 0 { return result }
  
  let mut current_ts = start
  let mut last_row : @core.Row? = None
  
  while current_ts <= end {
    let mut found_row : @core.Row? = None
    for pair in row_map {
      if pair.0 == current_ts { found_row = Some(pair.1); break }
    }
    
    match found_row {
      Some(row) => {
        result.push(row)
        last_row = Some(row)
      }
      None => {
        let filled_values : Array[@core.Value] = []
        match method {
          FillMethod::Null => {
            for i = 0; i < col_count; i = i + 1 { filled_values.push(@core.Value::Null) }
          }
          FillMethod::Previous => {
            match last_row {
              Some(lr) => { for v in lr.values { filled_values.push(v) } }
              None => { for i = 0; i < col_count; i = i + 1 { filled_values.push(@core.Value::Null) } }
            }
          }
          FillMethod::Next => {
            let mut next_row : @core.Row? = None
            for pair in row_map {
              if pair.0 > current_ts {
                match next_row {
                  None => next_row = Some(pair.1)
                  Some(nr) => if pair.0 < nr.ts { next_row = Some(pair.1) }
                }
              }
            }
            match next_row {
              Some(nr) => { for v in nr.values { filled_values.push(v) } }
              None => { for i = 0; i < col_count; i = i + 1 { filled_values.push(@core.Value::Null) } }
            }
          }
          FillMethod::Linear => {
            let mut next_row : @core.Row? = None
            for pair in row_map {
              if pair.0 > current_ts {
                match next_row {
                  None => next_row = Some(pair.1)
                  Some(nr) => if pair.0 < nr.ts { next_row = Some(pair.1) }
                }
              }
            }
            match (last_row, next_row) {
              (Some(lr), Some(nr)) => {
                let t_total = (nr.ts - lr.ts).to_double()
                let t_current = (current_ts - lr.ts).to_double()
                let ratio = t_current / t_total
                for i = 0; i < col_count; i = i + 1 {
                  match (lr.values[i], nr.values[i]) {
                    (@core.Value::Float(v1), @core.Value::Float(v2)) => {
                      filled_values.push(@core.Value::Float(v1 + (v2 - v1) * ratio))
                    }
                    (@core.Value::Int(v1), @core.Value::Int(v2)) => {
                      let interp = v1.to_double() + (v2.to_double() - v1.to_double()) * ratio
                      filled_values.push(@core.Value::Float(interp))
                    }
                    _ => filled_values.push(@core.Value::Null)
                  }
                }
              }
              _ => { for i = 0; i < col_count; i = i + 1 { filled_values.push(@core.Value::Null) } }
            }
          }
          FillMethod::Constant(val) => {
            for i = 0; i < col_count; i = i + 1 { filled_values.push(val) }
          }
        }
        result.push({ ts: current_ts, values: filled_values })
      }
    }
    current_ts = current_ts + interval_ms
  }
  result
}

