# アーキテクチャ

## 全体

```
┌───────────────────────── iPhone ─────────────────────────┐       ┌──────── 自分のサーバー (任意) ────────┐
│ Taiken (アプリ / Swift 5 + SwiftUI)                         │       │ Backend (Node.js + TypeScript)         │
│  Views ─ AppDependencies (組み立て) ─ AppRouter             │       │  HTTP: 認証・レート制御・期限            │
│  SwiftData / EventKit / CoreLocation / Keychain            │ HTTPS │  入力の許可リスト化 (樹は id の形だけ)  │
│  UserNotifications / BGTask / App Intents                  │ ────▶ │  Engine: 予算・遮断器・同時数           │──▶ Anthropic API
│  Apple Intelligence (iOS 26, 端末内)                        │Bearer │   ├ 下調べ (必要時Web検索)              │
│            │ ports (protocol)                              │       │   ├ きっかけ生成 / 会話 (tool use)      │
│ TaikenCore (中核 / Swift 6)                                 │       │   ├ 正規化・安全確認・通知判断          │
│  ViewModels・技の樹・体験ライブラリ・安全確認・通知判断       │       │   └ 失敗時は体験ライブラリで代替生成    │
│            │ App Group (今日の状態だけ)                     │       └───────────────────────────────────────┘
│ TaikenWidgets (ウィジェット・Live Activity)                  │
└────────────────────────────────────────────────────────────┘
          contracts/  … OpenAPI・フィクスチャ・体験ライブラリと10の要素 (content.ja.json)・技の樹 (skills.ja.json)・選び方のテストケース
```

- **iOS → 自分のBackend → AI API** (指示書 §4)。AIのAPIキーはBackendの環境変数にだけ存在する。
- **サーバーは任意**。未設定・オフラインでも、端末内のしくみ (Apple Intelligence または体験ライブラリ) で体験の流れは最後まで動く。
- **技の樹は端末の中だけ**。経験・段・芽・身についた技は端末で計算し、サーバーには送らない (送るのは、きっかけを選ぶための体験ライブラリの id だけ)。
- **契約**は `contracts/`。両側のテストが同じフィクスチャ・同じ体験ライブラリ・同じ選び方のテストケースで検証する。技の樹 (`skills.ja.json`) は iOS だけが使う。

## きっかけをつくるしくみ

きっかけ (AI・体験ライブラリの提案) は、ホームで「きっかけをもらう」を押したとき、話すで頼んだとき、自分でオンにした「ちょうどよい時に知らせる」のときだけつくる。画面を開いただけでは作らない (`HomeViewModel.refresh` はきっかけを作らない)。

| しくみ | いつ使うか | 実装 |
|---|---|---|
| 自分のサーバーのAI | 設定で接続先を保存したとき | `BackendClient` (TaikenCore) → Backend の Engine |
| Apple Intelligence | 接続先が無く、iOS 26 以降・対応機種・Apple Intelligence がオンのとき | `AppleIntelligenceExperienceService` (FoundationModels。`#if canImport` と `@available` で囲む) |
| 体験ライブラリ | 上のどちらも使えないとき、または失敗したとき | `LocalExperienceService` (TaikenCore)。Backend の代替生成も同じライブラリと同じ選び方 |

- `RoutingExperienceService` が今のしくみを持ち、設定の変更ですぐ差し替える。`EngineState` が画面に「どのしくみか」を正直に出す。
- 端末内のAIの出力にも `SafeguardedExperienceService` をかぶせ、サーバーと同じ安全確認 (危険な提案の除外・強い苦痛のサインでの相談先の案内) を通す。失敗・不正な出力のときは体験ライブラリに切り替える。
- `HomeViewModel.generate` は、主のしくみが失敗したら必ず端末内に切り替え、理由を一行で伝える (黙って止まらない)。

## 体験ライブラリと10の要素

