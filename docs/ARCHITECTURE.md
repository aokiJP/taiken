# アーキテクチャ

## 全体

```
┌───────────────────────── iPhone ─────────────────────────┐       ┌──────── 自分のサーバー (任意) ────────┐
│ Taiken (アプリ / Swift 5 + SwiftUI)                         │       │ Backend (Node.js + TypeScript)         │
│  Views ─ AppDependencies (組み立て) ─ AppRouter             │       │  HTTP: 認証・レート制御・期限            │
│  SwiftData / EventKit / CoreLocation / Keychain            │ HTTPS │  入力の許可リスト化・季節の正規化        │
│  UserNotifications / BGTask / App Intents                  │ ────▶ │  Engine: 予算・遮断器・同時数           │──▶ Anthropic API
│  Apple Intelligence (iOS 26, 端末内)                        │Bearer │   ├ 下調べ (必要時Web検索)              │
│            │ ports (protocol)                              │       │   ├ 体験生成 / 会話 (tool use)          │
│ TaikenCore (中核 / Swift 6)                                 │       │   ├ 正規化・安全確認・通知判断          │
│  ViewModels・季節・体験ライブラリ・安全確認・通知判断・傾向    │       │   └ 失敗時は体験ライブラリで代替生成    │
│            │ App Group (今日の状態だけ)                     │       └───────────────────────────────────────┘
│ TaikenWidgets (ウィジェット・Live Activity)                  │
└────────────────────────────────────────────────────────────┘
          contracts/  … OpenAPI・フィクスチャ・体験ライブラリ (content.ja.json)・選び方のテストケース
```

- **iOS → 自分のBackend → AI API** (指示書 §4)。AIのAPIキーはBackendの環境変数にだけ存在する。
- **サーバーは任意**。未設定・オフラインでも、端末内のしくみ (Apple Intelligence または体験ライブラリ) で体験の流れは最後まで動く。
- **契約**は `contracts/`。両側のテストが同じフィクスチャ・同じ体験ライブラリ・同じ選び方のテストケースで検証する。

## 提案をつくるしくみ

| しくみ | いつ使うか | 実装 |
|---|---|---|
| 自分のサーバーのAI | 設定で接続先を保存したとき | `BackendClient` (TaikenCore) → Backend の Engine |
| Apple Intelligence | 接続先が無く、iOS 26 以降・対応機種・Apple Intelligence がオンのとき | `AppleIntelligenceExperienceService` (FoundationModels。`#if canImport` と `@available` で囲む) |
| 体験ライブラリ | 上のどちらも使えないとき、または失敗したとき | `LocalExperienceService` (TaikenCore)。Backend の代替生成も同じライブラリと同じ選び方 |

- `RoutingExperienceService` が今のしくみを持ち、設定の変更ですぐ差し替える。`EngineState` が画面に「どのしくみか」を正直に出す。
- 端末内のAIの出力にも `SafeguardedExperienceService` をかぶせ、サーバーと同じ安全確認 (危険な提案の除外・強い苦痛のサインでの相談先の案内) を通す。失敗・不正な出力のときは体験ライブラリに切り替える。
- `HomeViewModel.generate` は、主のしくみが失敗したら必ず端末内に切り替え、理由を一行で伝える (黙って止まらない)。

## 体験ライブラリと七十二候

- `contracts/content.ja.json` が正。76の体験 (二十四節気ごとの季節の体験24を含む)、七十二候、テーマと気分のキーワードを持つ。
- `contracts/tools/sync.sh` が iOS (`TaikenCore/Resources`) と Backend (`src/content`) にコピーし、両方のテストがバイト単位の一致を確かめる。
- 選び方の仕様は `contracts/tools/selection_reference.py` (Python の基準実装)。予定・発言から読んだテーマ、気分、季節、時間帯、反応の傾向、最近の体験、除外を点数にし、日ごとに決まる小さなゆらぎを足して最大のものを選ぶ。そこから作った `selection_cases.json` を Swift・TypeScript・プロトタイプが同じ結果で通る。
- 七十二候は太陽の視黄経 (Meeus の簡易式) を5度ごとに区切って求める。暦の慣習どおり、切り替わる瞬間を含む日は新しい候の日とする (その日の終わりで判定)。国立天文台の2026年の暦と日付が一致することをテストで確かめている。
- 季節は日付だけから決まるので、許可なしでリクエストに含める。Backend は受け取った季節の文言を表から引き直し (`canonicalSeason`)、表に無い文言は捨てる (プロンプトへの混入を防ぐ)。

