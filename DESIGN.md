# UsagiDB Module Design

## 目的

UsagiDBを単一機能のTS-DBから、**複数のストレージモードを束ねる傘パッケージ**に再編する。
今のTS-DB機能は `ts` モードとして1つのモードに格下げし、将来 `kv`, `stream`, `vector` 等の
別モードを並列に足せる構造にする。

## モジュール構成

```
UsagiDB/
├── moon.mod.json                ← name: nkwork9999/usagidb
├── moon.pkg.json                ← root: imports core + ts
├── lib.mbt                      ← 傘 UsagiDB struct + facade methods
├── core/                        ← どのモードでも使う共通プリミティブ
│   ├── moon.pkg.json
│   ├── value.mbt                ← Value, Row
│   ├── delta.mbt                ← delta_encode/decode/compression_ratio
│   ├── time_unit.mbt            ← TimeUnit
│   ├── filter.mbt               ← Filter (WHERE)
│   ├── changelog.mbt            ← Operation, ChangeLogEntry, ChangeLog
│   ├── sync.mbt                 ← SyncState, SyncResult, SyncPacket
│   └── json.mbt                 ← JsonValue, JsonParser (汎用、UsagiDB非依存)
├── ts/                          ← 時系列モード (現UsagiDB相当)
│   ├── moon.pkg.json            ← imports core
│   ├── chunk.mbt                ← CompressedChunk, Chunk
│   ├── delta_store.mbt          ← DeltaStore
│   ├── main_store.mbt           ← MainStore
│   ├── delete_set.mbt           ← DeleteSet
│   ├── snapshot.mbt             ← Snapshot
│   ├── aggregate.mbt            ← AggResult, AggType, sum/avg/...
│   ├── downsample.mbt           ← downsample_*
│   ├── store.mbt                ← TimeSeriesStore (中核)
│   ├── serialize.mbt            ← TS-DB → JSON
│   └── deserialize.mbt          ← JSON → TS-DB
└── cmd/main/                    ← demo + JS exports
```

## モード追加時の指針

**core に置くもの**：
- 複数モードで使う型（Value, Row）
- 同期/監査系（ChangeLog, Sync）— モード非依存にしておけば全モードに自動で適用
- 汎用エンコード（delta, JSON）

**個別モードに置くもの**：
- そのモード固有のストレージ構造（Chunk, DeltaStore等）
- そのモード固有のクエリ/集約

## 傘 UsagiDB API

```moonbit
pub struct UsagiDB {
  ts : @ts.TimeSeriesStore?
  // 将来:
  // kv : @kv.KVStore?
  // stream : @stream.StreamStore?
}

pub fn UsagiDB::new() -> UsagiDB { { ts: None } }

pub fn UsagiDB::enable_ts(self : UsagiDB, threshold? : Int = 100) -> UsagiDB {
  { ..self, ts: Some(@ts.TimeSeriesStore::with_threshold(threshold)) }
}

// 後方互換ショートカット — 旧 UsagiDB::with_threshold(t) ユーザ向け
pub fn UsagiDB::with_threshold(threshold : Int) -> UsagiDB {
  UsagiDB::new().enable_ts(threshold)
}
```

## v0.1分割では何をしないか

- (1) v0.2機能（CRDT/Retention/ContinuousAggregate）の取り込み — 別ステップ
- 真の傘API化（`db.ts.insert(...)` 形式） — ts専用facadeメソッド (`db.insert(...)`) を残してinternalにts呼び出し
- KV/stream/vector など他モードの実装 — 後続

## 実行順序（(2) v0.1分割）

### Step 1: ファイル単位で分割（同一パッケージ内）
1ファイル2098行を10ファイル前後に section コメントベースで分ける。
パッケージ境界は変えないので import 不要、API変更なし。
→ 各ファイルに何が入るかが視覚的に固まる、後の移動コストが下がる

### Step 2: `core/` を切り出し
共通プリミティブを `core/` に移動。`moon.pkg.json` を作り、
crossing する型 (Value enum等) を `pub(all)` にする。
ts側の参照を `@core.Value` に書き換え。

### Step 3: `ts/` を切り出し
TS-DB固有コードを `ts/` に移動。`core` を import。
TimeSeriesStore（旧UsagiDB）が `ts.TimeSeriesStore` になる。

### Step 4: root に傘 UsagiDB
`lib.mbt` で薄い facade を作る。`cmd/main` を更新して新APIを使う。

各ステップで `moon test --target js` を通す。失敗したら巻き戻し。

## 検証ポイント

- 各ステップで JS target の build 成功
- ファイル削除/移動は `git mv` ではなく内容を新ファイルに書いた上で旧ファイル削除（commit前なので問題なし）
- `pub(all)` 化が必要なのは：Value, Operation, SyncResult, Filter, TimeUnit, AggResult, AggType（パッケージ境界を越える enum コンストラクタ使用箇所）
- 各 .mbt は section header コメントを残す（grep可能性維持）

## 既知の留保事項（このフェーズでは触らない）

- README/index.html と `js_*` exports の API 不整合（HTML側 `UsagiDB.create(50)` vs 実装 `js_create_db()`）
- v0.2 ドラフト機能
- テスト不足（fib/sumスタブ削除済、業務ロジックのテストは皆無）
