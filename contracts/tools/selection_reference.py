#!/usr/bin/env python3
"""体験ライブラリの選び方の基準実装 (仕様)。
iOS (LibrarySelector.swift)・Backend (library.ts) はこれと同じ結果を返すことを、
contracts/selection_cases.json で検証する。

点数のつけ方
- 予定や発言から読んだ場面 (テーマ) に合う: +4。特定の場面向けの体験で、その場面が見当たらない: -2
- 気分に合う: +2.5
- 朝・夜の時間帯に合う: +1.5
- 体験の樹の「芽」(灯った体験からつながっている、まだやっていない体験): +1.5
- 最近の反応の傾向: タグごとに +weight (響いた) / -1.5×weight (合わなかった)
- 最近の体験: -3。疲れぎみで手間のかかる体験: -2
- 日ごとに決まる小さなゆらぎ (0〜0.9)
時間帯の合わない体験と、今回は出さない体験 (別の視点で見たもの) は候補から外す。
"""
import datetime as dt
import json
import sys

SPECIFIC = {"study", "work", "commute", "meal", "housework", "shopping", "people", "body"}


def fnv1a(text: str) -> int:
    h = 0x811C9DC5
    for b in text.encode("utf-8"):
        h ^= b
        h = (h * 0x01000193) & 0xFFFFFFFF
    return h


def jitter(entry_id: str, day: int) -> float:
    return (fnv1a(f"{entry_id}#{day}") % 1000) / 1000 * 0.9


def day_number(date_text: str) -> int:
    return (dt.date.fromisoformat(date_text) - dt.date(1970, 1, 1)).days


def detect_themes(content, texts):
    found = set()
    for theme in content["themes"]:
        if any(k in t for t in texts for k in theme["keywords"]):
            found.add(theme["id"])
    return found


def detect_mood(content, texts):
    for mood in content["moods"]:
        if any(k in t for t in texts for k in mood["keywords"]):
            return mood["id"]
    return None


def select(content, case):
    day = day_number(case["date"])
    tod = case["time_of_day"]
    texts_event = [case["event_title"]] if case.get("event_title") else []
    messages = case.get("messages", [])
    detected = detect_themes(content, texts_event) | detect_themes(content, messages)
    mood = case.get("mood") or detect_mood(content, messages)
    time_theme = "morning" if tod in ("dawn", "morning") else "night" if tod in ("night", "lateNight") else None
    feedback = case.get("feedback", [])
    recent = set(case.get("recent_titles", []))
    exclude = set(case.get("exclude_titles", []))
    buds = set(case.get("buds", []))

    def eligible(e, use_exclude=True):
        if use_exclude and e["title"] in exclude:
            return False
        if e["times"] and tod not in e["times"]:
            return False
        return True

    def score(e):
        s = 0.0
        if any(t in detected for t in e["themes"]):
            s += 4.0
        elif all(t in SPECIFIC for t in e["themes"]):
            s -= 2.0
        if mood and mood in e["moods"]:
            s += 2.5
        if time_theme and time_theme in e["themes"]:
            s += 1.5
        if e["id"] in buds:
            s += 1.5
        for tag in e["tags"]:
            for f in feedback:
                if f["tag"] == tag:
                    factor = 1.0 if f["rating"] == "positive" else (-1.5 if f["rating"] == "negative" else 0.0)
                    s += factor * f["weight"]
        if e["title"] in recent:
            s -= 3.0
        if mood == "tired" and e["effort"] == "medium":
            s -= 2.0
        s += jitter(e["id"], day)
        return s

    experiences = content["experiences"]
    candidates = [e for e in experiences if eligible(e)]
    if not candidates:
        candidates = [e for e in experiences if eligible(e, False)]
    if not candidates:
        candidates = experiences
    best, best_score = None, float("-inf")
    for e in candidates:
        s = score(e)
        if s > best_score:
            best, best_score = e, s
    return best["id"]


ROOTS = "__ROOTS__"
FIRST = "__FIRST__"

