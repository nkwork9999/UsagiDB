// Typed query builder over UsagiDB's ts mode. Not a SQL parser —
// SQL ergonomics via fluent API. Bring your own SQLite-WASM / DuckDB-WASM
// if you need full SQL grammar.
//
// Example:
//   Query::from_ts()
//     .where_time_between(0L, 1000L)
//     .where_col_eq(0, Value::String("sensor-1"))
//     .select_count()
//     .execute(db)

///|
pub(all) enum QueryFilter {
  TimeBetween(Int64, Int64)
  ColumnEq(Int, @core.Value)
} derive(Show)

///|
pub(all) enum Aggregate {
  Rows
  Count
  Avg(Int)
  Min(Int)
  Max(Int)
  Sum(Int)
} derive(Show)

///|
pub(all) enum QueryResult {
  RowsResult(Array[@core.Row])
  CountResult(Int)
  NumberResult(Double)
  NullResult
} derive(Show)

///|
pub struct Query {
  filters : Array[QueryFilter]
  agg : Aggregate
}

///|
pub fn Query::from_ts() -> Query {
  { filters: [], agg: Rows }
}

///|
pub fn Query::where_time_between(
  self : Query,
  ts_min : Int64,
  ts_max : Int64,
) -> Query {
  self.filters.push(TimeBetween(ts_min, ts_max))
  self
}

///|
pub fn Query::where_col_eq(
  self : Query,
  col : Int,
  value : @core.Value,
) -> Query {
  self.filters.push(ColumnEq(col, value))
  self
}

///|
pub fn Query::select_count(self : Query) -> Query {
  { ..self, agg: Count }
}

///|
pub fn Query::select_avg(self : Query, col : Int) -> Query {
  { ..self, agg: Avg(col) }
}

///|
pub fn Query::select_min(self : Query, col : Int) -> Query {
  { ..self, agg: Min(col) }
}

///|
pub fn Query::select_max(self : Query, col : Int) -> Query {
  { ..self, agg: Max(col) }
}

///|
pub fn Query::select_sum(self : Query, col : Int) -> Query {
  { ..self, agg: Sum(col) }
}

///|
fn extract_time_range(filters : Array[QueryFilter]) -> (Int64, Int64) {
  let mut lo : Int64 = 0L
  let mut hi : Int64 = 9999999999999L
  for f in filters {
    match f {
      TimeBetween(a, b) => {
        lo = a
        hi = b
      }
      _ => ()
    }
  }
  (lo, hi)
}

///| Run the query against `store`. Returns a `QueryResult`.
pub fn Query::execute(
  self : Query,
  store : @ts.TimeSeriesStore,
) -> QueryResult {
  let (lo, hi) = extract_time_range(self.filters)
  // First narrow by time.
  let mut rows = store.scan(lo, hi)
  // Then apply ColumnEq filters in-memory.
  for f in self.filters {
    match f {
      ColumnEq(col, val) => {
        let kept : Array[@core.Row] = []
        for r in rows {
          if col < r.values.length() {
            if values_eq(r.values[col], val) {
              kept.push(r)
            }
          }
        }
        rows = kept
      }
      _ => ()
    }
  }
  match self.agg {
    Rows => RowsResult(rows)
    Count => CountResult(rows.length())
    Avg(col) => agg_average(rows, col)
    Min(col) => agg_min(rows, col)
    Max(col) => agg_max(rows, col)
    Sum(col) => agg_sum(rows, col)
  }
}

///|
fn values_eq(a : @core.Value, b : @core.Value) -> Bool {
  match (a, b) {
    (Null, Null) => true
    (Int(x), Int(y)) => x == y
    (Float(x), Float(y)) => x == y
    (String(x), String(y)) => x == y
    (Timestamp(x), Timestamp(y)) => x == y
    _ => false
  }
}

///|
fn value_to_double(v : @core.Value) -> Double? {
  match v {
    Int(n) => Some(n.to_double())
    Float(n) => Some(n)
    _ => None
  }
}

///|
fn agg_average(rows : Array[@core.Row], col : Int) -> QueryResult {
  let mut sum = 0.0
  let mut count = 0
  for r in rows {
    if col < r.values.length() {
      match value_to_double(r.values[col]) {
        Some(v) => {
          sum = sum + v
          count = count + 1
        }
        None => ()
      }
    }
  }
  if count == 0 {
    NullResult
  } else {
    NumberResult(sum / count.to_double())
  }
}

///|
fn agg_min(rows : Array[@core.Row], col : Int) -> QueryResult {
  let mut found : Double? = None
  for r in rows {
    if col < r.values.length() {
      match value_to_double(r.values[col]) {
        Some(v) =>
          match found {
            None => found = Some(v)
            Some(cur) => if v < cur { found = Some(v) }
          }
        None => ()
      }
    }
  }
  match found {
    Some(v) => NumberResult(v)
    None => NullResult
  }
}

///|
fn agg_max(rows : Array[@core.Row], col : Int) -> QueryResult {
  let mut found : Double? = None
  for r in rows {
    if col < r.values.length() {
      match value_to_double(r.values[col]) {
        Some(v) =>
          match found {
            None => found = Some(v)
            Some(cur) => if v > cur { found = Some(v) }
          }
        None => ()
      }
    }
  }
  match found {
    Some(v) => NumberResult(v)
    None => NullResult
  }
}

///|
fn agg_sum(rows : Array[@core.Row], col : Int) -> QueryResult {
  let mut s = 0.0
  let mut any = false
  for r in rows {
    if col < r.values.length() {
      match value_to_double(r.values[col]) {
        Some(v) => {
          s = s + v
          any = true
        }
        None => ()
      }
    }
  }
  if any {
    NumberResult(s)
  } else {
    NullResult
  }
}
