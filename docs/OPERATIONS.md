# 運用ガイド (個人サーバー)

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

iPhone の「体験」アプリ → 設定 → 接続先に `https://<マシン名>.<tailnet>.ts.net` とトークンを入れて「保存して接続テスト」。

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
| アプリに「簡易的な提案です」と出る | `/v1/status` の残り予算、ログの `fallback_reason` |
| 接続テストで「認証されませんでした」 | `CLIENT_TOKENS` とアプリのトークンが一致しているか |
| 実機から localhost に繋がらない | 実機の localhost は iPhone 自身。Mac の IP か Tailscale のホスト名を使う |
| 通知が来ない | iOS の通知許可、アプリ内の通知設定 (静かな時間・上限)、バックグラウンド更新は iOS が実行時期を決めるため数時間かかることがある (シミュレータでは動かない) |
| 起動しない (終了コード 78) | 標準エラーに設定の問題が列挙される |

## 更新

```bash
git pull
cd backend && docker compose up -d --build
```

使用量ファイル以外に状態を持たないので、バックアップは不要です。
