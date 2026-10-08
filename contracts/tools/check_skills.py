#!/usr/bin/env python3
"""skills.ja.json (技の樹) の形と約束ごとを、content.ja.json (要素と体験ライブラリ) と突き合わせて確かめる。
sync.sh から呼ばれる。問題があれば一覧を出して止まる。

確かめること
- 技の id と名前が重ならない。id は英小文字・数字・ハイフン
- 要素ごとに、一の技 (一段) 3つ・二の技 (三段) 3つ・奥義 (六段) 1つ。二の技は一の技の先、奥義は二の技の先
- 渡り技は、ふたつの要素のどちらも段を求め、どちらかの技の先にある
- 閃きは条件 (flash) と「閃いたとき」の一文を持ち、先の技・段・稽古を持たない
- 先にあるとよい技 (after) が存在し、輪にならない。どの技も根からたどれる
- 稽古はすべて体験ライブラリの体験。ライブラリのどの体験も、どれかの技の稽古になっている
- 技の名前は、体験ライブラリの体験の名前と重ならない (技は「やること」ではなく、身につく見方や力)
- できるようになること (ability) は「。」で終わる短い一文。段の数 (一段・三段 …) と季節の言葉は使わない
"""
import json
import re
import sys

KINDS = {"art", "secret", "cross", "flash"}
FLASH_KEYS = {"senses", "elements", "times", "element", "bands", "all_elements", "days", "self", "ties", "mastered"}
TIMES = {"dawn", "morning", "daytime", "evening", "night", "lateNight"}
SEASON_WORDS = ("季節", "立春", "立夏", "立秋", "立冬", "節気", "七十二候", "旬", "春", "夏", "秋", "冬")
ID = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
KANA = re.compile(r"^[ぁ-ゖー]+$")
# 段は要素の深さを表すアプリの言葉なので、できるようになることの中では「一段深く」のようには使わない
RANK_WORD = re.compile(r"[一二三四五六七八九十]段")


