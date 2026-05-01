// ============================================
// Delta Encoding (Compression)
// ============================================

pub fn delta_encode(values : Array[Int64]) -> (Int64, Array[Int64]) {
  if values.length() == 0 {
    return (0L, [])
  }
  
  let base = values[0]
  let deltas : Array[Int64] = []
  
  for i = 1; i < values.length(); i = i + 1 {
    deltas.push(values[i] - values[i - 1])
  }
  
  (base, deltas)
}

pub fn delta_decode(base : Int64, deltas : Array[Int64]) -> Array[Int64] {
  let result : Array[Int64] = [base]
  let mut current = base
  
  for delta in deltas {
    current = current + delta
    result.push(current)
  }
  
  result
}

pub fn compression_ratio(original : Array[Int64], deltas : Array[Int64]) -> Double {
  if original.length() == 0 {
    return 1.0
  }
  
  let mut max_original : Int64 = 0
  for v in original {
    let abs_v = if v < 0L { -v } else { v }
    if abs_v > max_original {
      max_original = abs_v
    }
  }
  
  let mut max_delta : Int64 = 0
  for d in deltas {
    let abs_d = if d < 0L { -d } else { d }
    if abs_d > max_delta {
      max_delta = abs_d
    }
  }
  
  if max_delta == 0L {
    return 10.0
  }
  
  let original_bits = bits_needed(max_original)
  let delta_bits = bits_needed(max_delta)
  
  if delta_bits == 0 {
    10.0
  } else {
    original_bits.to_double() / delta_bits.to_double()
  }
}

fn bits_needed(value : Int64) -> Int {
  if value == 0L {
    return 1
  }
  
  let mut v = if value < 0L { -value } else { value }
  let mut bits = 0
  
  while v > 0L {
    bits = bits + 1
    v = v / 2L
  }
  
  bits
}

