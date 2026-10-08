#!/bin/sh
# contracts/content.ja.json (体験ライブラリと要素) と contracts/skills.ja.json (技の樹) を確かめてから
# iOS と Backend にコピーし、選び方のテストケースを作り直す。
# 体験ライブラリ・要素・つながり・技を変えたら、これを実行してから両方のテストを流す。
# 技の樹は iOS だけが使う (提案のしくみは体験ライブラリだけを使う)。
set -eu
cd "$(dirname "$0")/.."
python3 -I tools/check_content.py content.ja.json
python3 -I tools/check_skills.py skills.ja.json content.ja.json
cp content.ja.json ../ios/TaikenCore/Sources/TaikenCore/Resources/content.ja.json
cp skills.ja.json ../ios/TaikenCore/Sources/TaikenCore/Resources/skills.ja.json
cp content.ja.json ../backend/src/content/content.ja.json
python3 -I tools/selection_reference.py content.ja.json selection_cases.json
echo "同期しました。iOS: swift test / Backend: npm run check で確認してください。"
