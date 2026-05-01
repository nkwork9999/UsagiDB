// UsagiDB - Minimal Single File Implementation
// Lightweight HTAP Database for Time Series Data
// With Full Serialization/Deserialization Support

// ============================================
// Types
// ============================================

/// Value type for database cells
pub(all) enum Value {
  Null
  Int(Int64)
  Float(Double)
  String(String)
  Timestamp(Int64)
} derive(Show, Eq)

/// A row with timestamp as primary key
pub(all) struct Row {
  ts : Int64
  values : Array[Value]
} derive(Show)

