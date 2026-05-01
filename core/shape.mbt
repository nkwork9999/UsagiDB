// Shape — a subscription predicate for incremental sync. Inspired by
// ElectricSQL's shape-based subscriptions: clients subscribe to a "slice" of
// the data and only receive changes that intersect with it.
//
// Today the predicate is two-dimensional: a closed time range plus an
// optional column filter. Either dimension may be `None` to match anything.

///|
pub(all) struct Shape {
  ts_min : Int64?
  ts_max : Int64?
  filter : Filter?
} derive(Show)

///| All-pass shape — matches every row.
pub fn Shape::all() -> Shape {
  { ts_min: None, ts_max: None, filter: None }
}

///| Time-range shape: matches rows whose `ts` is within `[lo, hi]` (inclusive).
pub fn Shape::time_range(lo : Int64, hi : Int64) -> Shape {
  { ts_min: Some(lo), ts_max: Some(hi), filter: None }
}

///| Filter-only shape: matches any row whose values satisfy `f`.
pub fn Shape::with_filter(f : Filter) -> Shape {
  { ts_min: None, ts_max: None, filter: Some(f) }
}

///| Combined shape: time range AND filter must both match.
pub fn Shape::and_filter(self : Shape, f : Filter) -> Shape {
  { ..self, filter: Some(f) }
}

///| Test whether a `Row` falls inside the shape.
pub fn Shape::matches_row(self : Shape, row : Row) -> Bool {
  match self.ts_min {
    Some(lo) => if row.ts < lo { return false }
    None => ()
  }
  match self.ts_max {
    Some(hi) => if row.ts > hi { return false }
    None => ()
  }
  match self.filter {
    Some(f) => if not(f.matches(row)) { return false }
    None => ()
  }
  true
}

///| Test whether a `ChangeLogEntry` falls inside the shape. Inserts use the
/// row predicate; deletes match if the deleted-ts is within the time range
/// (filter doesn't apply since we don't have the row anymore).
pub fn Shape::matches_entry(self : Shape, entry : ChangeLogEntry) -> Bool {
  match entry.op {
    Insert(row) => self.matches_row(row)
    Delete(ts) => {
      match self.ts_min {
        Some(lo) => if ts < lo { return false }
        None => ()
      }
      match self.ts_max {
        Some(hi) => if ts > hi { return false }
        None => ()
      }
      true
    }
  }
}
