# 体験 — いつもの一日に、まだ見ていない体験がある

> AIが人生を代わりに生きるのではなく、AIが日常の中から「次の体験」を見つけ、人間自身がそれを生きる。

予定・気分・時間帯から、いつもの行動を「別の視点・問い・小さな挑戦」として捉え直す誘いかけを、**ひとつだけ**差し出す iOS アプリと、その Backend です。
やった体験は **体験の樹** に灯り、その先に次の芽が出ます。サーバーが無くても、端末の中だけで最後まで使えます (体験ライブラリ / iOS 26 の Apple Intelligence)。

## 体験の流れ

```
受け取る ──▶ やってみる ──▶ 思い返す ──▶ 印を押す ──▶ 樹に灯る ──▶ ひと休み
 (今日の体験)  (体験中: ロック画面にも)  (問いに答えて、ひとこと)  (体験帳に朱の印)  (その先に芽が出る)  (押しつけない)
     │
     ├─ 別の視点 … 同じ重さの選択肢。見た体験は出さない
     └─ 今はやらない … 3時間は提案を控える。「断っても、何も減りません」
```

## 体験の樹

体験だけでできた、自分の場所です。ノートをリンクでつなぐアプリのように体験どうしがつながっていますが、置かれているのは文章ではなく、自分が生きた体験です。

```
            聴く ─ 遠くの音 ─ 音楽をひとつだけ
              │
   見る ──────●────── 味わう ─ ひと口目 ─ 食感 ─ 最後のひと口
  (根)    10の要素の根     ╲                      ⋮
              │            ╲ (朱の糸: 自分で結んだ体験どうし)
            休む ─ 遠くを見る休憩
```

- **10の要素**: 見る・聴く・嗅ぐ・味わう・触れる・動く・休む・考える・言葉にする・人と。それぞれに「いちばん小さなかたち」の根がある
- **つながり**: 体験ライブラリの94の体験が、深める・広げる・渡る (別の要素へ) の130のつながりで結ばれている
- **灯る・芽が出る**: 記した体験は朱の印になり、その先のまだやっていない体験が芽として呼吸する。提案も、芽を少しだけ前に出す
- **編む・結ぶ**: 自分で体験を書いて樹に植えられる (どこから伸ばすかも選べる)。響き合った体験どうしを朱の糸で結び、ひとこと添えられる
- **点数・レベル・解放の条件は無い**: どの体験も、いつでも始められる。樹は完成しない (編んだ体験と見つけた体験で、ずっと伸びる)
- **書き出せる**: 体験ごとのページが `[[リンク]]` でつながった Markdown のフォルダとして書き出せる。Obsidian などで開くと、グラフにこの樹がそのまま現れる

## そのほか

- **光と印**: 地はいまの時刻の空 (夜明け〜深夜の6つの空 × ライト/ダーク)。文字は藍墨、朱は印と「やってみる」「記す」にだけ使う
- **体験帳**: いつ何をしたかを、月の暦に押された印と日ごとの記録で。触れた要素に朱の印。連続記録・バッジ・ランキングは無い
- **アプリの外にも**: ウィジェット (今日の体験)、体験中の Live Activity、朝の便り (一日一度・その日すでに触れていれば送らない)、ショートカット
- **正直さ**: どのしくみが提案をつくったか (サーバーのAI / Apple Intelligence / 体験ライブラリ) をカードに出し、「次に渡す内容」を送る前に確かめられる。事実と推測は見た目で分ける

![体験の樹と、今日の体験](docs/screenshots/overview-light.jpg)
![夜の空 (ダーク)](docs/screenshots/overview-dark.jpg)

iPhone 17 Pro (iOS 26) のシミュレータで、UI テストが体験の流れをたどりながら撮った画面です。ほかの場面は [docs/screenshots](docs/screenshots)。
デザインの原則は [docs/DESIGN.md](docs/DESIGN.md)。ブラウザで動く Web 版は [docs/prototype/taiken.html](docs/prototype/taiken.html) (ダウンロードして開く。同じ体験ライブラリと選び方で、樹・体験のページ・編む・結ぶまで動きます)。

## 構成

```
contracts/   API契約 (OpenAPI + フィクスチャ)、体験ライブラリと10の要素 (content.ja.json)、選び方の共通テストケース
backend/     Node.js 22 + TypeScript (実行時の依存なし)。Docker / compose 付き
ios/
  TaikenCore/    UIに依存しない中核 (Swift 6)。ViewModel・体験の樹・体験ライブラリ・安全確認・通知判断・傾向計算
  Taiken/        アプリ (SwiftUI・SwiftData・EventKit・Keychain・通知・位置・App Intents・Apple Intelligence)
  TaikenWidgets/ ウィジェットと Live Activity
  Shared/        アプリとウィジェットで共有する見た目と定義
docs/        DESIGN / ARCHITECTURE / SECURITY_PRIVACY / OPERATIONS / prototype (Web 版)
.github/     CI (Backend・Docker・Swift on Linux・Xcode) と IPA のビルド
```

