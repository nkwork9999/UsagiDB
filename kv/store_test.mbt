///|
test "put_get_replace_delete" {
  let store = KVStore::new()
  store.put("answer", @core.Value::Int(41L))
  store.put("name", @core.Value::String("usagi"))
  store.put("answer", @core.Value::Int(42L))
  inspect(store.size(), content="2")
  inspect(store.contains("answer"), content="true")
  match store.get("answer") {
    Some(@core.Value::Int(value)) => inspect(value, content="42")
    _ => abort("expected integer value")
  }
  let keys = store.keys()
  inspect(keys.length(), content="2")
  inspect(keys[0] == "answer", content="true")
  inspect(keys[1] == "name", content="true")
  inspect(store.delete("answer"), content="true")
  inspect(store.delete("answer"), content="false")
  inspect(store.get("answer") is None, content="true")
}

///|
test "conditional_and_positional_operations" {
  let store = KVStore::new()
  inspect(store.is_empty(), content="true")
  inspect(store.put_if_absent("a", @core.Value::Int(1L)), content="true")
  inspect(store.put_if_absent("a", @core.Value::Int(9L)), content="false")
  inspect(store.replace_existing("a", @core.Value::Int(2L)), content="true")
  inspect(store.replace_existing("missing", @core.Value::Null), content="false")
  store.put("b", @core.Value::String("bee"))
  store.put("c", @core.Value::Int(3L))
  inspect(store.index_of("b"), content="1")
  inspect(store.key_at(2), content="Some(c)")
  inspect(store.key_at(-1), content="None")
  inspect(store.value_at(9), content="None")
  inspect(store.rename("b", "renamed"), content="true")
  inspect(store.rename("renamed", "a"), content="false")
  inspect(store.swap("a", "c"), content="true")
  inspect(store.keys(), content="[c, renamed, a]")
  inspect(store.first().unwrap().key, content="c")
  inspect(store.last().unwrap().key, content="a")
  inspect(store.values().length(), content="3")
  inspect(
    store.get_or("missing", @core.Value::String("fallback")),
    content="String(fallback)",
  )
  inspect(store.take("renamed"), content="Some(String(bee))")
  inspect(store.take("renamed"), content="None")
}

///|
test "prefix_bulk_snapshot_merge_and_clear" {
  let store = KVStore::new()
  store.put("user:1", @core.Value::String("Ada"))
  store.put("cache:1", @core.Value::Int(1L))
  store.put("user:2", @core.Value::String("Lin"))
  store.put("cache:2", @core.Value::Int(2L))
  inspect(store.keys_with_prefix("user:"), content="[user:1, user:2]")
  inspect(store.count_prefix("cache:"), content="2")
  inspect(store.delete_prefix("cache:"), content="2")
  inspect(store.entries_snapshot().length(), content="2")

  let incoming = KVStore::new()
  incoming.put("user:1", @core.Value::String("Grace"))
  incoming.put("user:3", @core.Value::String("Ken"))
  inspect(store.merge_from(incoming), content="2")
  inspect(store.keys(), content="[user:1, user:2, user:3]")
  inspect(store.retain_prefix("user:2"), content="2")
  inspect(store.keys(), content="[user:2]")
  store.clear()
  inspect(store.is_empty(), content="true")
}
