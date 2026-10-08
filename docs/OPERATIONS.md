# 運用ガイド (個人サーバー)

サーバーは任意です。アプリは接続先が無くても、体験ライブラリ (iOS 26 の対応機種では Apple Intelligence) で最後まで動きます。
ここでは、自分のサーバーのAIできっかけをつくりたいときの運用をまとめます。技の樹は端末の中だけにあり、サーバーには関係しません。

## 置き場所のおすすめ

自宅の Mac / PC か小さな VPS で Docker を動かし、**Tailscale** で iPhone とだけつなぐ構成をすすめます。
インターネットに公開しないので、攻撃面がほぼ無くなります。

```
iPhone (Tailscale) ──https──▶ tailscale serve ──▶ 127.0.0.1:8787 (Docker の Backend)
```

### 手順

```bash
cd backend
cp .env.example .env
npm run token            # 出てきた値を .env の CLIENT_TOKENS に入れる (Node.js が無ければ: openssl rand -base64 32)
# .env に ANTHROPIC_API_KEY を入れる
docker compose up -d --build
curl http://127.0.0.1:8787/health          # {"status":"ok"}

# Tailscale で HTTPS 公開 (同じ tailnet の端末からだけ見える)
tailscale serve --bg --https=443 http://127.0.0.1:8787
# → https://<マシン名>.<tailnet>.ts.net が接続先
```

iPhone の「体験」アプリ → 設定 → 自分のサーバー に `https://<マシン名>.<tailnet>.ts.net` とトークンを入れて「保存して接続を確かめる」。

> Tailscale を使わず公開する場合は、Caddy などで HTTPS 終端し、`CLIENT_TOKENS` を必ず設定してください。

## 主な設定 (.env)

| 変数 | 既定 | 説明 |
|---|---|---|
| `NODE_ENV` | development | production ではキーとトークンが無いと起動しない (終了コード 78) |
| `AI_PROVIDER` | anthropic | `mock` でAIなしに全体を動かせる |
| `AI_MODEL_EXPERIENCE` / `AI_MODEL_CHAT` / `AI_MODEL_RESEARCH` | sonnet / haiku / haiku | 体験生成は質、会話と下調べは費用を優先 |
| `WEB_SEARCH_ENABLED` | false | true でも、アプリ側で許可したときだけ使う |
| `DAILY_AI_REQUEST_LIMIT` / `DAILY_AI_TOKEN_LIMIT` / `DAILY_WEB_SEARCH_LIMIT` | 200 / 500000 / 20 | 1日の上限。超えるとAIを呼ばず代替生成 |
| `BUDGET_TIME_ZONE` | Asia/Tokyo | 上限がリセットされる「0時」の基準 |
| `DATA_DIR` | ./data (Docker では /data) | 使用量の保存先。再起動しても当日分を引き継ぐ |
| `CLIENT_TOKENS` | — | カンマ区切りで複数可 (ローテーション用) |
| `RATE_LIMIT_BURST` / `RATE_LIMIT_PER_MINUTE` | 10 / 20 | トークンごとのレート制御 |
| `MAX_CONCURRENT_AI` | 4 | AIの同時呼び出し数。超えると代替生成 |
| `LOG_LEVEL` | info | debug にすると AI API の応答時間なども出る |

モデル名は Anthropic のドキュメントで最新のものを確認してください。

## 監視

- `GET /health` … 生存確認 (Docker の HEALTHCHECK でも使用)
- `GET /v1/status` (要トークン) … 今日の残り予算、Web検索の有効/無効
- ログは JSON Lines。`docker compose logs -f backend | jq` で読める。主なイベント:
  - `http.request` … 1リクエスト1行 (`source`, `fallback_reason`, `ms`, `request_id`)
  - `engine.skipped_ai` … 予算切れ・遮断中・混雑でAIを呼ばなかった
  - `engine.primary_failed` / `ai.retry` … 上流の失敗と再試行
- iOS の診断ログは Console.app で subsystem をアプリのバンドルIDで絞る。`request_id` で Backend のログと突き合わせられる。

## よくある問題

| 症状 | 確認すること |
|---|---|
| きっかけのカードに「体験ライブラリ」と出る | 接続先が未設定なら正常 (端末内で選んでいる)。接続しているのに出るなら `/v1/status` の残り予算、ログの `fallback_reason`、ホームの一行の案内 |
| Apple Intelligence できっかけがつくられない | iOS 26 以降・対応機種・設定で Apple Intelligence がオン・モデルのダウンロード済みか。接続先を保存しているとサーバーが優先される |
| ウィジェットに日付とひとことしか出ない | 体験中でなく、きっかけももらっていなければ正常 (押すと「体験を記す」がひらく。日付が変わると日付とひとことに戻る)。自分でビルドした場合は、アプリとウィジェットの両方で同じ App Group が有効か |
| 記したのに経験が積もらない・段が下がった | 記録が触れた要素に経験が積もる (自分で記すときは要素を1〜3つ選ぶ。3.0 より前の記録は名前と文から推し量る)。記録を削除すると、そのぶんの経験も消える (身についた技と閃きは残る) |
| ロック画面に体験中の表示が出ない | 設定 → ロック画面とウィジェット、iOS の設定 → 体験 → ライブアクティビティ |
| 接続テストで「認証されませんでした」 | `CLIENT_TOKENS` とアプリのトークンが一致しているか |
| 実機から localhost に繋がらない | 実機の localhost は iPhone 自身。Mac の IP か Tailscale のホスト名を使う |
| 通知が来ない | iOS の通知許可、アプリ内の通知設定 (どちらも既定はオフ・静かな時間・上限)。朝の便りはその日すでに体験に触れていると届かない。「ちょうどよい時に知らせる」はバックグラウンド更新の時期を iOS が決めるため数時間かかることがある (シミュレータでは動かない) |
| 起動しない (終了コード 78) | 標準エラーに設定の問題が列挙される |

## 更新

```bash
git pull
cd backend && docker compose up -d --build
```

体験ライブラリや技の樹の文言・つながりを変えたときは、`contracts/tools/sync.sh` で検査し、iOS・Backend にコピーしてから、両方のテストを流します。

## IPA を作る

`main` に push すると `.github/workflows/ipa.yml` が実機用の署名なし IPA を作り、Actions の成果物と `ci-results` ブランチに置きます (手動実行もできる)。
自分の Mac で作るなら、`ios` で `xcodegen generate` したあと Xcode の Product → Archive で書き出すか、ワークフローと同じ `xcodebuild` を実行します。

使用量ファイル以外に状態を持たないので、バックアップは不要です。