## iOS の層

| 層 | 依存 | 役割 | 検証 |
|---|---|---|---|
| `TaikenCore` (Swift Package) | Foundation, Observation, Synchronization のみ | API型、BackendClient、ContextAssembler、Home/Chat/History/Settings の ViewModel、季節、体験ライブラリと選び方、端末内の会話、安全確認、通知判断と朝の便り、傾向計算、送信内容の表示 (`RequestPreview`)、ウィジェットに渡す状態 | `swift test` (Linux / macOS)、Swift 6 言語モード |
| `Taiken` (アプリ) | SwiftUI, SwiftData, EventKit, CoreLocation, Security, UserNotifications, BackgroundTasks, ActivityKit, WidgetKit, AppIntents, FoundationModels (iOS 26) | Port の実装 (アダプタ)、画面、依存の組み立て、ディープリンクとショートカット | Xcode (シミュレータ・実機ビルド) |
| `TaikenWidgets` (拡張) | SwiftUI, WidgetKit, ActivityKit | 今日のウィジェット、体験中の Live Activity | Xcode |
| `Shared` | SwiftUI, UIKit | アプリとウィジェットが同じ見た目を使うための色・書体・印・短冊、App Group、ディープリンク、Live Activity の属性 | 両方のターゲットでビルド |

中核は端末機能を `Ports.swift` などのプロトコル越しにしか使わない。テストとプレビューは `InMemoryAdapters.swift` や記録用の実装 (`RecordingPresence`・`RecordingWidgetPublisher`・`RecordingLetterScheduler`) に差し替える。
これにより、画面以外のほぼすべての振る舞いを Apple 以外の環境でも自動テストできる。

## 画面と状態

- ホームの真ん中のカードは `HomeViewModel.stage` だけで決まる: `loading → proposal → active → completed → resting` (+ `failed` / `idle`)。
- 「記す」は振り返りのシートが閉じきってから `finish` を呼ぶ (`sheet(onDismiss:)`)。印が押される瞬間を必ず見せるため。
- 画面の移動は `AppRouter` (シート: 話す・設定 / 押し出し: 体験帳 → 記録の詳細。型を混ぜられる `NavigationPath`)。
- 通知・ウィジェット・ショートカットからの入口は `DeepLink` (`taiken://today`・`journal`・`talk`) にまとめ、はじめの案内を終えるまでは何もしない。

## 体験の流れ (サーバー接続時)

1. `ContextAssembler` が、ユーザーが許可した情報だけを集める (予定は時間とタイトルのみ・終了済みは除外・最大8件、地域は市区町村名のみ、会話は直近の数件を6時間だけメモリに保持)。気分はその場で選んだときだけ、季節は日付から。
2. `PreferenceTrends` が履歴から「最近の反応の傾向」を計算する (14日の半減期、材料が少ないタグや半々のタグは送らない)。
3. Backend の `sanitize` が許可リスト方式で入力を組み直す (未知のフィールドは捨てる。季節は表から引き直す)。
4. Engine が予算 → 同時実行数 → 遮断器を確認。だめならAIを呼ばずに体験ライブラリで代替生成し、`fallback_reason` を付ける。
5. ユーザーが許可し、サーバーで有効なら、**下調べ**でAIに「外部情報が必要か」を判断させる。必要なときだけ `web_search` を使い、要約と参照URLだけを取り出す。検索段には発言や予定のタイトルを渡さない。
6. **体験生成**は `propose_experience` ツールを強制して構造化JSONだけを受け取る (振り返りの問い `reflection_question` を含む)。
7. 正規化 (型・範囲・未知値を安全側へ)、危険な提案の機械的な確認、通知ポリシー (確信度・時間帯・断りの回数) を通して返す。
8. iOS はさらにユーザーの通知設定 (静かな時間・1日の上限・間隔・体験中) で最終判断する。

