///| Cosine similarity puts the closest vector first.
test "vector_cosine_ranks_closest" {
  let v = VectorStore::new(3)
  let _ = v.insert("a", [1.0, 0.0, 0.0])
  let _ = v.insert("b", [0.0, 1.0, 0.0])
  let _ = v.insert("c", [0.9, 0.1, 0.0])
  let r = v.search([1.0, 0.0, 0.0], 2)
  inspect(r.length(), content="2")
  inspect(r[0].0, content="a")
  inspect(r[1].0, content="c")
}

///| Euclidean orders ascending — smaller distance comes first.
test "vector_euclidean_orders_ascending" {
  let v = VectorStore::new(2, metric=Euclidean)
  let _ = v.insert("near", [1.0, 1.0])
  let _ = v.insert("far", [10.0, 10.0])
  let r = v.search([1.1, 1.1], 2)
  inspect(r[0].0, content="near")
  inspect(r[1].0, content="far")
}

///| Re-insert with the same id replaces the embedding.
test "vector_reinsert_replaces" {
  let v = VectorStore::new(2)
  let _ = v.insert("x", [1.0, 0.0])
  let _ = v.insert("x", [0.0, 1.0])
  inspect(v.size(), content="1")
  let r = v.search([0.0, 1.0], 1)
  inspect(r[0].0, content="x")
}

///| Dimension mismatch is rejected silently.
test "vector_dim_mismatch_rejected" {
  let v = VectorStore::new(3)
  let ok = v.insert("bad", [1.0, 0.0])
  inspect(ok, content="false")
  inspect(v.size(), content="0")
}
