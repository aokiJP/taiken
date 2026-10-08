import Foundation
import Observation

/// 体験帳: これまでに記した体験と、最近の反応の傾向 (指示書 §15, §16)。
/// 数を競わせない。連続記録や「今日もやろう」のような義務を生む表示はしない。
/// 代わりに、季節 (七十二候) ごとに体験が重なっていく様子を見せる。
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
        /// この一年で体験した七十二候 (番号)
        public let microSeasons: Set<Int>

        public static let empty = Stats(lived: 0, thisMonth: 0, microSeasons: [])
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
    /// 何日分を表示するか (nil ならすべて)
    public var days: Int?

    public init(history: any HistoryRepository, calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { Date() }) {
        self.history = history
        self.calendar = calendar
        self.now = now
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
        let yearAgo = calendar.date(byAdding: .day, value: -365, to: date) ?? date
        stats = Stats(
            lived: chosen.count,
            thisMonth: chosen.filter { $0.createdAt >= monthStart }.count,
            microSeasons: Set(chosen.filter { $0.createdAt >= yearAgo }.map { MicroSeason.index(on: $0.createdAt, calendar: calendar) })
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
            errorMessage = nil
        } catch {
            errorMessage = AppError.storage.errorDescription
        }
        reload()
    }

    /// その体験をしたときの七十二候
    public func microSeason(of entry: HistoryEntry) -> MicroSeason {
        MicroSeason.at(entry.createdAt, calendar: calendar)
    }

    /// 端末内の履歴をすべてJSONで書き出す (自分のデータを持ち出せるように)
    public func exportJSON() throws -> Data {
        struct Export: Encodable {
            let exportedAt: Date
            let app: String
            let entries: [HistoryEntry]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try encoder.encode(Export(exportedAt: now(), app: "Taiken", entries: history.entries(since: nil, limit: nil)))
    }

    static func startOfMonth(_ date: Date, calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? calendar.startOfDay(for: date)
    }
}
