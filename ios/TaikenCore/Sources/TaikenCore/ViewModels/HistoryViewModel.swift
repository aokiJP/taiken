import Foundation
import Observation

/// 体験帳: これまでに記した体験と、最近の反応の傾向 (指示書 §15, §16)。
/// 数を競わせない。連続記録や「今日もやろう」のような義務を生む表示はしない。
/// 体験どうしのつながりは「体験の樹」で、いつ何をしたかはここ (月の暦と記録) で見る。
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

        public static let empty = Stats(lived: 0, thisMonth: 0, elements: [])
    }

    public private(set) var sections: [DaySection] = []
    public private(set) var trends: [PreferenceTrends.Summary] = []
    public private(set) var stats: Stats = .empty
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
            elements: Set(chosen.compactMap { $0.resolvedElements().first })
        )
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
            trees?.discardFoundIfUnused(entry.nodeID)
            errorMessage = nil
        } catch {
            errorMessage = AppError.storage.errorDescription
        }
        reload()
    }

    /// その記録が、体験の樹のどの体験か
    public func nodeID(of entry: HistoryEntry) -> String? {
        trees?.tree().nodeID(of: entry) ?? entry.nodeID
    }

    /// 端末内の体験帳と自分の樹 (編んだ体験・見つけた体験・結び) を、すべてJSONで書き出す
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

    /// 体験の樹と体験帳を、Markdown の保管庫として書き出すファイル
    public func vaultFiles() -> [VaultExporter.File] {
        guard let trees else { return [] }
        return VaultExporter.files(tree: trees.tree(), exportedAt: now(), calendar: calendar)
    }

    static func startOfMonth(_ date: Date, calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? calendar.startOfDay(for: date)
    }
}
