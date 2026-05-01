///| Index, search, ranked results.
test "search_basic_ranking" {
  let idx = SearchIndex::new()
  idx.index("d1", "The quick brown fox jumps over the lazy dog")
  idx.index("d2", "A quick test of the search engine")
  idx.index("d3", "Slow tortoise wins the race")
  let r = idx.search("quick")
  inspect(r.length(), content="2")
  // d1/d2 both contain "quick" once.
  let r2 = idx.search("quick test")
  inspect(r2.length(), content="2")
  inspect(r2[0].0, content="d2") // d2 has both terms → higher score
}

///| Re-indexing replaces the prior posting.
test "search_reindex_overwrites" {
  let idx = SearchIndex::new()
  idx.index("d1", "alpha beta")
  idx.index("d1", "gamma delta")
  inspect(idx.search("alpha").length(), content="0")
  inspect(idx.search("gamma").length(), content="1")
}

///| Removing a doc drops it from postings.
test "search_remove" {
  let idx = SearchIndex::new()
  idx.index("d1", "hello world")
  idx.index("d2", "hello there")
  inspect(idx.search("hello").length(), content="2")
  idx.remove("d1")
  inspect(idx.search("hello").length(), content="1")
  inspect(idx.doc_count(), content="1")
}

///| Tokenizer is lowercase and ignores punctuation.
test "search_case_and_punct" {
  let idx = SearchIndex::new()
  idx.index("d1", "Hello, World!")
  inspect(idx.search("hello").length(), content="1")
  inspect(idx.search("WORLD").length(), content="1")
}