## アプリの外への出口

| 出口 | 中身 | 実装 |
|---|---|---|
| ウィジェット | アプリが App Group の UserDefaults に置いた「今日の状態」(`WidgetSnapshot`: 種類・名前・誘いかけ・問い・印・季節)。内容が変わったときだけ描き直す | `AppGroupWidgetPublisher` → `TodayWidget` (時間帯の境目ごとに空を描き直し、日付が変わったら季節だけに戻す) |
| Live Activity | 体験中の誘いかけと問い。終えた・やめたらすぐ消す。ユーザーが消した表示は勝手に戻さない | `LiveActivityPresence` → `ExperienceLiveActivity` |
| 朝の便り | これから7日分のローカル通知を予約し直す (その日すでに触れていれば今日の分は送らない) | `DailyLetter.plan` → `UserNotificationLetterScheduler` |
| 状況に合わせた通知 | バックグラウンド更新で状況を確かめ、条件を満たすときだけ | `BackgroundCoordinator` → `UserNotificationScheduler` |
| ショートカット | 今日の体験 / 体験帳 / 話しかける を開く | `AppIntents.swift` (`PendingRoute` → `RootView` → `DeepLink`) |

## 保存

| データ | 場所 | 形式 |
|---|---|---|
| 体験帳 | アプリ自身の領域の SwiftData (App Group には置かない・iCloud に同期しない) | `TaikenSchemaV2` (v1 から軽量移行。v2 で振り返りの問いを追加) |
| 今日の提案・ひと休みの終わり | UserDefaults (当日分のみ) | JSON |
| ウィジェットに渡す状態 | App Group の UserDefaults | JSON (`WidgetSnapshot`) |
| 接続トークン | Keychain (この端末のみ) | — |
| 会話 | 保存しない (メモリのみ) | — |

## 主な設計判断

| 判断 | 理由 |
|---|---|
| サーバーを任意にし、端末内のしくみだけで体験の流れを完結させる | 誰でもすぐ使える。繋がらないときも止まらない |
| 体験ライブラリと選び方を contracts に置き、iOS・Backend・プロトタイプで共有する | どこで選んでも同じ体験になる。片方だけ変えるとテストが落ちる |
| 季節は Backend で表から引き直す | 季節の文言を経由したプロンプトへの混入を防ぐ |
| Backend は実行時の依存パッケージなし (Node の型除去で TS を直接実行) | 供給網リスクとビルド工程を減らす。開発時のみ `typescript` と `@types/node` |
| AI出力は tool use で構造化し、Backend で正規化してから返す | 指示書 §17「AIの自由文をUIロジックに使わない」 |
| 通知はローカル通知 + バックグラウンド更新 (プッシュ通知は使わない) | 常時接続ではなく必要時接続 (§13)。サーバーにデバイストークンを持たない |
| 会話はどこにも保存しない | 保存する必要がないものは保存しない (§19) |
| ウィジェットには今日の状態だけを渡し、体験帳は渡さない | ロック画面に出るものを最小にする |
| 中核は Swift 6 言語モード、アプリ層は Swift 5 + 並行性チェック complete (警告) | 中核のデータ競合をコンパイル時に排除しつつ、OS API の注釈差でビルドが止まらないようにする |

## 拡張するとき

- **SwiftData のモデル変更**: `TaikenSchemaV3` を追加し、`TaikenMigrationPlan.schemas` と `stages` に足す。古いスキーマの型は消さない。移行のテストを `TaikenTests` に足す。
- **体験の追加・文言の変更**: `contracts/content.ja.json` を直し、`contracts/tools/sync.sh` を実行してから両方のテストを流す。選び方を変えるときは基準実装から直す。
- **API の破壊的変更**: `/v2` を作り、`contracts/` を更新する。
- **AI提供元の追加**: `AiProvider` を実装して `index.ts` で差し替える。正規化と安全確認はエンジン側にあるので共通。
