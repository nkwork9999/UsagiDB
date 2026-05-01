// Vector store — brute-force cosine/dot/euclidean search. Suitable for
// up to ~10K vectors in browser memory; for larger sets, plug in HNSW
// (hnswlib-wasm) externally and use this only for offset/key bookkeeping.

///|
pub(all) enum DistanceMetric {
  Cosine
  Dot
  Euclidean
} derive(Show, Eq)

///|
pub struct VectorRecord {
  id : String
  embedding : Array[Double]
  metadata : @core.Value
} derive(Show)

///|
pub struct VectorStore {
  dim : Int
  metric : DistanceMetric
  records : Array[VectorRecord]
}

///| New empty store with the given embedding dimension and metric.
pub fn VectorStore::new(
  dim : Int,
  metric~ : DistanceMetric = Cosine,
) -> VectorStore {
  { dim, metric, records: [] }
}

///| Add a record. Mismatched dim is silently ignored — caller should validate.
pub fn VectorStore::insert(
  self : VectorStore,
  id : String,
  embedding : Array[Double],
  metadata~ : @core.Value = @core.Value::Null,
) -> Bool {
  if embedding.length() != self.dim {
    return false
  }
  // Dedupe: replace existing record with same id.
  for i = 0; i < self.records.length(); i = i + 1 {
    if self.records[i].id == id {
      self.records[i] = { id, embedding, metadata }
      return true
    }
  }
  self.records.push({ id, embedding, metadata })
  true
}

///|
pub fn VectorStore::remove(self : VectorStore, id : String) -> Bool {
  for i = 0; i < self.records.length(); i = i + 1 {
    if self.records[i].id == id {
      let _ = self.records.remove(i)
      return true
    }
  }
  false
}

///|
pub fn VectorStore::size(self : VectorStore) -> Int {
  self.records.length()
}

///|
fn dot(a : Array[Double], b : Array[Double]) -> Double {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  let mut s = 0.0
  for i = 0; i < n; i = i + 1 {
    s = s + a[i] * b[i]
  }
  s
}

///|
fn norm(a : Array[Double]) -> Double {
  let mut s = 0.0
  for v in a {
    s = s + v * v
  }
  if s <= 0.0 { 0.0 } else { s.sqrt() }
}

///|
fn euclid(a : Array[Double], b : Array[Double]) -> Double {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  let mut s = 0.0
  for i = 0; i < n; i = i + 1 {
    let d = a[i] - b[i]
    s = s + d * d
  }
  s.sqrt()
}

///| `score` is "higher is better" for Cosine/Dot, "lower is better" for
/// Euclidean. The returned array is sorted such that index 0 is the closest
/// match for whichever metric was configured.
pub fn VectorStore::search(
  self : VectorStore,
  query : Array[Double],
  k : Int,
) -> Array[(String, Double)] {
  if query.length() != self.dim {
    return []
  }
  let scored : Array[(String, Double)] = []
  let q_norm = norm(query)
  for r in self.records {
    let s = match self.metric {
      Cosine => {
        let n = norm(r.embedding) * q_norm
        if n <= 0.0 { 0.0 } else { dot(query, r.embedding) / n }
      }
      Dot => dot(query, r.embedding)
      Euclidean => euclid(query, r.embedding)
    }
    scored.push((r.id, s))
  }
  // Insertion sort (k typically small, n up to ~10K).
  let n = scored.length()
  let descending = match self.metric {
    Euclidean => false
    _ => true
  }
  for i = 1; i < n; i = i + 1 {
    let mut j = i
    while j > 0 {
      let swap = if descending {
        scored[j - 1].1 < scored[j].1
      } else {
        scored[j - 1].1 > scored[j].1
      }
      if not(swap) {
        break
      }
      let tmp = scored[j - 1]
      scored[j - 1] = scored[j]
      scored[j] = tmp
      j = j - 1
    }
  }
  // Truncate to k.
  let take = if k < scored.length() { k } else { scored.length() }
  let out : Array[(String, Double)] = []
  for i = 0; i < take; i = i + 1 {
    out.push(scored[i])
  }
  out
}
