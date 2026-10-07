# アーキテクチャ

## 全体

```
┌──────────────── iPhone ────────────────┐        ┌──────── 自分のサーバー ────────┐
│ Taiken (アプリ層 / Swift 5 + SwiftUI)   │        │ Backend (Node.js + TypeScript) │
│  Views ─ AppDependencies (組み立て)     │        │  HTTP: 認証・レート制御・期限    │
│  SwiftData / EventKit / CoreLocation    │ HTTPS  │  入力の許可リスト化             │
│  Keychain / UserNotifications / BGTask  │ ─────▶ │  Engine: 予算・遮断器・同時数   │
│            │ ports (protocol)           │ Bearer │   ├ 下調べ (必要時Web検索)       │──▶ Anthropic API
│ TaikenCore (中核 / Swift 6)             │        │   ├ 体験生成 / 会話 (tool use)   │
│  ViewModels・通信・送信内容の組み立て     │        │   ├ 正規化・安全確認・通知判断   │
│  通知判断・傾向計算・端末内の簡易生成     │        │   └ 失敗時はモックで代替生成     │
└─────────────────────────────────────────┘        └───────────────────────────────┘
```

- **iOS → 自分のBackend → AI API** (指示書 §4)。AIのAPIキーはBackendの環境変数にだけ存在する。
- **契約**は `contracts/openapi.json`。両側のテストが同じフィクスチャで検証する。

## iOS の層

| 層 | 依存 | 役割 | 検証 |
|---|---|---|---|
| `TaikenCore` (Swift Package) | Foundation, Observation のみ | API型、BackendClient、ContextBuilder/Assembler、Home/Chat/History/Settings の ViewModel、通知判断、傾向計算、端末内の簡易生成 | `swift test` (Linux / macOS)、Swift 6 言語モード |
| `Taiken` (アプリ) | SwiftUI, SwiftData, EventKit, CoreLocation, Security, UserNotifications, BackgroundTasks | Port の実装 (アダプタ)、画面、依存の組み立て | Xcode (シミュレータ) |

中核は端末機能を `Ports.swift` のプロトコル越しにしか使わない。テストとプレビューは `InMemoryAdapters.swift` に差し替える。
これにより、画面以外のほぼすべての振る舞いを Apple 以外の環境でも自動テストできる。

## 体験生成の流れ

1. `ContextAssembler` が、ユーザーが許可した情報だけを集める (予定は時間とタイトルのみ・終了済みは除外・最大8件、地域は市区町村名のみ、会話は直近の数件を6時間だけメモリに保持)。
2. `PreferenceTrends` が履歴から「最近の反応の傾向」を計算する (14日の半減期、材料が少ないタグや半々のタグは送らない)。
3. Backend の `sanitize` が許可リスト方式で入力を組み直す (未知のフィールドは捨てる)。
4. Engine が予算 → 同時実行数 → 遮断器を確認。だめならAIを呼ばずにモックで代替生成し、`fallback_reason` を付ける。
5. ユーザーが許可し、サーバーで有効なら、**下調べ**でAIに「外部情報が必要か」を判断させる。必要なときだけ `web_search` を使い、要約と参照URLだけを取り出す。検索段には発言や予定のタイトルを渡さない。
6. **体験生成**は `propose_experience` ツールを強制して構造化JSONだけを受け取る。
7. 正規化 (型・範囲・未知値を安全側へ)、危険な提案の機械的な確認、通知ポリシー (確信度・時間帯・断りの回数) を通して返す。
8. iOS はさらにユーザーの通知設定 (静かな時間・1日の上限・間隔・体験中) で最終判断する。

## 主な設計判断

| 判断 | 理由 |
|---|---|
| Backend は実行時の依存パッケージなし (Node の型除去で TS を直接実行) | 供給網リスクとビルド工程を減らす。開発時のみ `typescript` と `@types/node` |
| AI出力は tool use で構造化し、Backend で正規化してから返す | 指示書 §17「AIの自由文をUIロジックに使わない」 |
| AIが使えないときはモックで代替生成 (`source: fallback`) | アプリが止まらない。理由をUIで正直に伝える |
| 1日の利用上限 (リクエスト数・トークン数・検索回数) | 個人利用での想定外の請求を防ぐ |
| 通知はローカル通知 + バックグラウンド更新 (プッシュ通知は使わない) | 常時接続ではなく必要時接続 (§13)。サーバーにデバイストークンを持たない |
| 会話はどこにも保存しない | 保存する必要がないものは保存しない (§19) |
| トークンは Keychain (この端末のみ)、アプリ本体に秘密情報を埋め込まない | §4, §18 |
| 中核は Swift 6 言語モード、アプリ層は Swift 5 + 並行性チェック complete (警告) | 中核のデータ競合をコンパイル時に排除しつつ、OS API の注釈差でビルドが止まらないようにする |

## 拡張するとき

- **SwiftData のモデル変更**: `TaikenSchemaV2` を追加し、`TaikenMigrationPlan.stages` に移行を足す。
- **API の破壊的変更**: `/v2` を作り、`contracts/` を更新する。
- **AI提供元の追加**: `AiProvider` を実装して `index.ts` で差し替える。正規化と安全確認はエンジン側にあるので共通。
