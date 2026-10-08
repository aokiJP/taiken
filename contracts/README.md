# API契約 (iOS ⇄ Backend) と共有コンテンツ

`openapi.json` が契約の正です (version 3.0.0)。iOS と Backend は、このフォルダのファイルを両方のテストから読み込んで検証します。
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

## 3.0.0 での変更 (体験の樹)

| 項目 | 方向 | 内容 |
|---|---|---|
| `tree` | iOS → Backend | 体験の樹のいま。`lived` (灯った体験。最近のものから12件まで。`id`・`title`・`elements`) と `buds` (芽の id。16件まで)。体験帳を使う許可があるときだけ送り、無ければキーごと送らない。Backend は id の形 (英小文字・数字・ハイフン) と件数を確かめる |
| `experience.node_id` | Backend → iOS | 体験ライブラリから選んだときの体験の id (null 可)。AIが新しく作った体験は null |
| `experience.elements` | Backend → iOS | 体験の要素 (1〜3個。先頭が主な要素)。10の要素の id だけ |
| `experience.grows_from` | Backend → iOS | この体験が伸びている灯った体験の id (null 可)。`tree.lived` に無い id は Backend が捨てる |
| `season` (廃止) | — | 2.0.0 で送っていた季節。3.0.0 では送らず、古いアプリから届いても Backend は使わない |

## 2.0.0 での追加

| 項目 | 方向 | 内容 |
|---|---|---|
| `mood` | iOS → Backend | 自分で選んだいまの気分 (`tired` / `bored` / `focus` / `refresh`)。選んでいなければキーごと送らない |
| `experience.reflection_question` | Backend → iOS | 体験のあとに思い返す短い問い (null 可)。古い応答に無くても iOS は読める |

## 共有コンテンツ

| ファイル | 内容 | 検証 |
|---|---|---|
| `content.ja.json` | 体験ライブラリ (version 2): 10の要素 (字・名前・説明・根・言葉の手がかり)、94の体験、体験どうしのつながり130 (`opens`: `deepen` 深める / `widen` 広げる / `cross` 渡る)、テーマと気分のキーワード | iOS (`LibraryTests`) と Backend (`library.test.ts`) が、自分のコピーとバイト単位で一致することを確認 |
| `selection_cases.json` | 体験ライブラリの選び方のテストケース (16件。芽のある場合を含む) | 同じ入力に、iOS と Backend が同じ体験を返すことを確認 |
| `tools/check_content.py` | `content.ja.json` の約束ごとの検査 (要素と根・つながりの行き先・根からたどれること・文の形・季節の言葉が無いこと) | `sync.sh` の最初に実行 |
| `tools/selection_reference.py` | 選び方の基準実装 (仕様)。`selection_cases.json` を作る | — |
| `tools/sync.sh` | 検査してから、`content.ja.json` を iOS・Backend にコピーし、テストケースを作り直す | — |

体験や文言・つながりを変えるときは、`content.ja.json` を直して `sh tools/sync.sh` を実行し、`swift test` (ios/TaikenCore) と `npm run check` (backend) を流します。
選び方を変えるときは、まず `selection_reference.py` を直してテストケースを作り直し、Swift (`LibrarySelector.swift`) と TypeScript (`library.ts`) を合わせます。

体験の文は次の約束で書きます (`docs/DESIGN.md` の「言葉づかい」)。

- 誘いかけは「〜してみませんか？」で終え、目を向ける対象をひとつだけ具体的に含める。時刻・分数・手順は指定しない
- 視点は「〜ではなく、〜として」の形の一文
- 振り返りの問いは30文字以内で「？」で終える。評価や反省を迫らない

つながりは次の約束で張ります。

- `deepen` は同じ要素の中で、同じ対象をより細やかに見る (今朝の光 → 影のかたち)
- `widen` は同じ要素の中で、別の場面へ移す (目に留まるもの → 今日の色をさがす)
- `cross` は別の要素へ渡る (いつもと違う棚 → 知らない一品)
- どの体験も、どれかの根からたどり着けるようにする。根は、その要素の「いちばん小さなかたち」の体験
