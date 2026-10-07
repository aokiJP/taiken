# API契約 (iOS ⇄ Backend)

`openapi.json` が契約の正です。iOS と Backend は、このフォルダのファイルを両方のテストから読み込んで検証します。
片方だけ形を変えると、どちらかのテストが落ちます。

| 検証 | 場所 |
|---|---|
| フィクスチャが OpenAPI のスキーマに一致する | `backend/test/contract.test.ts` |
| Backend の実際の出力 (AI / モック / 代替生成 / HTTP応答) が OpenAPI に一致する | `backend/test/contract.test.ts`, `server.test.ts` |
| iOS の型がフィクスチャを読める・iOS が送る JSON がフィクスチャと完全一致する | `ios/TaikenCore/Tests/TaikenCoreTests/ContractTests.swift` |

| ファイル | 方向 | エンドポイント |
|---|---|---|
| `experience_request.sample.json` | iOS → Backend | `POST /v1/experience` |
| `experience_response.sample.json` | Backend → iOS | `POST /v1/experience` |
| `chat_request.sample.json` | iOS → Backend | `POST /v1/chat` |
| `chat_response.sample.json` | Backend → iOS | `POST /v1/chat` |
| `status_response.sample.json` | Backend → iOS | `GET /v1/status` |
| `error_response.sample.json` | Backend → iOS | すべて (エラー時) |

キーはすべて snake_case。iOS 側は `convertFromSnakeCase` / `convertToSnakeCase` で変換します。

## 推測と事実の区別

AIが状況について述べる項目には `basis` が付きます。

- `calendar` … カレンダーに書かれている事実
- `stated` … ユーザーが自分で言った事実
- `inferred` … AIの推測 (UIでは「推測」ラベルと斜体で表示)

未知の値はどちらの側でも `inferred` として扱います (推測を事実にしない)。
`possible_obligations` はすべて推測扱いで、`likelihood` (0〜1) を持ちます。

## 互換性の方針

- フィールドの追加は後方互換。iOS は新しいフィールドが無い古い応答も読めるようにしている (`ContractTests.testDecodesOlderResponsesWithoutNewFields`)
- 列挙値の追加は、iOS 側で安全な既定値 (推測・low・unknown) に倒れる
- 削除・意味の変更をするときは `/v2` を作る
