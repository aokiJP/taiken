#!/bin/sh
# contracts/content.ja.json (正) を確かめてから iOS と Backend にコピーし、選び方のテストケースを作り直す。
# 体験ライブラリ・要素・つながりを変えたら、これを実行してから両方のテストを流す。
set -eu
cd "$(dirname "$0")/.."
python3 tools/check_content.py content.ja.json
cp content.ja.json ../ios/TaikenCore/Sources/TaikenCore/Resources/content.ja.json
cp content.ja.json ../backend/src/content/content.ja.json
python3 tools/selection_reference.py content.ja.json selection_cases.json
echo "同期しました。iOS: swift test / Backend: npm run check で確認してください。"
