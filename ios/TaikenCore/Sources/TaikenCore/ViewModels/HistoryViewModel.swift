import Foundation
import Observation

/// 体験履歴と、最近の反応の傾向 (指示書 §15, §16)
@MainActor
@Observable
public final class HistoryViewModel {
    public struct DaySection: Identifiable, Equatable, Sendable {
        public var id: Date { day }
        public let day: Date
        public let entries: [HistoryEntry]
    }

    public private(set) var sections: [DaySection] = []
    public private(set) var trends: [PreferenceTrends.Summary] = []
    public private(set) var errorMessage: String?

    private let history: any HistoryRepository
    private let calendar: Calendar
    private let now: @Sendable () -> Date
    /// 何日分を表示するか
    public var days = 30

    public init(history: any HistoryRepository, calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { Date() }) {
        self.history = history
        self.calendar = calendar
        self.now = now
    }

    public var isEmpty: Bool { sections.isEmpty }

    public func reload() {
        let date = now()
        let since = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: date))
        let all = history.entries(since: since, limit: nil)
        let chosen = all.filter(\.wasChosen)
        let grouped = Dictionary(grouping: chosen) { calendar.startOfDay(for: $0.createdAt) }
        sections = grouped.keys.sorted(by: >).map { DaySection(day: $0, entries: grouped[$0] ?? []) }
        trends = PreferenceTrends.summaries(from: all, now: date)
    }

    public func delete(_ entry: HistoryEntry) {
        do {
            try history.delete(id: entry.id)
            errorMessage = nil
        } catch {
            errorMessage = AppError.storage.errorDescription
        }
        reload()
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
}