- `contracts/content.ja.json` (version 2) が正。10の要素 (字・名前・説明・根・言葉の手がかり)、94の体験、体験どうしの130のつながり (`opens`: deepen / widen / cross)、テーマと気分のキーワードを持つ。季節に結びついた体験は持たない。94の体験は、どれも技の樹のいずれかの技の「稽古」になっている。
- `contracts/tools/check_content.py` が、つながりの行き先・根が自分の要素を主に持つこと・どの体験も根からたどれること・誘いかけの形・季節の言葉が無いことを確かめる。
- `contracts/tools/sync.sh` が検査のあと iOS (`TaikenCore/Resources`)・Backend (`src/content`) にコピーし、テストが一致を確かめる。
- 選び方の仕様は `contracts/tools/selection_reference.py` (Python の基準実装)。予定・発言から読んだテーマ (+4 / 合わない場面は −2)、気分 (+2.5)、時間帯 (+1.5)、**技の稽古 (buds, +1.5)**、反応の傾向、最近の体験 (−3)、除外を点数にし、日ごとに決まる小さなゆらぎ (FNV-1a) を足して最大のものを選ぶ。そこから作った `selection_cases.json` の16ケースを Swift・TypeScript が同じ結果で通る。

## 技の樹

```
TaikenContent (要素・体験ライブラリ)  ─┐
SkillBook (技の樹の設計図: skills.ja.json)  ─┤
Garden (身についた技・使った技・編んだ技・結び・見届け) ─┼─▶ TreeBuilder.build ─▶ ExperienceTree ─▶ TreeLayout (放射状の配置)
体験帳 (HistoryEntry: nodeID・要素・時刻)  ─┘        │                    │
                                                  │                    ├▶ TreeViewModel (樹・一覧・技のページ・伸ばす・編む・結ぶ)
                                                  │                    ├▶ GrowthReport (記す前と後の差: 経験・段・芽・閃き・深まり)
                                                  │                    ├▶ TreeContext (きっかけに添える: 記した体験と技の稽古)
                                                  │                    ├▶ Lineage (きっかけ・体験中のカードに添える「◯の稽古」)
                                                  │                    └▶ VaultExporter (Markdown の保管庫)
                                           TreeSource (材料をまとめ、learn / settle / link / weave / tie / place を受け持つ)
```

### 設計図 (`SkillBook`)

- `contracts/skills.ja.json` (version 1) が正で、iOS がコピーを持つ (`SkillBookTests` がバイト単位で一致を確かめる)。93の技: 要素ごとに一の技3・二の技3・奥義1 (70)、渡り技14、閃き9。守破離の境目 (`mastery`: 破 3・離 7) もここ。
- 1つの技: `id`・`kind` (art / secret / cross / flash)・`element` と `also` (渡り技のもう一方)・`name`・`reading`・`ability` (できるようになること)・`after` と `needs` (先にあるとよい技と、そのうちいくつ)・`rank` (要素ごとに要る段)・`practice` (稽古: 体験ライブラリの id)・`keywords` (記した言葉から「使ったかも」を推し量る手がかり)。閃きは `practice`・`after`・`rank` を持たず、`flash` (条件) と `found` (閃いたとき) を持つ。
- `contracts/tools/check_skills.py` が、要素ごとの形・先の技が輪にならず根からたどれること・稽古がライブラリにあり、ライブラリのどの体験もどれかの技の稽古であること・名前が体験ライブラリの体験と重ならないこと・読みがひらがなであること・できるようになることの形 (40文字までの一文・段の数や季節の言葉を使わない)・閃きの条件の形を確かめる。
- 読み込めないときは空の樹 (`SkillBook.empty`) で動き続ける (要素の根と段だけになる)。

### 組み立て (`TreeBuilder.build`)

樹は保存しない。体験帳と自分の樹から、開くたび・記すたびに組み立てる (技と記録は百前後なので軽い)。

1. 記した体験 (`status == .completed`) を古い順に並べ、触れた要素を決める (記録の要素 → ライブラリの同じ体験 → 名前と文から推し量る `ElementClassifier`。3つまで)。要素ごとに数えたものが**経験**
2. 節を並べる: 要素の根 (`el-<要素>`) → 設計図の技 (閃きを除く) → 自分で編んだ技 (`w-…`)。3.0 で編んだ体験も、編んだ技として読む
3. 身についた技 (`Garden.learned`) と、芽を使った要素を数える。記録ごとに、その記録で育った技を決める: 記すときに選んだ技 (`Garden.uses`) + 稽古から始めた記録ならその稽古をもつ技 + 編んだ技の稽古
4. 要素ごとに**段** (`Ranks.rank`: 境目 1, 3, 6, 10 … = n(n+1)/2) と、まだ使っていない**芽** (段 − 芽を使った技の数) を計算する
5. 離に届いた技と、その時刻を求める (閃きの条件に使う)
6. **閃き**: 自分の樹に残っている閃き + いまの体験帳で条件を満たすもの (`FlashEvaluator`)。満たした体験 (または糸) の時刻を、閃いた時刻にする。まだ閃いていないものは数だけ持つ (画面には出さない)
7. **様子**: 根は段があれば身についた。技は、身についていれば身についた / 段と先の技がそろえば育てられる / 先の技が無いか、ひとつでも身についていれば気配 / それ以外は霧
8. つながり: 先の技から (同じ要素なら branch、別の要素なら cross)、先の技が無ければ根から。閃きは根から spark。結びは tie
9. 配置のための木: 要素ごとに、根から同じ要素の枝だけをたどる (深さと親子)。たどれない技は根に直接つなぐ
10. 技ごとの記録 (`SkillLife`): 使った記録と身についた時刻。守・破・離は使った記録の数から (`Mastery.of`)

