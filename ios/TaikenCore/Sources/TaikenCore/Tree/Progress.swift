import Foundation

// 自分で記した体験が、触れた要素に「経験」として積もり、要素ごとの「段」になる。
// 段が上がるたびに、その要素に「芽」がひとつ出て、どの技へ伸ばすかを自分で選ぶ。
// 経験は減らない。期限も、続けて記す決まりも無い。

/// 段の境目。段 n に届くのに要る経験の合計は 1, 3, 6, 10, 15, 21, 28 … (n(n+1)/2)
public enum Ranks {
    public static func threshold(_ rank: Int) -> Int {
        let r = max(0, rank)
        return r * (r + 1) / 2
    }

    /// 経験の合計から段
    public static func rank(for experience: Int) -> Int {
        var rank = 0
        while threshold(rank + 1) <= experience { rank += 1 }
        return rank
    }

    /// 一・二・三 … 十・十一 … 二十 … (段は漢数字で書く)
    public static func kanji(_ value: Int) -> String {
        let digits = ["〇", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
        guard value > 0 else { return "〇" }
        guard value < 100 else { return String(value) }
        let tens = value / 10
        let ones = value % 10
        var text = ""
        if tens > 0 { text += (tens == 1 ? "" : digits[tens]) + "十" }
        if ones > 0 { text += digits[ones] }
        return text
    }

    /// 「三段」(まだ一段に届いていなければ「まだ」)
    public static func label(_ rank: Int) -> String {
        rank > 0 ? "\(kanji(rank))段" : "まだ"
    }
}

/// ひとつの要素の、いまの段と経験と芽
public struct ElementProgress: Sendable, Equatable {
    public let element: String
    /// 経験 (この要素に触れた、記した体験の数)
    public let experience: Int
    /// 段
    public let rank: Int
    /// まだ使っていない芽 (段の数 − 技に使った芽)
    public let sprouts: Int

    public init(element: String, experience: Int, rank: Int, sprouts: Int) {
        self.element = element
        self.experience = experience
        self.rank = rank
        self.sprouts = sprouts
    }

    /// いまの段に入ってから積もった経験
    public var gained: Int { experience - Ranks.threshold(rank) }
    /// いまの段から次の段までの幅
    public var span: Int { Ranks.threshold(rank + 1) - Ranks.threshold(rank) }
    /// 次の段までに要る経験
    public var remaining: Int { max(0, span - gained) }
}

/// 身についた技の深まり (稽古の世界の言葉を借りる)
public enum Mastery: Int, Sendable, Comparable, CaseIterable, Codable {
    /// かたちを知った (身についたところ)
    case shu = 1
    /// 自分のやり方が出てきた
    case ha
    /// もう、自分のもの
    case ri

    public static func < (lhs: Mastery, rhs: Mastery) -> Bool { lhs.rawValue < rhs.rawValue }

    public var glyph: String {
        switch self {
        case .shu: "守"
        case .ha: "破"
        case .ri: "離"
        }
    }

    public var meaning: String {
        switch self {
        case .shu: "かたちを知った"
        case .ha: "自分のやり方が出てきた"
        case .ri: "もう、あなたのもの"
        }
    }

    /// 使った回数から
    public static func of(uses: Int, steps: SkillBook.MasterySteps) -> Mastery {
        if uses >= steps.ri { return .ri }
        if uses >= steps.ha { return .ha }
        return .shu
    }
}

/// 記したあと (や、4.0 にしてはじめて開いたとき) に見せる、樹の伸び
public struct GrowthReport: Sendable, Equatable {
    public struct RankUp: Sendable, Equatable, Identifiable {
        public var id: String { element.id }
        public let element: ExperienceElement
        public let from: Int
        public let to: Int
    }

    public struct Deepened: Sendable, Equatable, Identifiable {
        public var id: String { node.id }
        public let node: TreeNode
        public let mastery: Mastery
    }

    /// 経験が積もった要素
    public let gains: [ExperienceElement]
    /// 段が上がった要素
    public let rankUps: [RankUp]
    /// 新しく閃いた技
    public let flashes: [TreeNode]
    /// 深まった技 (守 → 破、破 → 離)
    public let deepened: [Deepened]
    /// いま芽が出ている要素 (伸ばせる技がある要素だけ)
    public let sproutElements: [ExperienceElement]

    public init(
        gains: [ExperienceElement] = [], rankUps: [RankUp] = [], flashes: [TreeNode] = [], deepened: [Deepened] = [],
        sproutElements: [ExperienceElement] = []
    ) {
        self.gains = gains
        self.rankUps = rankUps
        self.flashes = flashes
        self.deepened = deepened
        self.sproutElements = sproutElements
    }

    public static let empty = GrowthReport()

    /// 段・閃き・深まりのどれかがある (ただ経験が積もっただけではない)
    public var hasMoment: Bool { !rankUps.isEmpty || !flashes.isEmpty || !deepened.isEmpty }
    public var isEmpty: Bool { gains.isEmpty && !hasMoment }

