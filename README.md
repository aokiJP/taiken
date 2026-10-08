# 体験 — いつもの一日に、まだ見ていない体験がある

> AIが人生を代わりに生きるのではなく、AIが日常の中から「次の体験」を見つけ、人間自身がそれを生きる。

予定・気分・季節から、いつもの行動を「別の視点・問い・小さな挑戦」として捉え直す誘いかけを、**ひとつだけ**差し出す iOS アプリと、その Backend です。
サーバーが無くても、端末の中だけで最後まで使えます (体験ライブラリ / iOS 26 の Apple Intelligence)。

## 体験の流れ

```
受け取る ──▶ やってみる ──▶ 思い返す ──▶ 印を押す ──▶ ひと休み
 (今日の体験)   (体験中: ロック画面にも)  (問いに答えて、ひとこと)  (体験帳に朱の印)   (押しつけない)
     │
     ├─ 別の視点 … 同じ重さの選択肢。見た体験は出さない
     └─ 今はやらない … 3時間は提案を控える。「断っても、何も減りません」
```

- **光と印**: 地はいまの時刻の空 (夜明け〜深夜の6つの空 × ライト/ダーク)。文字は藍墨、朱は印と「やってみる」「記す」にだけ使う
- **七十二候**: 今日の候を縦書きの短冊で。二十四節気ごとに季節の体験がある (日付から計算するので許可は不要)
- **体験帳**: 七十二候の輪に、体験を記した候が朱で灯る。月の暦に押された印。連続記録・バッジ・ランキングは無い
- **アプリの外にも**: ウィジェット (今日の体験・七十二候)、体験中の Live Activity、朝の便り (一日一度・その日すでに触れていれば送らない)、ショートカット
- **正直さ**: どのしくみが提案をつくったか (サーバーのAI / Apple Intelligence / 体験ライブラリ) をカードに出し、「次に渡す内容」を送る前に確かめられる。事実と推測は見た目で分ける

デザインの原則は [docs/DESIGN.md](docs/DESIGN.md)。ブラウザで動くプロトタイプは [docs/prototype/taiken.html](docs/prototype/taiken.html) (ダウンロードして開く)。

## 構成

```
contracts/   API契約 (OpenAPI + フィクスチャ)、体験ライブラリと七十二候 (content.ja.json)、選び方の共通テストケース
backend/     Node.js 22 + TypeScript (実行時の依存なし)。Docker / compose 付き
ios/
  TaikenCore/    UIに依存しない中核 (Swift 6)。ViewModel・季節・体験ライブラリ・安全確認・通知判断・傾向計算
  Taiken/        アプリ (SwiftUI・SwiftData・EventKit・Keychain・通知・位置・App Intents・Apple Intelligence)
  TaikenWidgets/ ウィジェットと Live Activity
  Shared/        アプリとウィジェットで共有する見た目と定義
docs/        DESIGN / ARCHITECTURE / SECURITY_PRIVACY / OPERATIONS / prototype
.github/     CI (Backend・Docker・Swift on Linux・Xcode) と IPA のビルド
```

## インストール

### IPA (署名なし) から

[Actions の IPA ワークフロー](.github/workflows/ipa.yml) が、`main` に push するたびに実機用の `Taiken-<version>-unsigned.ipa` を作ります (Actions の成果物と `ci-results` ブランチ)。
署名されていないので、そのままでは iPhone に入りません。次のどれかで自分の Apple ID で署名して入れます。

- **Sideloadly / AltStore** (Mac / Windows): IPA を読み込み、自分の Apple ID で署名して転送する。無料の Apple ID では7日ごとに入れ直しが必要
- **Xcode から直接** (Mac): 下の「ソースから」の手順で、自分の Team で実機に入れる (ウィジェットの共有まで完全に動くのはこの方法)

> 署名し直すツールは App Group の ID を書き換えることがあります。その場合、アプリは問題なく動きますが、ウィジェットにはその日の季節だけが表示されます。

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

サーバーが無くても、体験ライブラリ (76の体験・七十二候) で動きます。iOS 26 以降の Apple Intelligence 対応機種では、端末内のAIが提案をつくります。

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
| Backend | `npm run check`: TypeScript strict の型検査と、テスト105件。カバレッジのしきい値付き | 行100% / 分岐93% / 関数95% |
| iOS 中核 | `swift test`: Swift 6 言語モード、テスト138件 (季節の計算は国立天文台の2026年の暦と照合) | 全件成功 |
| 契約 | Backend と iOS が同じ `contracts/` を検証。Backend は実際の出力も OpenAPI で検証 | 一致 |
| 体験ライブラリ | `contracts/content.ja.json` を正として iOS・Backend にコピーし、バイト単位で一致を確認。選び方は Python の基準実装から作った14ケースを、Swift・TypeScript・プロトタイプの JavaScript が同じ結果で通る | 一致 |
| アプリ・ウィジェット | CI の `ios-app` (シミュレータでビルドとテスト) と `IPA` (実機用ビルド) | Actions で確認 |

アプリ層のテスト (`ios/TaikenTests`) は、SwiftData の v1 → v2 移行で体験帳が失われないこと、Keychain、ディープリンクなどを確認します。
