# 体験 — AI体験生成プラットフォーム

> AIが人生を代わりに生きるのではなく、AIが日常の中から「次の体験」を見つけ、人間自身がそれを生きる。

日常の予定・会話・これまでの反応から、いつもの行動を「別の視点・問い・小さな挑戦」として捉え直す提案を1つ出す iOS アプリと、その Backend です。
利用者は自分ひとりを前提にしつつ、設計・テスト・運用は業務システムと同じ水準にしています。

指示書の Step 1〜12 をすべて実装済みです。

- カレンダー
- 体験生成
- フィードバック
- 通知
- 必要時Web検索
- 履歴とパーソナライズ

## 構成

```
contracts/   API契約 (OpenAPI + フィクスチャ)。iOS と Backend の両方のテストが参照する
backend/     Node.js 22 + TypeScript (実行時の依存なし)。Docker / compose 付き
ios/
  TaikenCore/  UIに依存しない中核 (Swift 6)。ViewModel・通信・通知判断・傾向計算
  Taiken/      アプリ (SwiftUI・SwiftData・EventKit・Keychain・通知・位置)
docs/        ARCHITECTURE / SECURITY_PRIVACY / OPERATIONS
.github/     CI (Backend・Docker・Swift on Linux・Xcode)
```

## すぐ試す (APIキー不要)

```bash
# Backend (Node.js 22.18 以上)
cd backend
npm install
npm run start:mock                    # http://localhost:8787 (AIの代わりにルールベースで生成)

# iOS (Xcode 16 以上)
brew install xcodegen
cd ios && xcodegen generate && open Taiken.xcodeproj
```

Signing の Team は `ios/Config/Local.xcconfig` に書きます (gitには入りません)。

```
TAIKEN_DEVELOPMENT_TEAM = ABCDE12345
TAIKEN_BUNDLE_ID = jp.yourname.taiken
```

シミュレータは開発用の既定 `http://localhost:8787` に繋がります。Backend を動かしていなくても、アプリは端末内の簡易提案で動きます。

## 本番として使う

1. `backend/.env` に `ANTHROPIC_API_KEY` と `CLIENT_TOKENS` を設定する。トークンは `npm run token` で作る。
2. `docker compose up -d --build` で起動する。
3. Tailscale で iPhone からだけ繋がるようにする。手順は [docs/OPERATIONS.md](docs/OPERATIONS.md) を参照。
4. アプリの「設定」で接続先URLとトークンを保存し、接続テストする。トークンは Keychain に保存される。
5. 必要なら、同じ設定画面で次のものを個別にオンにする。
   - 通知
   - おおよその地域
   - 必要時Web検索

## 品質の確認

| 対象 | 方法 | 結果 |
|---|---|---|
| Backend | `npm run check`: TypeScript strict の型検査と、テスト89件。カバレッジのしきい値付き | 行100% / 分岐90% / 関数96% |
| iOS 中核 | `swift test`: Swift 6 言語モード、テスト74件 | 全件成功、コンパイラ警告0 |
| 契約 | Backend と iOS が同じ `contracts/` を検証。Backend は実際の出力も OpenAPI で検証 | 一致 |
| 結合 | 本番モードで起動した Backend に、iOS 中核の実物を接続して動かした | 成功 |
| ログ | 上の結合で出たサーバーログに、予定・発言・地域が含まれないことを確認 | 0件 |

結合テストでは、iOS 中核の次の部品を実物のまま使いました。

- `HomeViewModel`
- `ChatViewModel`
- `BackgroundCoordinator`
- `BackendClient`

確認した流れは次のとおりです。

- 体験の生成と「別の提案」
- 👍 の評価を履歴に保存
- チャットの提案を Home の「体験中」へ移す
- 苦痛のサインがあるときの相談先の案内
- バックグラウンド更新
- 誤ったトークンでの認証エラー
- サーバーが止まっているときの端末内提案への切り替え

**未検証のもの (この開発環境に Xcode・Docker が無いため)**

- SwiftUI 画面、SwiftData・EventKit・Keychain・通知・位置情報のアダプタを含むアプリのビルドと実行。
  - Xcode で `⌘B` と `⌘U` を実行してください。
  - CI の `ios-app` ジョブでも同じことを行います。
- Docker イメージのビルド。CI の `backend-image` ジョブで行います。
- 実際の Anthropic API との通信。リクエストの形・再試行・Web検索の応答処理は、模擬応答を使ったテストで確認しています。
