// ============================================
// Filter (WHERE clause)
// ============================================

pub(all) enum Filter {
  Eq(Int, Value)
  Ne(Int, Value)
  Gt(Int, Value)
  Gte(Int, Value)
  Lt(Int, Value)
  Lte(Int, Value)
  And(Filter, Filter)
  Or(Filter, Filter)
  Not(Filter)
  True
} derive(Show)

fn compare_values(a : Value, b : Value) -> Int {
  match (a, b) {
    (Value::Int(x), Value::Int(y)) => {
      if x < y { -1 } else if x > y { 1 } else { 0 }
    }
    (Value::Float(x), Value::Float(y)) => {
      if x < y { -1 } else if x > y { 1 } else { 0 }
    }
    (Value::Int(x), Value::Float(y)) => {
      let xf = x.to_double()
      if xf < y { -1 } else if xf > y { 1 } else { 0 }
    }
    (Value::Float(x), Value::Int(y)) => {
      let yf = y.to_double()
      if x < yf { -1 } else if x > yf { 1 } else { 0 }
    }
    (Value::String(x), Value::String(y)) => {
      if x < y { -1 } else if x > y { 1 } else { 0 }
    }
    _ => 0
  }
}

pub fn Filter::matches(self : Filter, row : Row) -> Bool {
  match self {
    Filter::True => true
    Filter::Eq(col, val) => {
      if col < row.values.length() {
        row.values[col] == val
      } else {
        false
      }
    }
    Filter::Ne(col, val) => {
      if col < row.values.length() {
        row.values[col] != val
      } else {
        true
      }
    }
    Filter::Gt(col, val) => {
      if col < row.values.length() {
        compare_values(row.values[col], val) > 0
      } else {
        false
      }
    }
    Filter::Gte(col, val) => {
      if col < row.values.length() {
        compare_values(row.values[col], val) >= 0
      } else {
        false
      }
    }
    Filter::Lt(col, val) => {
      if col < row.values.length() {
        compare_values(row.values[col], val) < 0
      } else {
        false
      }
    }
    Filter::Lte(col, val) => {
      if col < row.values.length() {
        compare_values(row.values[col], val) <= 0
      } else {
        false
      }
    }
    Filter::And(f1, f2) => f1.matches(row) && f2.matches(row)
    Filter::Or(f1, f2) => f1.matches(row) || f2.matches(row)
    Filter::Not(f) => !f.matches(row)
  }
}

