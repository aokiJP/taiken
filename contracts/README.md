# API契約 (iOS ⇄ Backend) と共有コンテンツ

`openapi.json` が契約の正です (version 2.0.0)。iOS と Backend は、このフォルダのファイルを両方のテストから読み込んで検証します。
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

## 2.0.0 での追加

| 項目 | 方向 | 内容 |
|---|---|---|
| `mood` | iOS → Backend | 自分で選んだいまの気分 (`tired` / `bored` / `focus` / `refresh`)。選んでいなければキーごと送らない |
| `season` | iOS → Backend | 二十四節気・七十二候・その意味。日付から決まる。Backend は表から引き直し、表に無い文言は捨てる |
| `experience.reflection_question` | Backend → iOS | 体験のあとに思い返す短い問い (null 可)。古い応答に無くても iOS は読める |

## 共有コンテンツ

| ファイル | 内容 | 検証 |
|---|---|---|
| `content.ja.json` | 体験ライブラリ (76件。二十四節気ごとの季節の体験を含む)、二十四節気、七十二候、テーマと気分のキーワード | iOS (`LibraryTests`) と Backend (`library.test.ts`) が、自分のコピーとバイト単位で一致することを確認 |
| `selection_cases.json` | 体験ライブラリの選び方のテストケース (14件) | 同じ入力に、iOS と Backend とプロトタイプが同じ体験を返すことを確認 |
| `tools/selection_reference.py` | 選び方の基準実装 (仕様)。`selection_cases.json` を作る | — |
| `tools/sync.sh` | `content.ja.json` を iOS と Backend にコピーし、テストケースを作り直す | — |

体験や文言を変えるときは、`content.ja.json` を直して `sh tools/sync.sh` を実行し、`swift test` (ios/TaikenCore) と `npm run check` (backend) を流します。
選び方を変えるときは、まず `selection_reference.py` を直してテストケースを作り直し、Swift (`LibrarySelector.swift`) と TypeScript (`library.ts`) を合わせます。

体験の文は次の約束で書きます (`docs/DESIGN.md` の「言葉づかい」)。

- 誘いかけは「〜してみませんか？」で終え、目を向ける対象をひとつだけ具体的に含める。時刻・分数・手順は指定しない
- 視点は「〜ではなく、〜として」の形の一文
- 振り返りの問いは30文字以内で「？」で終える。評価や反省を迫らない
