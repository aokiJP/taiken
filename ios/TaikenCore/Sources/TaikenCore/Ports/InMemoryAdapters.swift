import Foundation
import Synchronization

// プレビュー・テスト・権限が無いときに使う、端末機能を使わない実装。

public struct FixedCalendarProvider: CalendarProviding {
    public var snapshots: [CalendarEventSnapshot]
    public var state: PermissionState

    public init(events: [CalendarEventSnapshot] = [], state: PermissionState = .granted) {
        self.snapshots = events
        self.state = state
    }

    public func access() -> PermissionState { state }
    public func requestAccess() async -> PermissionState { state }
    public func events(from start: Date, to end: Date) -> [CalendarEventSnapshot] {
        snapshots.filter { $0.end > start && $0.start < end }
    }

    public static func sample(now: Date = Date()) -> FixedCalendarProvider {
        FixedCalendarProvider(events: [
            CalendarEventSnapshot(title: "数学の課題", start: now.addingTimeInterval(50 * 60), end: now.addingTimeInterval(140 * 60), isAllDay: false),
            CalendarEventSnapshot(title: "ゼミ", start: now.addingTimeInterval(20 * 3600), end: now.addingTimeInterval(21 * 3600), isAllDay: false),
        ])
    }
}

@MainActor
public final class FixedLocationProvider: LocationProviding {
    public var area: Area?
    public var state: PermissionState
    public private(set) var requests = 0

    public init(area: Area? = nil, state: PermissionState = .granted) {
        self.area = area
        self.state = state
    }

    public func access() -> PermissionState { state }
    public func requestAccess() async -> PermissionState { state }
    public func currentArea() async -> Area? {
        requests += 1
        return state == .granted ? area : nil
    }
}

@MainActor
public final class InMemoryHistoryRepository: HistoryRepository {
    public private(set) var storage: [HistoryEntry]
    /// テスト用: true にすると書き込みが失敗する
    public var failWrites = false

    public init(_ entries: [HistoryEntry] = []) {
        storage = entries
    }

    private func guardWrite() throws {
        if failWrites { throw AppError.storage }
    }

    public func add(_ entry: HistoryEntry) throws {
        try guardWrite()
        storage.append(entry)
    }

    public func update(_ entry: HistoryEntry) throws {
        try guardWrite()
        guard let index = storage.firstIndex(where: { $0.id == entry.id }) else { return }
        storage[index] = entry
    }

    public func entry(id: UUID) -> HistoryEntry? {
        storage.first { $0.id == id }
    }

    public func entries(since: Date?, limit: Int?) -> [HistoryEntry] {
        let filtered = storage
            .filter { entry in since.map { entry.createdAt >= $0 } ?? true }
            .sorted { $0.createdAt > $1.createdAt }
        return limit.map { Array(filtered.prefix($0)) } ?? filtered
    }

    public func delete(id: UUID) throws {
        try guardWrite()
        storage.removeAll { $0.id == id }
    }

    public func deleteAll() throws {
        try guardWrite()
        storage.removeAll()
    }
}

public final class InMemoryProposalCache: ProposalCaching {
    private let value = Mutex<CachedProposal?>(nil)
    public init() {}
    public func load() -> CachedProposal? { value.withLock { $0 } }
    public func save(_ proposal: CachedProposal) { value.withLock { $0 = proposal } }
    public func clear() { value.withLock { $0 = nil } }
}

public final class InMemoryNotificationLedger: NotificationLedger {
    private let dates = Mutex<[Date]>([])
    public init(_ initial: [Date] = []) { dates.withLock { $0 = initial } }
    public func deliveries(since date: Date) -> [Date] { dates.withLock { $0.filter { $0 >= date } } }
    public func recordDelivery(at date: Date) { dates.withLock { $0.append(date) } }
}

public final class InMemoryConnectionStore: ConnectionStore {
    private let value: Mutex<BackendEndpoint?>
    public init(_ endpoint: BackendEndpoint? = nil) { value = Mutex(endpoint) }
    public func load() -> BackendEndpoint? { value.withLock { $0 } }
    public func save(_ endpoint: BackendEndpoint) throws { value.withLock { $0 = endpoint } }
    public func clear() throws { value.withLock { $0 = nil } }
}

/// 通知を実際には出さず、記録だけする
public final class RecordingNotificationScheduler: NotificationScheduling {
    private let state: Mutex<(authorization: NotificationAuthorization, grantOnRequest: Bool, delivered: [NotificationContent])>

    public init(authorization: NotificationAuthorization = .authorized, grantOnRequest: Bool = true) {
        state = Mutex((authorization, grantOnRequest, []))
    }

    public var delivered: [NotificationContent] { state.withLock { $0.delivered } }

    public func authorization() async -> NotificationAuthorization { state.withLock { $0.authorization } }

    public func requestAuthorization() async -> Bool {
        state.withLock {
            $0.authorization = $0.grantOnRequest ? .authorized : .denied
            return $0.grantOnRequest
        }
    }

    public func deliver(_ content: NotificationContent, identifier: String) async throws {
        state.withLock { $0.delivered.append(content) }
    }
}
