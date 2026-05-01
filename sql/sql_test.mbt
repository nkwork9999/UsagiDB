///| Time-range filter narrows the result set.
test "query_time_range" {
  let db = @ts.TimeSeriesStore::with_threshold(50)
  let _ = db.insert(0L, [@core.Value::Float(1.0)])
  let _ = db.insert(100L, [@core.Value::Float(2.0)])
  let _ = db.insert(500L, [@core.Value::Float(3.0)])
  let _ = db.insert(1000L, [@core.Value::Float(4.0)])
  let q = Query::from_ts().where_time_between(50L, 600L).select_count()
  match q.execute(db) {
    CountResult(n) => inspect(n, content="2")
    _ => abort("expected count")
  }
}

///| AVG on numeric column.
test "query_avg" {
  let db = @ts.TimeSeriesStore::with_threshold(50)
  let _ = db.insert(0L, [@core.Value::Float(10.0)])
  let _ = db.insert(100L, [@core.Value::Float(20.0)])
  let _ = db.insert(200L, [@core.Value::Float(30.0)])
  let q = Query::from_ts().select_avg(0)
  match q.execute(db) {
    NumberResult(v) => inspect(v, content="20")
    _ => abort("expected number")
  }
}

///| Column equality filter combined with time range.
test "query_col_eq_filter" {
  let db = @ts.TimeSeriesStore::with_threshold(50)
  let _ = db.insert(0L, [@core.Value::Float(20.0), @core.Value::String("a")])
  let _ = db.insert(100L, [@core.Value::Float(21.0), @core.Value::String("b")])
  let _ = db.insert(200L, [@core.Value::Float(22.0), @core.Value::String("a")])
  let q = Query::from_ts()
    .where_col_eq(1, @core.Value::String("a"))
    .select_count()
  match q.execute(db) {
    CountResult(n) => inspect(n, content="2")
    _ => abort("expected count")
  }
}

///| MAX/MIN/SUM run over numeric columns.
test "query_min_max_sum" {
  let db = @ts.TimeSeriesStore::with_threshold(50)
  let _ = db.insert(0L, [@core.Value::Int(5L)])
  let _ = db.insert(100L, [@core.Value::Int(2L)])
  let _ = db.insert(200L, [@core.Value::Int(8L)])
  let qmax = Query::from_ts().select_max(0)
  let qmin = Query::from_ts().select_min(0)
  let qsum = Query::from_ts().select_sum(0)
  match qmax.execute(db) {
    NumberResult(v) => inspect(v, content="8")
    _ => abort("expected max")
  }
  match qmin.execute(db) {
    NumberResult(v) => inspect(v, content="2")
    _ => abort("expected min")
  }
  match qsum.execute(db) {
    NumberResult(v) => inspect(v, content="15")
    _ => abort("expected sum")
  }
}
