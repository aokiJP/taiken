# API契約 (iOS ⇄ Backend) と共有コンテンツ

`openapi.json` が契約の正です (version 3.0.0。アプリ 4.0 でも形は変えていません)。iOS と Backend は、このフォルダのファイルを両方のテストから読み込んで検証します。
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
API の名前は `experience` のままですが、アプリの画面ではこれを「きっかけ」と呼びます (求められたときだけ作るひとつの提案)。

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

## 4.0 (技の樹) での変更

形は変えていません。`tree` の中身を、iOS が技の樹から作るようになりました。Backend の受け取り方 (id の形と件数を確かめ、`buds` を少しだけ前に出し、`grows_from` は `lived` にある id だけ受け取る) は 3.0.0 と同じなので、古いアプリも新しいアプリも同じサーバーで動きます。

| 項目 | 方向 | 4.0 での中身 |
|---|---|---|
| `tree.lived` | iOS → Backend | 記したことのある体験ライブラリの体験 (最近のものから12件まで。`id`・`title`・`elements`)。自分で見つけて記した体験は、自分の言葉なので入れない |
| `tree.buds` | iOS → Backend | **技の稽古**: ユーザーが身につけた技・育てられる技の稽古になる体験ライブラリの id (16件まで)。何も身についていなければ、要素の根の体験。3.0 では「灯った体験の先の、まだやっていない体験 (芽)」だった |
| `experience.grows_from` | Backend → iOS | この体験が伸びている、記した体験の id (null 可)。`tree.lived` に無い id は Backend が捨てる |
| きっかけの理由 (`experience.reason`) | Backend → iOS | 技の稽古から選んだときも、どの技の稽古かは書かない (霧の中の技の名前を明かさないため)。どの技の稽古かは iOS がカードに添える |

技の樹そのもの (経験・段・芽・身についた技・閃き) はサーバーに送りません。`skills.ja.json` は iOS だけが使います。

## 3.0.0 での変更 (体験の樹)

| 項目 | 方向 | 内容 |
|---|---|---|
| `tree` | iOS → Backend | 樹のいま。`lived` と `buds` (中身は上の「4.0 での変更」)。体験帳を使う許可があるときだけ送り、無ければキーごと送らない。Backend は id の形 (英小文字・数字・ハイフン) と件数を確かめる |
| `experience.node_id` | Backend → iOS | 体験ライブラリから選んだときの体験の id (null 可)。AIが新しく作った体験は null |
| `experience.elements` | Backend → iOS | 体験の要素 (1〜3個。先頭が主な要素)。10の要素の id だけ |
| `experience.grows_from` | Backend → iOS | この体験が伸びている体験の id (null 可) |
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
| `skills.ja.json` | 技の樹 (version 1): 93の技 (要素ごとに 一の技3・二の技3・奥義1、渡り技14、閃き9)。名前・読み・できるようになること・先の技・要る段・稽古 (体験ライブラリの id)・手がかりの言葉、閃きの条件と「閃いたとき」、守破離の境目 (破 3・離 7) | iOS (`SkillBookTests`) が自分のコピーとバイト単位で一致することを確認 (Backend は使わない) |
| `selection_cases.json` | 体験ライブラリの選び方のテストケース (16件。技の稽古 (buds) のある場合を含む) | 同じ入力に、iOS と Backend が同じ体験を返すことを確認 |
| `tools/check_content.py` | `content.ja.json` の約束ごとの検査 (要素と根・つながりの行き先・根からたどれること・文の形・季節の言葉が無いこと) | `sync.sh` の最初に実行 |
| `tools/check_skills.py` | `skills.ja.json` の約束ごとの検査 (要素ごとの形・先の技が輪にならず根からたどれること・稽古がライブラリにあり、ライブラリのどの体験もどれかの技の稽古であること・名前が体験ライブラリの体験と重ならないこと・言葉の約束・閃きの条件の形) | `sync.sh` で `check_content.py` の次に実行 |
| `tools/selection_reference.py` | 選び方の基準実装 (仕様)。`selection_cases.json` を作る | — |
| `tools/sync.sh` | 検査してから、`content.ja.json` を iOS・Backend に、`skills.ja.json` を iOS にコピーし、テストケースを作り直す (Python は `-I` で動かす) | — |

体験・技・文言・つながりを変えるときは、`content.ja.json` か `skills.ja.json` を直して `sh tools/sync.sh` を実行し、`swift test` (ios/TaikenCore) と `npm run check` (backend) を流します。
選び方を変えるときは、まず `selection_reference.py` を直してテストケースを作り直し、Swift (`LibrarySelector.swift`) と TypeScript (`library.ts`) を合わせます。

体験 (稽古・きっかけ) の文は次の約束で書きます (`docs/DESIGN.md` の「言葉づかい」)。

- 誘いかけは「〜してみませんか？」で終え、目を向ける対象をひとつだけ具体的に含める。時刻・分数・手順は指定しない
- 視点は「〜ではなく、〜として」の形の一文
- 振り返りの問いは30文字以内で「？」で終える。評価や反省を迫らない

技の文は次の約束で書きます。

- 技は「やること」ではなく、身につく見方や力。名前は見方や力の名前にし (10文字まで・読みはひらがな)、体験ライブラリの体験と同じ名前にしない
- できるようになることは40文字までの一文で「。」で終え、身についたあとの自分を「〜できる」「〜が分かる」のように書く。命令・お題にしない。名前を繰り返さない。段の数 (一段・三段 …) や、芽・結ぶ のようなアプリの言葉と紛れる言い方をしない
- 閃きの「閃いたとき」は「〜とき」で書く。条件は暮らし方の組み合わせだけ (期限・連続・回数を競う条件は作らない)
- 季節の言葉は使わない
- id は変えない (身についた技・使った技は、端末に id で保存されている)。名前や言葉は変えてよい

つながりは次の約束で張ります。

- `deepen` は同じ要素の中で、同じ対象をより細やかに見る (今朝の光 → 影のかたち)
- `widen` は同じ要素の中で、別の場面へ移す (目に留まるもの → 今日の色をさがす)
- `cross` は別の要素へ渡る (いつもと違う棚 → 知らない一品)
- どの体験も、どれかの根からたどり着けるようにする。根は、その要素の「いちばん小さなかたち」の体験