### 受け持ち (`TreeSource`)

| 操作 | すること |
|---|---|
| `learn(id)` | `check` が `.available(charge:)` なら、その要素の芽をひとつ使って `Garden.learned` に足す。条件が足りない・芽が無いときは理由を返す (`LearnError`) |
| `settle()` | 新しく閃いた技を `Garden.learned` に残す (体験帳を消しても、閃きは消えない)。記した・伸ばした・結んだあとに呼ぶ |
| `link(entry:skills:)` | 記した体験で使った技 (身についた技だけ) を記録に結ぶ。`forget(entry:)` は記録を消したときに外す |
| `weave` / `revise` / `remove` | 編んだ技を植える・書き直す・手放す (`WeaveDraft.problems` で確かめてから。手放すと使った芽は戻る) |
| `tie` / `untie` | 身についた技どうしを結ぶ・ほどく |
| `welcome()` / `markSeen()` | 3.0 から来たときに一度だけ見せる「これまでの体験から育っていたもの」(`GrowthReport.since(nothing:)`) |
| `place(_:)` | きっかけや稽古を始める前に、要素と `nodeID` を補う (ライブラリの体験・編んだ技の稽古はその id を残す。記すと、その稽古をもつ技に数える) |
| `lineage(of:)` | カードに添える一行。どの技の稽古か (霧の中の技は名前を出さず要素だけ) / 新しい体験か |
| `context()` | きっかけに添える `TreeContext` |

保存に失敗したら変更を捨てる (`commit` が保存できたときだけ `garden` と `revision` を進める)。

### 記すと、どう伸びるか

- `HomeViewModel.record(LivedDraft)`: 自分で見つけた体験を記す。`HistoryEntry.lived` は誘いかけを持たない記録 (`isSelfRecorded`)。保存 → `link` → `settle` → 記す前の樹と記したあとの樹の差 (`GrowthReport.between`) を `completedGrowth` に置く。
- `HomeViewModel.finish(rating:note:skills:)`: きっかけや稽古から始めた体験を記す。流れは同じ。
- `GrowthReport`: 経験が積もった要素、段が上がった要素 (`RankUp`: 新しく出た芽の数も。記録を消したあとに同じ段へ戻ったときは 0)、新しく閃いた技、深まった技 (守 → 破、破 → 離)、いま伸ばせる技がある要素。記したところのカードは、これだけを見せる。

### 配置 (`TreeLayout`)

要素ごとに、葉の数に応じた扇形を割り当て、根を内側の輪 (半径 0.3) に、深さ1つごとに 0.2 ずつ外の輪に置く。閃きは、その要素の扇のいちばん外の輪に置く。同じ輪で近すぎる技は角度を少しずつ離す。乱数は使わず、同じ樹からはいつも同じ配置になる。樹の形 (`signature`: 節・主な要素・親) が変わったときだけ計算し直す。

### きっかけに添える樹のいま (`TreeContext`)

- `lived`: 記したことのある体験ライブラリの体験 (最近のものから12件まで。id・名前・要素)。自分で見つけて記した体験は、自分の言葉なので入れない
- `buds`: 技の稽古。身についた技・育てられる技の稽古になる体験の id (16件まで)。何も身についていなければ、要素の根の体験
- 体験帳を使う許可があるときだけ送る。Backend は id の形 (英小文字・数字・ハイフン) と件数を確かめ、選び方では `buds` を少しだけ前に出す (+1.5)。AIは `lived` から自然に伸びる体験なら `grows_from` にその id を入れられる。`tree.lived` に無い id は捨てる (Backend の正規化と、iOS の `place` の両方で)
- きっかけの理由には、どの技の稽古かを書かない (霧の中の技の名前を明かさないため)。どの技の稽古かは、iOS がカードの「枝」(`Lineage`) で、見えている技だけを出す

