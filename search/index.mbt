// Minimal inverted-index full-text search. Tokenization is lowercase +
// non-alphanumeric split (no stemming, no stop-word list). Scoring is
// term-frequency-only (no BM25 yet) — enough for the demo, easily upgraded.

///|
pub struct SearchIndex {
  // token → list of (doc_id, term_frequency)
  postings : Map[String, Array[(String, Int)]]
  // doc_id → original raw text (for highlighting / snippet)
  docs : Map[String, String]
}

///|
pub fn SearchIndex::new() -> SearchIndex {
  { postings: Map::new(), docs: Map::new() }
}

///|
fn is_word_char(c : Char) -> Bool {
  let code = c.to_int()
  let digit = code >= 0x30 && code <= 0x39
  let upper = code >= 0x41 && code <= 0x5a
  let lower = code >= 0x61 && code <= 0x7a
  digit || upper || lower
}

///|
fn lowercase_char(c : Char) -> Char {
  let code = c.to_int()
  if code >= 0x41 && code <= 0x5a {
    Char::from_int(code + 32)
  } else {
    c
  }
}

///|
fn tokenize(text : String) -> Array[String] {
  let tokens : Array[String] = []
  let cur = StringBuilder::new()
  let mut has = false
  for ch in text {
    if is_word_char(ch) {
      cur.write_char(lowercase_char(ch))
      has = true
    } else if has {
      tokens.push(cur.to_string())
      cur.reset()
      has = false
    }
  }
  if has {
    tokens.push(cur.to_string())
  }
  tokens
}

///| Index `text` under `doc_id`. Re-indexing the same `doc_id` overwrites.
pub fn SearchIndex::index(
  self : SearchIndex,
  doc_id : String,
  text : String,
) -> Unit {
  // Drop any prior posting for this doc.
  self.remove(doc_id)
  self.docs[doc_id] = text
  let counts : Map[String, Int] = Map::new()
  for tok in tokenize(text) {
    match counts.get(tok) {
      Some(n) => counts[tok] = n + 1
      None => counts[tok] = 1
    }
  }
  for entry in counts {
    let (tok, freq) = entry
    match self.postings.get(tok) {
      Some(list) => list.push((doc_id, freq))
      None => {
        let list : Array[(String, Int)] = []
        list.push((doc_id, freq))
        self.postings[tok] = list
      }
    }
  }
}

///|
pub fn SearchIndex::remove(self : SearchIndex, doc_id : String) -> Unit {
  if self.docs.get(doc_id) is None {
    return
  }
  let _ = self.docs.remove(doc_id)
  for entry in self.postings {
    let (_, list) = entry
    let kept : Array[(String, Int)] = []
    for p in list {
      if p.0 != doc_id {
        kept.push(p)
      }
    }
    list.clear()
    for p in kept {
      list.push(p)
    }
  }
}

///| Search `query` and return `(doc_id, score)` pairs sorted by score desc.
/// Score is the sum of term-frequencies for tokens that match.
pub fn SearchIndex::search(
  self : SearchIndex,
  query : String,
) -> Array[(String, Int)] {
  let qtokens = tokenize(query)
  if qtokens.length() == 0 {
    return []
  }
  let acc : Map[String, Int] = Map::new()
  for tok in qtokens {
    match self.postings.get(tok) {
      None => ()
      Some(list) =>
        for p in list {
          let (doc_id, freq) = p
          match acc.get(doc_id) {
            Some(s) => acc[doc_id] = s + freq
            None => acc[doc_id] = freq
          }
        }
    }
  }
  let result : Array[(String, Int)] = []
  for entry in acc {
    result.push(entry)
  }
  // Insertion sort — input is small for browser-side index.
  let n = result.length()
  for i = 1; i < n; i = i + 1 {
    let mut j = i
    while j > 0 && result[j - 1].1 < result[j].1 {
      let tmp = result[j - 1]
      result[j - 1] = result[j]
      result[j] = tmp
      j = j - 1
    }
  }
  result
}

///| Number of indexed docs.
pub fn SearchIndex::doc_count(self : SearchIndex) -> Int {
  self.docs.size()
}
