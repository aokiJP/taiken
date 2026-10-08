import Foundation
import Observation

/// 体験帳: これまでに記した体験と、要素ごとの段と、最近の反応の傾向 (指示書 §15, §16)。
/// 他人と比べない。連続記録や「今日もやろう」のような義務を生む表示はしない。
/// 技どうしのつながりは「技の樹」で、いつ何をしたかはここ (月の暦と記録) で見る。
@MainActor
@Observable
public final class HistoryViewModel {
    public struct DaySection: Identifiable, Equatable, Sendable {
        public var id: Date { day }
        public let day: Date
        public let entries: [HistoryEntry]
    }

    /// 月の暦の1マス
    public struct DayMark: Identifiable, Equatable, Sendable {
        public var id: Date { date }
        public let date: Date
        public let day: Int
        public let isInMonth: Bool
        public let isToday: Bool
        public let entries: [HistoryEntry]
    }

    public struct Stats: Equatable, Sendable {
        /// これまでに記した (または体験中の) 体験の数
        public let lived: Int
        /// 今月の数
        public let thisMonth: Int
        /// 触れたことのある要素 (主な要素の id)
        public let elements: Set<String>
        /// 自分で見つけて記した体験の数
        public let selfRecorded: Int

        public static let empty = Stats(lived: 0, thisMonth: 0, elements: [], selfRecorded: 0)
    }

    public private(set) var sections: [DaySection] = []
    public private(set) var trends: [PreferenceTrends.Summary] = []
    public private(set) var stats: Stats = .empty
    /// 要素ごとの段 (技の樹があるときだけ)
    public private(set) var progress: [ElementProgress] = []
    /// 身についた技の数 (閃きも含む)
    public private(set) var learnedCount = 0
    public private(set) var errorMessage: String?
    /// 暦に表示している月 (その月の1日)
    public private(set) var displayedMonth: Date

    private var chosen: [HistoryEntry] = []
    private let history: any HistoryRepository
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    private let trees: TreeSource?
    /// 何日分を表示するか (nil ならすべて)
    public var days: Int?

    public init(
        history: any HistoryRepository, calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { Date() },
        trees: TreeSource? = nil
    ) {
        self.history = history
        self.calendar = calendar
        self.now = now
        self.trees = trees
        displayedMonth = Self.startOfMonth(now(), calendar: calendar)
    }

    public var isEmpty: Bool { sections.isEmpty }

    public func reload() {
        let date = now()
        let since = days.flatMap { calendar.date(byAdding: .day, value: -$0, to: calendar.startOfDay(for: date)) }
        let all = history.entries(since: since, limit: nil)
        chosen = all.filter(\.wasChosen)
        let grouped = Dictionary(grouping: chosen) { calendar.startOfDay(for: $0.createdAt) }
        sections = grouped.keys.sorted(by: >).map { DaySection(day: $0, entries: grouped[$0] ?? []) }
        trends = PreferenceTrends.summaries(from: all, now: date)

        let monthStart = Self.startOfMonth(date, calendar: calendar)
        stats = Stats(
            lived: chosen.count,
            thisMonth: chosen.filter { $0.createdAt >= monthStart }.count,
            elements: Set(chosen.compactMap { $0.resolvedElements().first }),
            selfRecorded: chosen.filter { $0.status == .completed && $0.isSelfRecorded }.count
        )
        if let trees {
            let tree = trees.tree()
            progress = tree.elements.map { tree.progress(of: $0.id) }
            learnedCount = tree.learnedNodes.count
        } else {
            progress = []
            learnedCount = 0
        }
    }

    // MARK: - 月の暦

    /// 表示中の月を、週ごとに並べたマス (前後の月の日も含めて7の倍数)
    public func monthGrid() -> [DayMark] {
        guard let range = calendar.range(of: .day, in: .month, for: displayedMonth) else { return [] }
        let firstWeekday = calendar.component(.weekday, from: displayedMonth)
        let leading = (firstWeekday - calendar.firstWeekday + 7) % 7
        let total = Int((Double(leading + range.count) / 7).rounded(.up)) * 7
        let today = calendar.startOfDay(for: now())
        let byDay = Dictionary(grouping: chosen) { calendar.startOfDay(for: $0.createdAt) }

        return (0..<total).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset - leading, to: displayedMonth) else { return nil }
            let day = calendar.startOfDay(for: date)
            return DayMark(
                date: day,
                day: calendar.component(.day, from: day),
                isInMonth: calendar.isDate(day, equalTo: displayedMonth, toGranularity: .month),
                isToday: day == today,
                entries: (byDay[day] ?? []).sorted { $0.createdAt < $1.createdAt }
            )
        }
    }

    public var canShowNextMonth: Bool {
        displayedMonth < Self.startOfMonth(now(), calendar: calendar)
    }

    public func showPreviousMonth() {
        displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
    }

    public func showNextMonth() {
        guard canShowNextMonth else { return }
        displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
    }

    public func showCurrentMonth() {
        displayedMonth = Self.startOfMonth(now(), calendar: calendar)
    }

    // MARK: - 操作

    public func delete(_ entry: HistoryEntry) {
        do {
            try history.delete(id: entry.id)
            trees?.forget(entry: entry.id)
            errorMessage = nil
        } catch {
            errorMessage = AppError.storage.errorDescription
        }
        reload()
    }

    /// その記録で育った技 (稽古から始めたもの・自分で「使った」と選んだもの)。霧の中の技は名前を明かさないので出さない
    public func skills(of entry: HistoryEntry) -> [TreeNode] {
        guard let tree = trees?.tree() else { return [] }
        return tree.skills(usedIn: entry.id).filter { tree.state(of: $0.id) != .unknown }
    }

    /// 記録のページに添える、その記録で育った技と、いまの様子
    public struct GrownSkill: Identifiable, Equatable, Sendable {
        public var id: String { node.id }
        public let node: TreeNode
        public let state: NodeState
        public let glyph: String
    }

    public func grownSkills(of entry: HistoryEntry) -> [GrownSkill] {
        guard let tree = trees?.tree() else { return [] }
        return tree.skills(usedIn: entry.id).compactMap { node in
            let state = tree.state(of: node.id)
            return state == .unknown ? nil : GrownSkill(node: node, state: state, glyph: tree.glyph(of: node))
        }
    }

    /// 樹の上で、その記録に近い場所 (育った技があればその技、無ければ主な要素の根)
    public func treeFocus(of entry: HistoryEntry) -> String? {
        if let skill = skills(of: entry).first { return skill.id }
        return entry.resolvedElements().first.map { ExperienceTree.rootID($0) }
    }

    /// 端末内の体験帳と自分の樹 (身についた技・編んだ技・結び) を、すべてJSONで書き出す
    public func exportJSON() throws -> Data {
        struct Export: Encodable {
            let exportedAt: Date
            let app: String
            let entries: [HistoryEntry]
            let garden: Garden?
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try encoder.encode(Export(exportedAt: now(), app: "Taiken", entries: history.entries(since: nil, limit: nil), garden: trees?.garden))
    }

    /// 技の樹と体験帳を、Markdown の保管庫として書き出すファイル
    public func vaultFiles() -> [VaultExporter.File] {
        guard let trees else { return [] }
        return VaultExporter.files(tree: trees.tree(), entries: history.entries(since: nil, limit: nil), exportedAt: now(), calendar: calendar)
    }

    static func startOfMonth(_ date: Date, calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? calendar.startOfDay(for: date)
    }
}