## iOS の層

| 層 | 依存 | 役割 | 検証 |
|---|---|---|---|
| `TaikenCore` (Swift Package) | Foundation, Observation, Synchronization のみ | API型、BackendClient、ContextAssembler、Home/Chat/History/Settings/Tree の ViewModel、技の樹 (設計図・組み立て・段と芽・閃き・配置・自分の樹・書き出し)、体験ライブラリと選び方、端末内の会話、安全確認、通知判断と朝の便り、傾向計算、送信内容の表示 (`RequestPreview`)、ウィジェットに渡す状態 | `swift test` (Linux / macOS)、Swift 6 言語モード |
| `Taiken` (アプリ) | SwiftUI, SwiftData, EventKit, CoreLocation, Security, UserNotifications, BackgroundTasks, ActivityKit, WidgetKit, AppIntents, FoundationModels (iOS 26) | Port の実装 (アダプタ)、画面 (樹は `Canvas` で描く)、依存の組み立て、ディープリンクとショートカット | Xcode (シミュレータ・実機ビルド)、`TaikenTests`・`TaikenUITests` |
| `TaikenWidgets` (拡張) | SwiftUI, WidgetKit, ActivityKit | 今日のウィジェット (体験中 / きっかけ / 「体験を記す」の入口)、体験中の Live Activity | Xcode |
| `Shared` | SwiftUI, UIKit | アプリとウィジェットが同じ見た目を使うための色・書体・印、App Group、ディープリンク、Live Activity の属性 | 両方のターゲットでビルド |

中核は端末機能を `Ports.swift` などのプロトコル越しにしか使わない。テストとプレビューは `InMemoryAdapters.swift` や記録用の実装 (`RecordingPresence`・`RecordingWidgetPublisher`・`RecordingLetterScheduler`・`InMemoryGardenStore`) に差し替える。
これにより、画面以外のほぼすべての振る舞いを Apple 以外の環境でも自動テストできる。

## 画面と状態

- ホームの真ん中のカードは `HomeViewModel.stage` だけで決まる: ふだんは `idle` (技の樹のカード: 十の要素の段・芽・「体験を記す」・「きっかけをもらう」)。きっかけを求めると `loading → proposal`、やってみると `active`、記すと `completed` (+ `failed`)。`welcome` (3.0 から来たときの一度だけの知らせ) は `idle` のときだけ出す。
- 「記す」は、記す・振り返りのシートが閉じきってから `record` / `finish` を呼ぶ (`sheet(onDismiss:)`)。印が押される瞬間と、樹の伸び (`completedGrowth`) を必ず見せるため。
- 画面の移動は `AppRouter` (シート: 話す・設定 / 押し出し: 体験帳 → 記録の詳細、ホーム → 技の樹。型を混ぜられる `NavigationPath`)。「体験を記す」はホームのシートで、ショートカット・ウィジェット (`taiken://record`) からも開く。
- 技の樹の画面 (`TreeView`) は `TreeViewModel.revision` が変わったときだけ描く材料 (`TreeScene`) を作り直す。移動と拡大は `TreeViewport` (アニメーションできる値) だけを変え、`Canvas` が毎フレーム描く。技のページ (`NodePage`) はシートの中の `NavigationStack` で、となりの技へ押し出していく。
- 樹から稽古を「やってみる」と、ページのシートが閉じきってから `HomeViewModel.begin` → ホームへ戻る。体験中のものがあれば、区切ってよいかを先に聞く。
- 通知・ウィジェット・ショートカットからの入口は `DeepLink` (`taiken://today`・`journal`・`tree`・`talk`・`record`) にまとめ、はじめの案内を終えるまでは何もしない。

## きっかけの流れ (サーバー接続時)

