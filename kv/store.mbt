// In-memory key/value mode. Array-backed storage keeps iteration order stable
// and avoids target-specific hash behaviour for small embedded datasets.

///|
pub(all) struct KVEntry {
  key : String
  value : @core.Value
}

///|
pub struct KVStore {
  entries : Array[KVEntry]
}

///|
pub fn KVStore::new() -> KVStore {
  { entries: [] }
}

///|
/// Insert or replace a value. Replacing a key preserves its position.
pub fn KVStore::put(self : KVStore, key : String, value : @core.Value) -> Unit {
  for i = 0; i < self.entries.length(); i = i + 1 {
    if self.entries[i].key == key {
      self.entries[i] = { key, value }
      return
    }
  }
  self.entries.push({ key, value })
}

///|
pub fn KVStore::get(self : KVStore, key : String) -> @core.Value? {
  for entry in self.entries {
    if entry.key == key {
      return Some(entry.value)
    }
  }
  None
}

///|
pub fn KVStore::delete(self : KVStore, key : String) -> Bool {
  for i = 0; i < self.entries.length(); i = i + 1 {
    if self.entries[i].key == key {
      let _ = self.entries.remove(i)
      return true
    }
  }
  false
}

///|
pub fn KVStore::contains(self : KVStore, key : String) -> Bool {
  self.get(key) is Some(_)
}

///|
pub fn KVStore::size(self : KVStore) -> Int {
  self.entries.length()
}

///|
/// Return keys in stable insertion order.
pub fn KVStore::keys(self : KVStore) -> Array[String] {
  self.entries.map(fn(entry) { entry.key })
}

///|
pub fn KVStore::is_empty(self : KVStore) -> Bool {
  self.entries.length() == 0
}

///|
pub fn KVStore::values(self : KVStore) -> Array[@core.Value] {
  self.entries.map(fn(entry) { entry.value })
}

///|
/// Return a stable snapshot that callers can inspect without mutating the store.
pub fn KVStore::entries_snapshot(self : KVStore) -> Array[KVEntry] {
  self.entries.map(fn(entry) { { key: entry.key, value: entry.value } })
}

///|
pub fn KVStore::get_or(
  self : KVStore,
  key : String,
  fallback : @core.Value,
) -> @core.Value {
  match self.get(key) {
    Some(value) => value
    None => fallback
  }
}

///|
/// Insert only when the key is absent.
pub fn KVStore::put_if_absent(
  self : KVStore,
  key : String,
  value : @core.Value,
) -> Bool {
  if self.contains(key) {
    false
  } else {
    self.entries.push({ key, value })
    true
  }
}

///|
/// Replace only when the key already exists.
pub fn KVStore::replace_existing(
  self : KVStore,
  key : String,
  value : @core.Value,
) -> Bool {
  for i = 0; i < self.entries.length(); i = i + 1 {
    if self.entries[i].key == key {
      self.entries[i] = { key, value }
      return true
    }
  }
  false
}

///|
/// Remove a key and return its previous value.
pub fn KVStore::take(self : KVStore, key : String) -> @core.Value? {
  for i = 0; i < self.entries.length(); i = i + 1 {
    if self.entries[i].key == key {
      let value = self.entries[i].value
      let _ = self.entries.remove(i)
      return Some(value)
    }
  }
  None
}

///|
pub fn KVStore::clear(self : KVStore) -> Unit {
  while self.entries.length() > 0 {
    let _ = self.entries.remove(self.entries.length() - 1)
  }
}

///|
pub fn KVStore::first(self : KVStore) -> KVEntry? {
  if self.entries.length() == 0 {
    None
  } else {
    let entry = self.entries[0]
    Some({ key: entry.key, value: entry.value })
  }
}

///|
pub fn KVStore::last(self : KVStore) -> KVEntry? {
  if self.entries.length() == 0 {
    None
  } else {
    let entry = self.entries[self.entries.length() - 1]
    Some({ key: entry.key, value: entry.value })
  }
}

///|
pub fn KVStore::key_at(self : KVStore, index : Int) -> String? {
  if index < 0 || index >= self.entries.length() {
    None
  } else {
    Some(self.entries[index].key)
  }
}

///|
pub fn KVStore::value_at(self : KVStore, index : Int) -> @core.Value? {
  if index < 0 || index >= self.entries.length() {
    None
  } else {
    Some(self.entries[index].value)
  }
}

///|
pub fn KVStore::index_of(self : KVStore, key : String) -> Int {
  for i = 0; i < self.entries.length(); i = i + 1 {
    if self.entries[i].key == key {
      return i
    }
  }
  -1
}

///|
/// Rename in place, preserving order. Existing destinations are rejected.
pub fn KVStore::rename(self : KVStore, from : String, to : String) -> Bool {
  if from == to {
    return self.contains(from)
  }
  if self.contains(to) {
    return false
  }
  let index = self.index_of(from)
  if index < 0 {
    false
  } else {
    let value = self.entries[index].value
    self.entries[index] = { key: to, value }
    true
  }
}

///|
/// Exchange two keys without changing any other position.
pub fn KVStore::swap(self : KVStore, left : String, right : String) -> Bool {
  let left_index = self.index_of(left)
  let right_index = self.index_of(right)
  if left_index < 0 || right_index < 0 {
    false
  } else {
    let left_entry = self.entries[left_index]
    let right_entry = self.entries[right_index]
    self.entries[left_index] = right_entry
    self.entries[right_index] = left_entry
    true
  }
}

///|
pub fn KVStore::keys_with_prefix(
  self : KVStore,
  prefix : String,
) -> Array[String] {
  let matches : Array[String] = []
  for entry in self.entries {
    if entry.key.has_prefix(prefix) {
      matches.push(entry.key)
    }
  }
  matches
}

///|
pub fn KVStore::count_prefix(self : KVStore, prefix : String) -> Int {
  let mut count = 0
  for entry in self.entries {
    if entry.key.has_prefix(prefix) {
      count = count + 1
    }
  }
  count
}

///|
/// Delete all matching keys and return the number removed.
pub fn KVStore::delete_prefix(self : KVStore, prefix : String) -> Int {
  let mut removed = 0
  let mut index = 0
  while index < self.entries.length() {
    if self.entries[index].key.has_prefix(prefix) {
      let _ = self.entries.remove(index)
      removed = removed + 1
    } else {
      index = index + 1
    }
  }
  removed
}

///|
/// Keep only matching keys and return the number removed.
pub fn KVStore::retain_prefix(self : KVStore, prefix : String) -> Int {
  let before = self.entries.length()
  let mut index = 0
  while index < self.entries.length() {
    if self.entries[index].key.has_prefix(prefix) {
      index = index + 1
    } else {
      let _ = self.entries.remove(index)
    }
  }
  before - self.entries.length()
}

///|
/// Merge another snapshot. Existing values are replaced in place and new keys
/// are appended in source order. Returns the number of processed entries.
pub fn KVStore::merge_from(self : KVStore, other : KVStore) -> Int {
  let snapshot = other.entries_snapshot()
  for entry in snapshot {
    self.put(entry.key, entry.value)
  }
  snapshot.length()
}
