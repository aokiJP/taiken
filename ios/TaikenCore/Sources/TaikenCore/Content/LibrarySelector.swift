import Foundation

/// 体験ライブラリから、今の状況にいちばん合う体験を1つ選ぶ。
/// 仕様は contracts/tools/selection_reference.py。Backend (library.ts) と Web 版が同じ結果になることを
/// contracts/selection_cases.json で確かめている。
public struct LibrarySelector: Sendable {
    public struct Input: Sendable, Equatable {
        /// 1970-01-01 からの日数 (その土地の日付)。同じ日は同じ順番になり、日が変わると顔ぶれが変わる
        public var day: Int
        public var timeOfDay: TimeOfDay
        /// 次の予定のタイトル (送信を許可していなければ nil)
        public var eventTitle: String?
        public var messages: [String]
        /// ユーザーが選んだ気分。nil なら発言から読み取る
        public var mood: Mood?
        public var feedback: [FeedbackSignal]
        /// 最近の体験 (選んだ・断ったものを含む)。後ろに回す
        public var recentTitles: Set<String>
        /// 今回は出さない (別の提案で見たもの)
        public var excludeTitles: Set<String>
        /// 体験の樹の「芽」(灯った体験からつながっている、まだやっていない体験の id)。少しだけ前に出す
        public var buds: Set<String>

        public init(
            day: Int, timeOfDay: TimeOfDay, eventTitle: String? = nil, messages: [String] = [],
            mood: Mood? = nil, feedback: [FeedbackSignal] = [], recentTitles: Set<String> = [], excludeTitles: Set<String> = [],
            buds: Set<String> = []
        ) {
            self.day = day
            self.timeOfDay = timeOfDay
            self.eventTitle = eventTitle
            self.messages = messages
            self.mood = mood
            self.feedback = feedback
            self.recentTitles = recentTitles
            self.excludeTitles = excludeTitles
            self.buds = buds
        }
    }

    /// 選ばれた体験と、なぜそれを選んだかの材料 (提案理由の文に使う)
    public struct Choice: Sendable, Equatable {
        public let experience: TaikenContent.LibraryExperience
        public let themesFromEvent: Set<String>
        public let themesFromMessages: Set<String>
        /// 気分 (選んだもの、または発言から読み取ったもの)
        public let mood: Mood?
        /// 気分をユーザーが自分で選んだか
        public let moodWasChosen: Bool
        /// 体験の樹の芽から選んだか
        public let isBud: Bool

        /// 予定の内容に合わせて選んだか
        public var matchesEvent: Bool { !Set(experience.themes).isDisjoint(with: themesFromEvent) }
        public var matchesMessages: Bool { !Set(experience.themes).isDisjoint(with: themesFromMessages) }
    }

    /// 特定の場面を前提にするテーマ (その場面が見当たらないときは後ろに回す)
    static let specificThemes: Set<String> = ["study", "work", "commute", "meal", "housework", "shopping", "people", "body"]
    /// 芽に足す点数
    static let budBonus = 1.5

    public let content: TaikenContent

    public init(content: TaikenContent = .shared) {
        self.content = content
    }

    // MARK: - 読み取り

    public func detectThemes(_ texts: [String]) -> Set<String> {
        var found = Set<String>()
        for theme in content.themes where theme.keywords.contains(where: { keyword in texts.contains { $0.contains(keyword) } }) {
            found.insert(theme.id)
        }
        return found
    }

    public func detectMood(_ texts: [String]) -> Mood? {
        for mood in content.moods where mood.keywords.contains(where: { keyword in texts.contains { $0.contains(keyword) } }) {
            if let value = Mood(rawValue: mood.id) { return value }
        }
        return nil
    }

    // MARK: - 選ぶ

    public func choose(_ input: Input) -> Choice {
        let fromEvent = detectThemes(input.eventTitle.map { [$0] } ?? [])
        let fromMessages = detectThemes(input.messages)
        let detected = fromEvent.union(fromMessages)
        let mood = input.mood ?? detectMood(input.messages)
        let timeTheme: String? = switch input.timeOfDay {
        case .dawn, .morning: "morning"
        case .night, .lateNight: "night"
        case .daytime, .evening: nil
        }

        func eligible(_ e: TaikenContent.LibraryExperience, useExclude: Bool) -> Bool {
            if useExclude && input.excludeTitles.contains(e.title) { return false }
            if !e.times.isEmpty && !e.times.contains(input.timeOfDay.rawValue) { return false }
            return true
        }

        func score(_ e: TaikenContent.LibraryExperience) -> Double {
            var s = 0.0
            if e.themes.contains(where: { detected.contains($0) }) {
                s += 4.0
            } else if e.themes.allSatisfy({ Self.specificThemes.contains($0) }) {
                s -= 2.0
            }
            if let mood, e.moods.contains(mood.rawValue) { s += 2.5 }
            if let timeTheme, e.themes.contains(timeTheme) { s += 1.5 }
            if input.buds.contains(e.id) { s += Self.budBonus }
            for tag in e.tags {
                for signal in input.feedback where signal.tag == tag {
                    let factor: Double = switch signal.rating {
                    case .positive: 1.0
                    case .negative: -1.5
                    case .neutral: 0.0
                    }
                    s += factor * signal.weight
                }
            }
            if input.recentTitles.contains(e.title) { s -= 3.0 }
            if mood == .tired && e.effort == "medium" { s -= 2.0 }
            s += Self.jitter(id: e.id, day: input.day)
            return s
        }

        var candidates = content.experiences.filter { eligible($0, useExclude: true) }
        if candidates.isEmpty { candidates = content.experiences.filter { eligible($0, useExclude: false) } }
        if candidates.isEmpty { candidates = content.experiences }

        var best = candidates[0]
        var bestScore = -Double.infinity
        for candidate in candidates {
            let s = score(candidate)
            if s > bestScore {
                best = candidate
                bestScore = s
            }
        }
        return Choice(
            experience: best, themesFromEvent: fromEvent, themesFromMessages: fromMessages,
            mood: mood, moodWasChosen: input.mood != nil, isBud: input.buds.contains(best.id)
        )
    }

    // MARK: - 決定的なゆらぎ

    /// FNV-1a (32bit)。Backend と同じ値になる
    static func fnv1a(_ text: String) -> UInt32 {
        var hash: UInt32 = 0x811C_9DC5
        for byte in text.utf8 {
            hash ^= UInt32(byte)
            hash = hash &* 0x0100_0193
        }
        return hash
    }

    /// 同じ点数の候補の並びを日ごとに変える (0〜0.9)
    static func jitter(id: String, day: Int) -> Double {
        Double(fnv1a("\(id)#\(day)") % 1000) / 1000 * 0.9
    }

    /// 1970-01-01 からの日数 (calendar のタイムゾーンでの日付)
    public static func dayNumber(of date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
        let midnight = utc.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day)) ?? date
        return Int((midnight.timeIntervalSince1970 / 86_400).rounded(.down))
    }
}