1. `ContextAssembler` が、ユーザーが許可した情報だけを集める (予定は時間とタイトルのみ・終了済みは除外・最大8件、地域は市区町村名のみ、会話は直近の数件を6時間だけメモリに保持)。気分はその場で選んだときだけ。体験帳を使う許可があるときだけ、最近の体験 (自分で見つけて記した体験は除く) と技の樹のいま (`tree`) を添える。
2. `PreferenceTrends` が履歴から「最近の反応の傾向」を計算する (14日の半減期、材料が少ないタグや半々のタグは送らない)。
3. Backend の `sanitize` が許可リスト方式で入力を組み直す (未知のフィールドは捨てる。樹の id は英小文字・数字・ハイフンの形だけ、件数の上限付き。古いクライアントが送る `season` は無視する)。
4. Engine が予算 → 同時実行数 → 遮断器を確認。だめならAIを呼ばずに体験ライブラリで代替生成し、`fallback_reason` を付ける (技の稽古も同じように少し前に出す)。
5. ユーザーが許可し、サーバーで有効なら、**下調べ**でAIに「外部情報が必要か」を判断させる。必要なときだけ `web_search` を使い、要約と参照URLだけを取り出す。検索段には発言や予定のタイトルを渡さない。
6. **きっかけ生成**は `propose_experience` ツールを強制して構造化JSONだけを受け取る (振り返りの問い・要素・伸びた先を含む)。プロンプトは、提案は義務ではなく「きっかけ」であること、「次の段階へ」「レベルを上げよう」のような言い方をしないことを求める。
7. 正規化 (型・範囲・未知値を安全側へ。要素は10の要素だけ、伸びた先は `tree.lived` にある id だけ)、危険な提案の機械的な確認、通知ポリシー (確信度・時間帯・断りの回数) を通して返す。
8. iOS はさらにユーザーの通知設定 (静かな時間・1日の上限・間隔・体験中) で最終判断する。

## アプリの外への出口

| 出口 | 中身 | 実装 |
|---|---|---|
| ウィジェット | アプリが App Group の UserDefaults に置いた「今日の状態」(`WidgetSnapshot`: 種類・名前・誘いかけ・問い・印・要素の名前)。体験中・きっかけが無いときは日付とひとことで、押すと「体験を記す」へ。内容が変わったときだけ描き直す | `AppGroupWidgetPublisher` → `TodayWidget` (時間帯の境目ごとに空を描き直し、日付が変わったら日付とひとことに戻す) |
| Live Activity | 体験中の誘いかけと問いと要素。終えた・やめたらすぐ消す。ユーザーが消した表示は勝手に戻さない | `LiveActivityPresence` → `ExperienceLiveActivity` |
| 朝の便り | これから7日分のローカル通知を予約し直す。中身は短いひとことだけ (その日すでに触れていれば今日の分は送らない) | `DailyLetter.plan` → `UserNotificationLetterScheduler` |
| ちょうどよい時に知らせる | バックグラウンド更新で状況を確かめ、条件を満たすときだけきっかけをひとつ知らせる (自分でオンにしたときだけ) | `BackgroundCoordinator` → `UserNotificationScheduler` |
| ショートカット | 体験を記す / ホーム / 体験帳 / 技の樹 / 話しかける を開く | `AppIntents.swift` (`PendingRoute` → `RootView` → `DeepLink`) |
| 書き出し | 技の樹を Markdown の保管庫 (zip) に、体験帳と自分の樹を JSON に | `VaultExporter` → `VaultArchive` (`NSFileCoordinator` の `.forUploading` で zip にする)、`HistoryViewModel.exportJSON` |

## 保存

| データ | 場所 | 形式 |
|---|---|---|
| 体験帳 | アプリ自身の領域の SwiftData (App Group には置かない・iCloud に同期しない) | `TaikenSchemaV3` (v1 → v2 → v3 の軽量移行。v2 で振り返りの問い、v3 で樹の上の位置 `nodeID` と要素 `elementsText` を追加)。4.0 では変えていない |
| 自分の樹 | アプリ自身の Application Support の `Taiken/garden.json` (iCloud に同期しない・初回のロック解除まで保護) | JSON (`Garden` version 2: `learned` 身についた技と閃き・`uses` 記録と使った技・`nodes` 編んだ技・`ties` 結び・`seen` 4.0 の知らせを見届けたか)。version 1 (3.0: `nodes` と `ties` だけ) も読む |
| 今日のきっかけ・通知を控える終わり | UserDefaults (当日分のみ) | JSON |
| ウィジェットに渡す状態 | App Group の UserDefaults | JSON (`WidgetSnapshot`) |
| 接続トークン | Keychain (この端末のみ) | — |
| 会話 | 保存しない (メモリのみ) | — |