def check(skills_doc, content):
    problems = []
    if skills_doc.get("version") != 1:
        problems.append("version は 1")
    mastery = skills_doc.get("mastery", {})
    if not (isinstance(mastery.get("ha"), int) and isinstance(mastery.get("ri"), int) and 0 < mastery["ha"] < mastery["ri"]):
        problems.append("mastery は 0 < ha < ri の整数")
    elements = [e["id"] for e in content["elements"]]
    library = {e["id"] for e in content["experiences"]}
    library_titles = {e["title"] for e in content["experiences"]}
    skills = skills_doc.get("skills", [])
    by_id = {}
    for s in skills:
        if s["id"] in by_id:
            problems.append(f"{s['id']}: id が重なっている")
        by_id[s["id"]] = s
    names = [s["name"] for s in skills]
    if len(set(names)) != len(names):
        problems.append("技の名前が重なっている")

    for s in skills:
        i = s["id"]
        kind = s.get("kind")
        if not ID.match(i):
            problems.append(f"{i}: id は英小文字・数字・ハイフン")
        if kind not in KINDS:
            problems.append(f"{i}: kind {kind}")
        if s.get("element") not in elements:
            problems.append(f"{i}: element {s.get('element')}")
        also = s.get("also", [])
        if not set(also) <= set(elements) or s.get("element") in also:
            problems.append(f"{i}: also は別の要素")
        if not (1 <= len(s["name"]) <= 10):
            problems.append(f"{i}: 名前は10文字まで")
        if s["name"] in library_titles:
            problems.append(f"{i}: 名前「{s['name']}」が体験ライブラリの体験と同じ (技は見方や力の名前にする)")
        if not KANA.match(s.get("reading", "")):
            problems.append(f"{i}: 読みはひらがな")
        ability = s.get("ability", "")
        if not ability.endswith("。") or len(ability) > 40:
            problems.append(f"{i}: ability は40文字までの、「。」で終わる一文")
        if RANK_WORD.search(ability):
            problems.append(f"{i}: ability に段の数を書かない (段は要素の深さの言葉)")
        text = s["name"] + ability + s.get("found", "")
        for word in SEASON_WORDS:
            if word in text:
                problems.append(f"{i}: 季節の言葉 ({word}) は使わない")
        for p in s.get("practice", []):
            if p not in library:
                problems.append(f"{i}: 稽古 {p} がライブラリに無い")
        for a in s.get("after", []):
            if a not in by_id:
                problems.append(f"{i}: 先の技 {a} が無い")
            if a == i:
                problems.append(f"{i}: 自分自身が先の技")
        needs = s.get("needs", 0)
        if not (0 <= needs <= len(s.get("after", []))) or (s.get("after") and needs == 0):
            problems.append(f"{i}: needs は after の数まで (after があれば1以上)")
        rank = s.get("rank", {})
        if not set(rank) <= set(elements) or not all(isinstance(v, int) and 1 <= v <= 10 for v in rank.values()):
            problems.append(f"{i}: rank は要素ごとの段 (1〜10)")

        if kind == "flash":
            rule = s.get("flash")
            if not isinstance(rule, dict) or not rule or not set(rule) <= FLASH_KEYS:
                problems.append(f"{i}: flash の条件")
            elif not set(rule.get("times", [])) <= TIMES:
                problems.append(f"{i}: flash の時間帯")
            if not s.get("found", "").endswith("とき"):
                problems.append(f"{i}: found は「〜とき」")
            if s.get("after") or rank or s.get("practice"):
                problems.append(f"{i}: 閃きは先の技・段・稽古を持たない")
        else:
            if "flash" in s or "found" in s:
                problems.append(f"{i}: 閃きでない技は flash / found を持たない")
            if not s.get("practice"):
                problems.append(f"{i}: 稽古がひとつも無い")
            if not s.get("keywords"):
                problems.append(f"{i}: keywords が空")
            if s["element"] not in rank:
                problems.append(f"{i}: 主な要素の段の条件が無い")
        if kind == "cross":
            if len(also) != 1 or also[0] not in rank:
                problems.append(f"{i}: 渡り技は、もう一方の要素の段も求める")
            sides = {by_id[a]["element"] for a in s.get("after", []) if a in by_id}
            if not sides <= {s["element"], *also} or not sides:
                problems.append(f"{i}: 渡り技は、ふたつの要素の技の先にある")

    # 要素ごとの形
    for el in elements:
        arts = [s for s in skills if s.get("element") == el and s.get("kind") == "art"]
        first = [s for s in arts if not s.get("after")]
        second = [s for s in arts if s.get("after")]
        secrets = [s for s in skills if s.get("element") == el and s.get("kind") == "secret"]
        if len(first) != 3 or len(second) != 3 or len(secrets) != 1:
            problems.append(f"{el}: 一の技3・二の技3・奥義1 (いまは {len(first)}・{len(second)}・{len(secrets)})")
        for s in first:
            if s.get("rank") != {el: 1}:
                problems.append(f"{s['id']}: 一の技は一段")
        for s in second:
            if s.get("rank") != {el: 3} or any(by_id.get(a, {}).get("element") != el for a in s["after"]):
                problems.append(f"{s['id']}: 二の技は三段で、同じ要素の一の技の先")
        for s in secrets:
            if s.get("rank") != {el: 6} or {a for a in s["after"]} != {x["id"] for x in second}:
                problems.append(f"{s['id']}: 奥義は六段で、同じ要素の二の技の先")

    # 輪にならない・根からたどれる
    reached = {s["id"] for s in skills if not s.get("after")}
    changed = True
    while changed:
        changed = False
        for s in skills:
            if s["id"] in reached:
                continue
            got = sum(1 for a in s.get("after", []) if a in reached)
            if got >= max(1, s.get("needs", 1)):
                reached.add(s["id"])
                changed = True
    lost = sorted(set(by_id) - reached)
    if lost:
        problems.append(f"根からたどれない技 (輪になっているかもしれない): {', '.join(lost)}")

    used = {p for s in skills for p in s.get("practice", [])}
    unused = sorted(library - used)
    if unused:
        problems.append(f"どの技の稽古にもなっていない体験: {', '.join(unused)}")
    return problems


def main(skills_path, content_path):
    skills_doc = json.load(open(skills_path, encoding="utf-8"))
    content = json.load(open(content_path, encoding="utf-8"))
    problems = check(skills_doc, content)
    if problems:
        print("skills.ja.json に直すところがあります:")
        for p in problems:
            print(" -", p)
        sys.exit(1)
    counts = {}
    for s in skills_doc["skills"]:
        counts[s["kind"]] = counts.get(s["kind"], 0) + 1
    print(f"技 {len(skills_doc['skills'])} ・ 一と二の技 {counts.get('art', 0)} ・ 奥義 {counts.get('secret', 0)}"
          f" ・ 渡り技 {counts.get('cross', 0)} ・ 閃き {counts.get('flash', 0)}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "skills.ja.json", sys.argv[2] if len(sys.argv) > 2 else "content.ja.json")