## インストール

### IPA (署名なし) から

[Actions の IPA ワークフロー](.github/workflows/ipa.yml) が、`main` に push するたびに実機用の `Taiken-<version>-unsigned.ipa` を作ります (Actions の成果物と `ci-results` ブランチ)。
署名されていないので、そのままでは iPhone に入りません。次のどれかで自分の Apple ID で署名して入れます。

- **Sideloadly / AltStore** (Mac / Windows): IPA を読み込み、自分の Apple ID で署名して転送する。無料の Apple ID では7日ごとに入れ直しが必要
- **Xcode から直接** (Mac): 下の「ソースから」の手順で、自分の Team で実機に入れる (ウィジェットの共有まで完全に動くのはこの方法)

> 署名し直すツールは App Group の ID を書き換えることがあります。その場合、アプリは問題なく動きますが、ウィジェットには日付とひとことだけが表示されます。

### ソースから (Xcode 16 以上・Mac)

```bash
brew install xcodegen
cd ios && xcodegen generate && open Taiken.xcodeproj
```

Signing の Team とバンドルIDは `ios/Config/Local.xcconfig` に書きます (gitには入りません)。App Group は `group.<バンドルID>` になります。

```
TAIKEN_DEVELOPMENT_TEAM = ABCDE12345
TAIKEN_BUNDLE_ID = jp.yourname.taiken
```

無料の Apple ID (Personal Team) で「App Groups に対応していない」と署名に失敗するときは、同じファイルに次の2行を足すと App Group なしで入れられます (アプリは動き、ウィジェットには日付とひとことだけが出ます)。

```
TAIKEN_APP_ENTITLEMENTS =
TAIKEN_WIDGET_ENTITLEMENTS =
```

サーバーが無くても、体験ライブラリ (10の要素・94の体験) で動きます。iOS 26 以降の Apple Intelligence 対応機種では、端末内のAIが提案をつくります。

## 自分のサーバーのAIを使う (任意)

```bash
cd backend
npm install
npm run start:mock                    # APIキー無しで全体を試す (http://localhost:8787)
```

本番は `backend/.env` に `ANTHROPIC_API_KEY` と `CLIENT_TOKENS` (`npm run token` で作る) を書き、`docker compose up -d --build`。
Tailscale で iPhone からだけ繋がるようにし、アプリの「設定 → 自分のサーバー」で URL とトークンを保存します。手順は [docs/OPERATIONS.md](docs/OPERATIONS.md)。

## 品質の確認

| 対象 | 方法 | 結果 |
|---|---|---|
| Backend | `npm run check`: TypeScript strict の型検査と、テスト110件。カバレッジのしきい値付き | 全件成功 |
| iOS 中核 | `swift test`: Swift 6 言語モード、テスト172件 (体験の樹の組み立て・芽・配置・編む・結ぶ・書き出しを含む) | 全件成功 |
| 契約 | Backend と iOS が同じ `contracts/` を検証。Backend は実際の出力も OpenAPI で検証 | 一致 |
| 体験ライブラリ | `contracts/content.ja.json` を正として iOS・Backend・Web 版にコピーし、一致を確認。`check_content.py` が、つながりの行き先・根・要素・季節の言葉が無いことを確かめる。選び方は Python の基準実装から作った16ケースを、Swift・TypeScript・Web 版の JavaScript が同じ結果で通る | 一致 |
| アプリ層 | `TaikenTests` をシミュレータで: SwiftData の保存と v1 / v2 → v3 移行 (体験帳が失われず、古い記録も樹の上の位置が見つかる)、ディープリンク、依存の組み立て、樹から始める、Markdown の書き出し、Keychain (署名なしの CI では省略) | 全件成功 |
| 画面の流れ | `TaikenUITests` をシミュレータ (iOS 26) で、ライト表示・ダーク表示の2回: はじめの案内 → 受け取る → 手がかり → 体験の樹 (一覧・体験のページ・編む) → やってみる → 思い返して記す → 印 → 樹に灯る → 体験帳 → 記録 → 話す → 設定。各場面を撮影 (`Screens` ワークフロー) | 全件成功 |
| 実機用ビルド | `IPA` ワークフロー: Xcode 26 / iOS 26 SDK でアプリとウィジェット拡張をビルドし、署名なしの IPA にまとめる | 成功 |
