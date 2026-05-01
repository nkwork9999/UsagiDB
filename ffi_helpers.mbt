// Constructor / Value helpers exposed for JS callers that can't easily build
// MoonBit enum variants directly.

///|
pub fn create_db_default() -> UsagiDB {
  UsagiDB::with_threshold(100)
}

///|
pub fn create_db_with_threshold(threshold : Int) -> UsagiDB {
  UsagiDB::with_threshold(threshold)
}

///|
pub fn value_float(v : Double) -> @core.Value {
  @core.Value::Float(v)
}

///|
pub fn value_string(s : String) -> @core.Value {
  @core.Value::String(s)
}

///|
pub fn value_int(v : Int64) -> @core.Value {
  @core.Value::Int(v)
}