    /// 二つの樹の差 (記す前と、記したあと)
    public static func between(_ before: ExperienceTree, _ after: ExperienceTree, gained elements: [String] = []) -> GrowthReport {
        let gains = after.content.knownElements(elements).compactMap { after.element($0) }
        var rankUps: [RankUp] = []
        for element in after.elements {
            let old = before.progress(of: element.id).rank
            let new = after.progress(of: element.id).rank
            if new > old { rankUps.append(RankUp(element: element, from: old, to: new)) }
        }
        let flashes = after.nodes.filter { $0.kind == .flash && before.node($0.id) == nil }
        var deepened: [Deepened] = []
        for node in after.learnedNodes where node.kind != .flash {
            guard let now = after.mastery(of: node.id) else { continue }
            let was = before.mastery(of: node.id)
            if let was, now > was { deepened.append(Deepened(node: node, mastery: now)) }
        }
        return GrowthReport(
            gains: gains, rankUps: rankUps, flashes: flashes, deepened: deepened,
            sproutElements: after.elements.filter { after.hasLearnable(inElement: $0.id) }
        )
    }

    /// はじめから、いまの樹まで (4.0 にしてはじめて開いたとき、これまでの体験から育っていたもの)
    public static func since(nothing tree: ExperienceTree) -> GrowthReport {
        GrowthReport(
            gains: [],
            rankUps: tree.elements.compactMap { element in
                let rank = tree.progress(of: element.id).rank
                return rank > 0 ? RankUp(element: element, from: 0, to: rank) : nil
            },
            flashes: tree.nodes.filter { $0.kind == .flash },
            deepened: [],
            sproutElements: tree.elements.filter { tree.hasLearnable(inElement: $0.id) }
        )
    }
}

// MARK: - 閃き

/// 閃きの条件を、記した体験から確かめる。満たした体験 (または糸) の時刻を、閃いた時刻とする
enum FlashEvaluator {
    static let senses: Set<String> = ["see", "hear", "smell", "taste", "touch"]

    struct Inputs {
        /// 記した体験 (古い順) と、その要素
        let entries: [(entry: HistoryEntry, elements: [String])]
        let ranks: [String: Int]
        let elementIDs: [String]
        let ties: [Tie]
        /// 離に届いた技と、届いた時刻
        let masteredAt: [Date]
        let calendar: Calendar
    }

    /// 条件を満たしていれば、満たした時刻
    static func satisfied(_ rule: SkillBook.FlashRule, inputs: Inputs) -> Date? {
        var moments: [Date] = []

        // ひとつの体験で満たす条件 (要素の数・五感・時間帯・要素)
        let perEntry = rule.senses != nil || rule.elements != nil || rule.times != nil || rule.element != nil
        if perEntry {
            let match = inputs.entries.first { item in
                let set = Set(item.elements)
                if let n = rule.elements, set.count < n { return false }
                if let n = rule.senses, set.intersection(senses).count < n { return false }
                if let element = rule.element, !set.contains(element) { return false }
                if let times = rule.times {
                    let band = TimeOfDay.at(item.entry.finishedAt ?? item.entry.createdAt, calendar: inputs.calendar).rawValue
                    if !times.contains(band) { return false }
                }
                return true
            }
            guard let match else { return nil }
            moments.append(match.entry.finishedAt ?? match.entry.createdAt)
        }

        if let n = rule.bands {
            var bandsByDay: [Date: Set<String>] = [:]
            var found: Date?
            for item in inputs.entries {
                let date = item.entry.finishedAt ?? item.entry.createdAt
                let day = inputs.calendar.startOfDay(for: date)
                bandsByDay[day, default: []].insert(TimeOfDay.at(date, calendar: inputs.calendar).rawValue)
                if (bandsByDay[day]?.count ?? 0) >= n {
                    found = date
                    break
                }
            }
            guard let found else { return nil }
            moments.append(found)
        }

        if let n = rule.days {
            var days = Set<Date>()
            var found: Date?
            for item in inputs.entries {
                let date = item.entry.finishedAt ?? item.entry.createdAt
                days.insert(inputs.calendar.startOfDay(for: date))
                if days.count >= n {
                    found = date
                    break
                }
            }
            guard let found else { return nil }
            moments.append(found)
        }

        if let n = rule.selfRecorded {
            let own = inputs.entries.filter { $0.entry.isSelfRecorded }
            guard own.count >= n else { return nil }
            moments.append(own[n - 1].entry.finishedAt ?? own[n - 1].entry.createdAt)
        }

        if let n = rule.allElements {
            // すべての要素がその段に届いた時刻 (古い順にたどって、届いた体験を探す)
            var experience: [String: Int] = [:]
            var found: Date?
            for item in inputs.entries {
                for element in item.elements { experience[element, default: 0] += 1 }
                if inputs.elementIDs.allSatisfy({ Ranks.rank(for: experience[$0] ?? 0) >= n }) {
                    found = item.entry.finishedAt ?? item.entry.createdAt
                    break
                }
            }
            guard let found else { return nil }
            moments.append(found)
        }

        if let n = rule.ties {
            let sorted = inputs.ties.sorted { $0.createdAt < $1.createdAt }
            guard sorted.count >= n else { return nil }
            moments.append(sorted[n - 1].createdAt)
        }

        if let n = rule.mastered {
            let sorted = inputs.masteredAt.sorted()
            guard sorted.count >= n else { return nil }
            moments.append(sorted[n - 1])
        }

        return moments.max()
    }
}
