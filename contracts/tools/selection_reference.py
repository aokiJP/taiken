#!/usr/bin/env python3
"""体験ライブラリの選び方の基準実装 (仕様)。
iOS (LibrarySelector.swift) と Backend (library.ts) はこれと同じ結果を返すことを、
contracts/selection_cases.json で検証する。"""
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
    term = case["solar_term"]
    texts_event = [case["event_title"]] if case.get("event_title") else []
    messages = case.get("messages", [])
    detected = detect_themes(content, texts_event) | detect_themes(content, messages)
    mood = case.get("mood") or detect_mood(content, messages)
    time_theme = "morning" if tod in ("dawn", "morning") else "night" if tod in ("night", "lateNight") else None
    feedback = case.get("feedback", [])
    recent = set(case.get("recent_titles", []))
    exclude = set(case.get("exclude_titles", []))

    def eligible(e, use_exclude=True):
        if use_exclude and e["title"] in exclude:
            return False
        if e["solar_terms"] and term not in e["solar_terms"]:
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
        if e["solar_terms"]:
            s += 3.0
        if time_theme and time_theme in e["themes"]:
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


CASES = [
    {"name": "予定も気分も無い寒露の夕方は、季節の体験", "date": "2026-10-08", "time_of_day": "evening", "solar_term": 16},
    {"name": "勉強の予定があれば勉強の体験", "date": "2026-10-08", "time_of_day": "evening", "solar_term": 16, "event_title": "数学の課題"},
    {"name": "勉強の予定 + 疲れぎみなら軽いもの", "date": "2026-10-08", "time_of_day": "evening", "solar_term": 16, "event_title": "数学の課題", "mood": "tired"},
    {"name": "朝 + 気分転換", "date": "2026-10-09", "time_of_day": "morning", "solar_term": 16, "mood": "refresh"},
    {"name": "夜は夜の体験 (昼向きの季節の体験は出さない)", "date": "2026-10-08", "time_of_day": "night", "solar_term": 16},
    {"name": "深夜", "date": "2026-10-08", "time_of_day": "lateNight", "solar_term": 16},
    {"name": "別の提案: 見た体験は除く", "date": "2026-10-08", "time_of_day": "evening", "solar_term": 16, "exclude_titles": ["渡っていくもの"]},
    {"name": "最近やった体験は後ろに回す", "date": "2026-10-08", "time_of_day": "evening", "solar_term": 16, "recent_titles": ["渡っていくもの"]},
    {"name": "発言から気分と予定の種類を読む", "date": "2026-10-08", "time_of_day": "daytime", "solar_term": 16, "messages": ["これから会議。ちょっと疲れた"]},
    {"name": "反応の傾向を使う (季節の体験が出ない昼)", "date": "2026-12-23", "time_of_day": "daytime", "solar_term": 21, "mood": "bored",
     "feedback": [{"tag": "social", "rating": "negative", "weight": 1.0}, {"tag": "creative", "rating": "positive", "weight": 0.8}]},
    {"name": "移動の予定 + 季節", "date": "2026-10-10", "time_of_day": "morning", "solar_term": 16, "event_title": "通学"},
    {"name": "冬至の夜", "date": "2026-12-22", "time_of_day": "night", "solar_term": 21},
    {"name": "立春の昼 + 集中したい", "date": "2027-02-05", "time_of_day": "daytime", "solar_term": 0, "mood": "focus"},
    {"name": "全部除外されたら除外を外して選ぶ", "date": "2026-10-08", "time_of_day": "lateNight", "solar_term": 16,
     "exclude_titles": ["__ALL_LATE_NIGHT__"]},
]


def main(content_path, out_path):
    content = json.load(open(content_path, encoding="utf-8"))
    out = []
    for case in CASES:
        case = dict(case)
        if case.get("exclude_titles") == ["__ALL_LATE_NIGHT__"]:
            case["exclude_titles"] = [e["title"] for e in content["experiences"]
                                      if (not e["times"] or "lateNight" in e["times"])
                                      and (not e["solar_terms"] or 16 in e["solar_terms"])]
        full = {
            "name": case["name"],
            "date": case["date"],
            "time_of_day": case["time_of_day"],
            "solar_term": case["solar_term"],
            "event_title": case.get("event_title"),
            "messages": case.get("messages", []),
            "mood": case.get("mood"),
            "feedback": case.get("feedback", []),
            "recent_titles": case.get("recent_titles", []),
            "exclude_titles": case.get("exclude_titles", []),
        }
        full["expected"] = select(content, full)
        out.append(full)
        print(f"{full['expected']:22s} ← {full['name']}")
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump({"description": "体験ライブラリの選び方のテストケース。iOS と Backend が同じ結果を返すことを確かめる。", "cases": out},
                  f, ensure_ascii=False, indent=2)
        f.write("\n")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