CASES = [
    {"name": "予定も気分も無い夕方", "date": "2026-10-08", "time_of_day": "evening"},
    {"name": "勉強の予定があれば勉強の体験", "date": "2026-10-08", "time_of_day": "evening", "event_title": "数学の課題"},
    {"name": "勉強の予定 + 疲れぎみなら軽いもの", "date": "2026-10-08", "time_of_day": "evening", "event_title": "数学の課題", "mood": "tired"},
    {"name": "朝 + 気分転換", "date": "2026-10-09", "time_of_day": "morning", "mood": "refresh"},
    {"name": "夜は夜の体験", "date": "2026-10-08", "time_of_day": "night"},
    {"name": "深夜", "date": "2026-10-08", "time_of_day": "lateNight"},
    {"name": "別の提案: 見た体験は除く", "date": "2026-10-08", "time_of_day": "evening", "exclude_titles": [FIRST]},
    {"name": "最近やった体験は後ろに回す", "date": "2026-10-08", "time_of_day": "evening", "recent_titles": [FIRST]},
    {"name": "発言から気分と予定の種類を読む", "date": "2026-10-08", "time_of_day": "daytime", "messages": ["これから会議。ちょっと疲れた"]},
    {"name": "反応の傾向を使う", "date": "2026-12-23", "time_of_day": "daytime", "mood": "bored",
     "feedback": [{"tag": "social", "rating": "negative", "weight": 1.0}, {"tag": "creative", "rating": "positive", "weight": 0.8}]},
    {"name": "移動の予定", "date": "2026-10-10", "time_of_day": "morning", "event_title": "通学"},
    {"name": "はじめての人は、根 (いちばん小さなかたち) が芽になる", "date": "2026-10-08", "time_of_day": "daytime", "buds": [ROOTS]},
    {"name": "灯った体験の先の芽を少し優先する", "date": "2026-10-08", "time_of_day": "daytime",
     "buds": ["meal-texture", "taste-last-bite", "taste-water", "meal-screen-down"]},
    {"name": "芽よりも、予定に合う体験を優先する", "date": "2026-10-08", "time_of_day": "evening", "event_title": "数学の課題",
     "buds": ["hear-far", "touch-wind"]},
    {"name": "芽 + 気分", "date": "2026-10-11", "time_of_day": "daytime", "mood": "tired",
     "buds": ["pause-breath", "rest-nothing", "pause-waiting", "pause-one-thing", "smell-breath"]},
    {"name": "全部除外されたら除外を外して選ぶ", "date": "2026-10-08", "time_of_day": "lateNight", "exclude_titles": ["__ALL_LATE_NIGHT__"]},
]


def main(content_path, out_path):
    content = json.load(open(content_path, encoding="utf-8"))
    roots = [el["root"] for el in content["elements"]]
    out = []
    first_title = None
    for case in CASES:
        case = dict(case)
        if case.get("exclude_titles") == ["__ALL_LATE_NIGHT__"]:
            case["exclude_titles"] = [e["title"] for e in content["experiences"] if not e["times"] or "lateNight" in e["times"]]
        if first_title:
            for key in ("exclude_titles", "recent_titles"):
                case[key] = [first_title if t == FIRST else t for t in case.get(key, [])]
        if case.get("buds") == [ROOTS]:
            case["buds"] = roots
        full = {
            "name": case["name"],
            "date": case["date"],
            "time_of_day": case["time_of_day"],
            "event_title": case.get("event_title"),
            "messages": case.get("messages", []),
            "mood": case.get("mood"),
            "feedback": case.get("feedback", []),
            "recent_titles": case.get("recent_titles", []),
            "exclude_titles": case.get("exclude_titles", []),
            "buds": case.get("buds", []),
        }
        full["expected"] = select(content, full)
        if first_title is None:
            first_title = next(e["title"] for e in content["experiences"] if e["id"] == full["expected"])
        out.append(full)
        print(f"{full['expected']:22s} ← {full['name']}")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump({"description": "体験ライブラリの選び方のテストケース。iOS・Backend が同じ結果を返すことを確かめる。", "cases": out},
                  f, ensure_ascii=False, indent=2)
        f.write("\n")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
