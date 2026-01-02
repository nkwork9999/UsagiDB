# 🐰 UsagiDB

A lightweight time-series database implemented in MoonBit. Runs in the browser.

## Features

- **HTAP Architecture**: DeltaStore (fast writes) + MainStore (compressed chunks)
- **Delta Encoding**: Efficient timestamp compression
- **Snapshots**: Time-travel query support
- **JSON Serialization**: Data persistence and restoration
- **Changelog**: Operation history for sync and auditing

## Demo

https://nkwork9999.github.io/usagidb/

## Usage

### Browser

```html
<script src="./target/js/release/build/cmd/main/main.js"></script>
<script>
  // Create DB (threshold: compaction threshold)
  const db = UsagiDB.create(50);

  // Insert data
  const ts = UsagiDB.toInt64(Date.now() % 2147483647);
  UsagiDB.insert(db, ts, [
    new UsagiDB.Float(25.5),
    new UsagiDB.String("sensor-1"),
  ]);

  // Scan
  const start = { hi: 0, lo: 0 };
  const end = { hi: 0x7fffffff, lo: -1 };
  const rows = UsagiDB.scan(db, start, end);

  // Stats
  console.log(UsagiDB.stats(db));

  // Serialize / Deserialize
  const json = UsagiDB.serialize(db);
  const restored = UsagiDB.deserialize(json);
</script>
```

### API

| Function                         | Description       |
| -------------------------------- | ----------------- |
| `UsagiDB.create(threshold)`      | Create database   |
| `UsagiDB.insert(db, ts, values)` | Insert data       |
| `UsagiDB.scan(db, start, end)`   | Range scan        |
| `UsagiDB.stats(db)`              | Get statistics    |
| `UsagiDB.serialize(db)`          | Serialize to JSON |
| `UsagiDB.deserialize(json)`      | Restore from JSON |
| `UsagiDB.compact(db)`            | Manual compaction |

### Value Types

| Constructor             | Usage           |
| ----------------------- | --------------- |
| `new UsagiDB.Float(n)`  | Floating point  |
| `new UsagiDB.String(s)` | String          |
| `new UsagiDB.Int(n)`    | Integer (Int64) |
| `UsagiDB.Null`          | NULL value      |

## Build

```bash
# Requires MoonBit CLI
moon build --target js
```

Output: `target/js/release/build/cmd/main/main.js`

## Architecture

```
┌─────────────────────────────────────────┐
│              UsagiDB                    │
├─────────────┬─────────────┬─────────────┤
│ DeltaStore  │  MainStore  │  DeleteSet  │
│ (new data)  │ (compressed)│(deleted ts) │
├─────────────┴─────────────┴─────────────┤
│              Snapshots                  │
│        (point-in-time recovery)         │
├─────────────────────────────────────────┤
│              ChangeLog                  │
│         (operation history)             │
└─────────────────────────────────────────┘
```

## License

MIT License
