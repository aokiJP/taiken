import Foundation

// 端末の機能 (カレンダー・位置・保存・通知) への出入口。
// 実装はアプリ側 (EventKit, CoreLocation, SwiftData, UserNotifications, Keychain) にあり、
// テストとプレビューでは InMemoryAdapters.swift の実装に差し替える。

// MARK: - カレンダー

/// EventKitから取り出した予定の、アプリ内で使う最小限のコピー。
/// メモ・場所・参加者などはそもそも読み出さない。
public struct CalendarEventSnapshot: Sendable, Hashable {
    public let title: String?
    public let start: Date
    public let end: Date
    public let isAllDay: Bool

    public init(title: String?, start: Date, end: Date, isAllDay: Bool) {
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
    }
}

public enum PermissionState: String, Sendable, Equatable {
    case notDetermined
    case granted
    case denied
}

public protocol CalendarProviding: Sendable {
    func access() -> PermissionState
    func requestAccess() async -> PermissionState
    func events(from start: Date, to end: Date) -> [CalendarEventSnapshot]
}

// MARK: - 位置 (市区町村レベル)

@MainActor
public protocol LocationProviding: AnyObject {
    func access() -> PermissionState
    func requestAccess() async -> PermissionState
    /// おおよその地域。許可が無い・取得できない場合は nil
    func currentArea() async -> Area?
}

// MARK: - 履歴

@MainActor
public protocol HistoryRepository: AnyObject {
    func add(_ entry: HistoryEntry) throws
    func update(_ entry: HistoryEntry) throws
    func entry(id: UUID) -> HistoryEntry?
    /// 新しい順
    func entries(since: Date?, limit: Int?) -> [HistoryEntry]
    func delete(id: UUID) throws
    func deleteAll() throws
}

extension HistoryRepository {
    public func activeEntry() -> HistoryEntry? {
        entries(since: nil, limit: 50).first { $0.status == .active }
    }

    @discardableResult
    public func record(_ experience: Experience, theme: String?, status: HistoryEntry.Status, at date: Date) throws -> HistoryEntry {
        let entry = HistoryEntry(experience: experience, theme: theme, status: status, at: date)
        try add(entry)
        return entry
    }

    public func finish(id: UUID, rating: Rating, note: String?, at date: Date) throws {
        guard var entry = entry(id: id) else { return }
        entry.status = .completed
        entry.rating = rating
        entry.finishedAt = date
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.note = trimmed?.isEmpty == false ? String(trimmed!.prefix(200)) : nil
        try update(entry)
    }
}

// MARK: - 通知

public enum NotificationAuthorization: String, Sendable, Equatable {
    case notDetermined
    case authorized
    case denied
}

public protocol NotificationScheduling: Sendable {
    func authorization() async -> NotificationAuthorization
    func requestAuthorization() async -> Bool
    func deliver(_ content: NotificationContent, identifier: String) async throws
}

/// 通知を出した時刻の記録 (1日の上限・最小間隔の判定用)
public protocol NotificationLedger: Sendable {
    func deliveries(since date: Date) -> [Date]
    func recordDelivery(at date: Date)
}

// MARK: - 接続先

public protocol ConnectionStore: Sendable {
    func load() -> BackendEndpoint?
    func save(_ endpoint: BackendEndpoint) throws
    func clear() throws
}

// MARK: - 最後の提案のキャッシュ

public struct CachedProposal: Codable, Sendable, Equatable {
    public let generatedAt: Date
    public let response: ExperienceResponse

    public init(generatedAt: Date, response: ExperienceResponse) {
        self.generatedAt = generatedAt
        self.response = response
    }
}

/// Home の小さな状態 (当日の提案と「ひと休み」の終わり) を覚えておく。
/// 開き直しても、断った直後に提案を押しつけないために「ひと休み」も保存する。
public protocol ProposalCaching: Sendable {
    func load() -> CachedProposal?
    func save(_ proposal: CachedProposal)
    func clear()
    /// 「今はやらない」「終えた」のあと、次の提案を控える時刻
    func loadRestingUntil() -> Date?
    func saveRestingUntil(_ date: Date?)
}
