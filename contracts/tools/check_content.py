#!/usr/bin/env python3
"""content.ja.json (体験ライブラリと要素) の形と約束ごとを確かめる。
sync.sh から呼ばれる。問題があれば一覧を出して止まる。

確かめること
- 要素は10個。ひと文字の印 (glyph) と、根になる体験を持つ
- 体験の id と名前が重ならない。文の約束 (誘いかけ・問い) を守っている
- 要素・テーマ・気分・時間帯・タグが決められた値だけ
- つながり (opens) の行き先が存在し、自分自身を指さず、重複しない
- どの体験も、どれかの根からつながりをたどって行き着ける (樹から離れた体験が無い)
"""
import json
import sys
from collections import deque

TAGS = {"new_perspective", "question", "small_challenge", "observation", "sensory", "reflection", "social", "creative",
        "competitive", "short", "long_duration"}
MOODS = {"tired", "bored", "focus", "refresh"}
TIMES = {"dawn", "morning", "daytime", "evening", "night", "lateNight"}
KINDS = {"deepen", "widen", "cross"}


def check(content):
    problems = []
    if content.get("version") != 2:
        problems.append("version は 2")
    elements = content.get("elements", [])
    element_ids = [e["id"] for e in elements]
    if len(elements) != 10 or len(set(element_ids)) != 10:
        problems.append("要素はちょうど10個 (id が重ならない)")
    if len({e["glyph"] for e in elements}) != len(elements):
        problems.append("要素の印 (glyph) が重なっている")
    themes = {t["id"] for t in content.get("themes", [])}
    experiences = content.get("experiences", [])
    by_id = {e["id"]: e for e in experiences}
    if len(by_id) != len(experiences):
        problems.append("体験の id が重なっている")
    if len({e["title"] for e in experiences}) != len(experiences):
        problems.append("体験の名前が重なっている")

    for el in elements:
        if len(el["glyph"]) != 1:
            problems.append(f"{el['id']}: 印はひと文字")
        root = by_id.get(el["root"])
        if not root:
            problems.append(f"{el['id']}: 根 {el['root']} が無い")
        elif root["elements"][0] != el["id"]:
            problems.append(f"{el['id']}: 根 {el['root']} の主な要素が {el['id']} ではない")
        if not el.get("keywords"):
            problems.append(f"{el['id']}: keywords が空")

    for e in experiences:
        i = e["id"]
        if "ませんか？" not in e["invitation"]:
            problems.append(f"{i}: 誘いかけは「〜ませんか？」の形")
        q = e["reflection_question"]
        if not q.endswith("？") or len(q) > 30:
            problems.append(f"{i}: 問いは30文字以内で「？」で終える")
        if not (1 <= len(e["tags"]) <= 4) or not set(e["tags"]) <= TAGS:
            problems.append(f"{i}: tags")
        if not e["themes"] or not set(e["themes"]) <= themes:
            problems.append(f"{i}: themes")
        if not set(e["moods"]) <= MOODS:
            problems.append(f"{i}: moods")
        if not set(e["times"]) <= TIMES:
            problems.append(f"{i}: times")
        if e["effort"] not in ("low", "medium"):
            problems.append(f"{i}: effort")
        els = e.get("elements", [])
        if not (1 <= len(els) <= 3) or len(set(els)) != len(els) or not set(els) <= set(element_ids):
            problems.append(f"{i}: elements は1〜3個の要素")
        seen = set()
        for link in e.get("opens", []):
            to, kind = link.get("to"), link.get("kind")
            if to not in by_id:
                problems.append(f"{i}: つながりの行き先 {to} が無い")
            if to == i:
                problems.append(f"{i}: 自分自身へのつながり")
            if kind not in KINDS:
                problems.append(f"{i}: つながりの種類 {kind}")
            if to in seen:
                problems.append(f"{i}: {to} へのつながりが重なっている")
            seen.add(to)
        for word in ("季節", "立春", "立夏", "立秋", "立冬", "節気", "七十二候"):
            if word in e["title"] + e["perspective"] + e["invitation"] + e["reflection_question"]:
                problems.append(f"{i}: 季節の言葉 ({word}) は使わない")

    # 根からたどって、すべての体験に行き着ける
    roots = [el["root"] for el in elements if el["root"] in by_id]
    reached = set(roots)
    queue = deque(roots)
    while queue:
        current = queue.popleft()
        for link in by_id[current].get("opens", []):
            if link["to"] in by_id and link["to"] not in reached:
                reached.add(link["to"])
                queue.append(link["to"])
    lost = sorted(set(by_id) - reached)
    if lost:
        problems.append(f"根から行き着けない体験: {', '.join(lost)}")

    counts = {el: 0 for el in element_ids}
    for e in experiences:
        if e.get("elements"):
            counts[e["elements"][0]] = counts.get(e["elements"][0], 0) + 1
    for el, n in counts.items():
        if n < 6:
            problems.append(f"{el}: 主な要素にしている体験が少ない ({n})")
    return problems, counts


def main(path):
    content = json.load(open(path, encoding="utf-8"))
    problems, counts = check(content)
    if problems:
        print("content.ja.json に直すところがあります:")
        for p in problems:
            print(" -", p)
        sys.exit(1)
    summary = " ".join(f"{el['glyph']}{counts[el['id']]}" for el in content["elements"])
    links = sum(len(e["opens"]) for e in content["experiences"])
    print(f"体験 {len(content['experiences'])} ・ つながり {links} ・ 要素ごと {summary}")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "content.ja.json")
