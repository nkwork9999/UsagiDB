# 🐰 UsagiDB

Multi-modal embedded database in MoonBit. Runs in the browser.

**🌐 Live demo:** https://nkwork9999.github.io/UsagiDB/  
**🌊 Realtime canvas chart:** https://nkwork9999.github.io/UsagiDB/web/

| Mode | Role |
|---|---|
| **`ts`** | HTAP time-series (DeltaStore + MainStore + retention + continuous aggregates) |
| **`stream`** | Realtime compaction (KeepLastN / Downsample-OHLC / DeadBand / ExceptionBased / RateLimit) |
| **`log`** | Kafka-like topics + consumer groups + retention + JSON snapshot |
| **`search`** | Inverted-index full-text search |
| **`vector`** | Brute-force k-NN (Cosine / Dot / Euclidean) |
| **`sql`** | Typed query builder over `ts` (SELECT/WHERE/AGG) |

Plus: CRDT (LWW + VectorClock + LamportClock), conflict-resolution policies (LWW / FWW / Max / Min / PreferSite), Shape-based subscriptions, JSON SyncPacket wire format.

## Demo

**Live:** https://nkwork9999.github.io/UsagiDB/

- Main demo: 4 panels (`ts` / `stream` / `log` / sync) with BroadcastChannel + OPFS toggles.
- Realtime canvas chart at [/web/](https://nkwork9999.github.io/UsagiDB/web/) — smooth-scrolling OHLC + sensor pane (jellyfish_moon-based).

## Run locally

```bash
git clone https://github.com/nkwork9999/UsagiDB
cd UsagiDB
moon build --target js
python3 -m http.server 8765
# open http://localhost:8765/
```

OPFS, Service Worker, and BroadcastChannel all need a normal HTTP origin (localhost or HTTPS). Don't open `index.html` directly via `file://`.

## Quickstart (browser)

```html
<script type="module">
  import {
    create,
    to_int64, value_float, value_string,
    insert, scan, stats, serialize, deserialize,
    stream_keep_last_n, stream_downsample_ohlc, stream_dead_band,
    stream_put, stream_query,
    log_enable, log_produce_string, log_subscribe, log_poll, log_list_topics,
    log_serialize, log_deserialize,
    sync_pull, sync_apply, sync_local_seq, sync_pull_range,
    stream_serialize, stream_restore,
  } from "./target/js/release/build/cmd/main/main.js";

  // ts mode — HTAP time-series
  const db = create(50);
  insert(db, to_int64(Date.now() % 2_147_483_647),
    [value_float(25.5), value_string("sensor-1")]);
  const rows = scan(db, to_int64(0), to_int64(2_147_483_647));
  console.log(stats(db));

  // stream mode — realtime compaction (in-memory)
  stream_downsample_ohlc(db, "price", to_int64(1000));   // 1s OHLC bucket
  stream_put(db, "price", 100.0, to_int64(0));
  stream_query(db, "price"); // → [{$tag, ...}] Point or Candle

  // log mode — Kafka-like
  log_enable(db);
  log_subscribe(db, "events", "consumer-A");
  log_produce_string(db, "events", "evt-1", "hello", to_int64(0));
  const records = log_poll(db, "events", "consumer-A", 10);

  // sync — pull/apply JSON SyncPackets over WebSocket / WebRTC / etc.
  const packet = sync_pull(db, to_int64(0));
  // → ws.send(packet); on the other side: sync_apply(db2, packet);
</script>
```

## Module map

```
UsagiDB/
├── core/      Value, Row, ChangeLog, Sync, CRDT, Filter, TimeUnit, JSON, Shape
├── ts/        HTAP store + retention + continuous aggregates + CRDT wiring + Shape pull
├── stream/    Realtime compaction (formerly jellyfish_moon)
├── log/       Kafka-like topics + consumer groups + bridge to stream
├── search/    Inverted-index FTS
├── vector/    Brute-force k-NN
├── sql/       Typed query builder
├── lib.mbt    Umbrella UsagiDB struct + facade methods
├── cmd/main/  CLI demo + JS exports for index.html
├── cmd/web/   Canvas chart entry (separate JS bundle)
├── index.html 4-panel demo (ts/stream/log/sync)
├── web/       Realtime canvas chart
└── sw.js      Service Worker for offline outbox drain
```

## Edge / sync features

- **Conflict resolution**: `LastWriteWins` / `FirstWriteWins` / `MaxValue` / `MinValue` / `PreferSite(id)` — pick when calling `merge_crdt_with`.
- **Shape subscription**: `Shape::time_range(lo, hi)` lets a peer pull only its slice of the data, ElectricSQL-style.
- **OPFS persistence**: switchable per-mode JSON snapshots saved to OPFS — survives tab restarts.
- **BroadcastChannel**: same-origin cross-tab pub/sub for `log` produce events and `ts` SyncPackets.
- **Service Worker** (`sw.js`): drains a localStorage outbox of failed pushes when the tab regains connectivity (registers a Background Sync tag on Chromium; falls back to `window.online`).
- **Stream bridge**: `db.log_to_stream(topic, group, stream_key)` projects log records into the in-memory stream view.

## Build & test

```bash
moon check --target js     # type-check
moon build --target js     # produces target/js/release/build/{cmd/main, cmd/web}/*.js
moon test  --target js     # 60+ tests across all packages
moon fmt                   # format
```

`wasm-gc` target is *not* supported — `extern "js"` FFI is JS-only.

## Build via CI / GitHub Pages

Pushing to `main` runs [.github/workflows/pages.yml](./.github/workflows/pages.yml) which:

1. Installs MoonBit, runs `moon build --target js`.
2. Stages `index.html`, `sw.js`, `web/`, and `target/js/release/build/` into `_site/`.
3. Deploys via `actions/deploy-pages`.

To enable: GitHub repo → **Settings → Pages → Source: `GitHub Actions`** (one-time).

## v0.2 features (vs original v0.1)

- CRDT primitives in `core/` (LamportClock / VectorClock / LWWValue / CRDTRow) — fully wired into `ts/insert`, `ts/delete`, and `SyncPacket`.
- `RetentionPolicy` (time-based row deletion) and `ContinuousAggregate` (named pre-computed bucket aggregates) on `ts`.
- `FillMethod` for gap-filling scans (`Null` / `Previous` / `Next` / `Linear` / `Constant`).
- Per-key `CompactionTrigger` on `stream` (`EveryN` / `EveryDuration` / `OnRead` / `Manual`).

## Architecture (v0.2 internal layout for `ts` mode)

```
┌─────────────────────────────────────────────┐
│             UsagiDB (umbrella)              │
│   { ts?, stream?, log?, search?, vector? }  │
├─────────────────────────────────────────────┤
│  ts mode: TimeSeriesStore                   │
│  ┌────────────┬────────────┬────────────┐   │
│  │ DeltaStore │ MainStore  │ DeleteSet  │   │
│  │ (writes)   │(compressed)│(tombstone) │   │
│  └────────────┴────────────┴────────────┘   │
│  Snapshots (time-travel)                    │
│  ChangeLog (operation history)              │
│  RetentionPolicy + ContinuousAggregate     │
│  CRDTRow + LamportClock + VectorClock       │
└─────────────────────────────────────────────┘
```

## License

MPL-2.0
