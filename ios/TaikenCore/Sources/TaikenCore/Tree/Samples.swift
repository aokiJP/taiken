import Foundation

// プレビュー・UIテスト・はじめの案内の挿絵で使う、見本の体験帳と自分の樹

extension HistoryEntry {
    /// 見本の、自分で見つけて記した体験 (きっかけから始めたものではない)
    public static func sampleLived(
        now: Date = Date(), calendar: Calendar = .current, content: TaikenContent = .shared
    ) -> [HistoryEntry] {
        let picks: [(days: Int, text: String, elements: [String])] = [
            (0, "帰り道、パン屋の前で足が止まった", ["smell", "move"]),
            (3, "湯呑みの温かさを、両手で確かめた", ["touch", "pause"]),
        ]
        return picks.compactMap { pick in
            guard let day = calendar.date(byAdding: .day, value: -pick.days, to: now) else { return nil }
            return HistoryEntry.lived(
                LivedDraft(text: pick.text, elements: pick.elements), at: day.addingTimeInterval(-2 * 3600), content: content
            )
        }
    }
}

extension Garden {
    /// 見本で伸ばす技 (この順に、伸ばせるものだけ伸ばす)
    static let sampleSkills = [
        "see-tomeru", "see-chigai", "hear-sumasu", "taste-hitokuchi", "think-tsumazuki", "move-michi", "cross-arukime",
    ]
    static let sampleWovenID = "w-sampleyuge"

    /// 見本の自分の樹: 見本の体験帳から、伸ばせる技を順に伸ばし、技をひとつ編み、糸をひとつ結ぶ。
    /// 芽は使いきらずに残す (「芽が出ています」の様子も見られるように)
    public static func sample(
        entries: [HistoryEntry], content: TaikenContent = .shared, book: SkillBook = .shared, now: Date = Date(),
        calendar: Calendar = .current
    ) -> Garden {
        var garden = Garden(seen: true)
        garden.nodes.append(PersonalNode(
            id: sampleWovenID, kind: .woven, title: "湯気のゆくえ",
            invitation: "温かい飲み物を入れたら、湯気がどこで見えなくなるかを追ってみる。",
            perspective: "湯気が消えるところまで、見届けられる。",
            elements: ["see", "pause"], growsFrom: "see-tomeru", createdAt: now.addingTimeInterval(-30 * 60)
        ))
        for (offset, id) in (sampleSkills + [sampleWovenID]).enumerated() {
            let tree = TreeBuilder.build(content: content, book: book, garden: garden, entries: entries, calendar: calendar)
            guard case .available(let charge) = tree.check(id) else { continue }
            garden.learned.append(LearnedSkill(id: id, element: charge, learnedAt: now.addingTimeInterval(Double(offset - 20) * 60)))
        }
        if garden.isLearned("move-michi"),
           let walk = entries.first(where: { $0.isSelfRecorded && $0.elements.contains("move") }) {
            garden.uses.append(SkillUse(entryID: walk.id, skills: ["move-michi"]))
        }
        if garden.isLearned("see-tomeru"), garden.isLearned("taste-hitokuchi") {
            garden.ties.append(Tie(
                between: "see-tomeru", and: "taste-hitokuchi", note: "どちらも、思ったより長く見ていた",
                createdAt: now.addingTimeInterval(-60)
            ))
        }
        return garden
    }
}