経験と段は保存しない (体験帳から数え直す)。保存するのは、自分で選んだこと (どの技に芽を使ったか・どの技を使ったか・編んだ・結んだ) と閃きだけ。

## 主な設計判断

| 判断 | 理由 |
|---|---|
| サーバーを任意にし、端末内のしくみだけで体験の流れを完結させる | 誰でもすぐ使える。繋がらないときも止まらない |
| きっかけは求められたときだけつくる (画面を開いただけでは作らない) | 提案は、こなすと義務になる。体験は自分で生きて記すもの |
| 経験・段・芽は入れる。期限・連続・減少・比較・達成率は入れない | 成長が見える・選ぶ、という RPG の体験の本体だけを借り、数を義務にする仕組みは借りない |
| 経験と段は記録から毎回数え直す。保存するのは自分で選んだことと閃きだけ | 体験帳の記録を消せば、そのぶんの経験も消える。食い違う二つの真実を持たない。身についた技と閃きは、選んだ・閃いた事実として残す |
| 技の中身 (名前・できるようになること・条件・稽古) をデータ (`skills.ja.json`) にし、検査をかける | 言葉の見直しをコードに触らずにできる。名前を変えても id は変えないので、身についた技は失われない |
| 霧の中の技の名前は、画面にも理由にも書き出しにも出さない | 気配と発見を守る。きっかけの理由は Backend・端末内で共通の書き方にし、技の名前を入れない |
| 体験ライブラリと選び方を contracts に置き、iOS・Backend で共有する | どこで選んでも同じ体験になる。片方だけ変えるとテストが落ちる |
| 送るのは体験ライブラリの id と名前と要素だけ。自分で記した言葉・ひとこと・評価・技の樹の段や技は送らない | きっかけに役立つ最小限。Backend は id の形と件数を確かめ、知らない id は捨てる |
| Backend は実行時の依存パッケージなし (Node の型除去で TS を直接実行) | 供給網リスクとビルド工程を減らす。開発時のみ `typescript` と `@types/node` |
| AI出力は tool use で構造化し、Backend で正規化してから返す | 指示書 §17「AIの自由文をUIロジックに使わない」 |
| 通知はローカル通知 + バックグラウンド更新 (プッシュ通知は使わない) | 常時接続ではなく必要時接続 (§13)。サーバーにデバイストークンを持たない |
| 会話はどこにも保存しない | 保存する必要がないものは保存しない (§19) |
| ウィジェットには今日の状態だけを渡し、体験帳と樹は渡さない | ロック画面に出るものを最小にする |
| 中核は Swift 6 言語モード、アプリ層は Swift 5 + 並行性チェック complete (警告) | 中核のデータ競合をコンパイル時に排除しつつ、OS API の注釈差でビルドが止まらないようにする |

## 拡張するとき

- **技の追加・言葉の変更**: `contracts/skills.ja.json` を直し、`sh contracts/tools/sync.sh` を実行してから `swift test` を流す。id は変えない (身についた技・使った技は id で保存されている)。要素ごとの形 (一の技3・二の技3・奥義1) を変えるときは、`check_skills.py` と `SkillBookTests` も合わせる。
- **閃きの条件の追加**: `SkillBook.FlashRule` と `FlashEvaluator` に足し、`check_skills.py` の `FLASH_KEYS` にも足す。期限・連続・回数を競う条件は作らない。
- **体験の追加・つながりの変更**: `contracts/content.ja.json` を直し、`sync.sh` を実行してから全部のテストを流す (検査が、行き先の無いつながり・根からたどれない体験・どの技の稽古でもない体験を見つける)。選び方を変えるときは基準実装から直す。
- **SwiftData のモデル変更**: `TaikenSchemaV4` を追加し、`TaikenMigrationPlan.schemas` と `stages` に足す。古いスキーマの型は消さない。移行のテストを `TaikenTests` に足す。
- **自分の樹の形の変更**: `Garden.currentVersion` を上げ、読み込みで古い形を受け取れるようにする (`GardenStoreTests`)。
- **API の破壊的変更**: `/v2` を作り、`contracts/` を更新する。
- **AI提供元の追加**: `AiProvider` を実装して `index.ts` で差し替える。正規化と安全確認はエンジン側にあるので共通。
