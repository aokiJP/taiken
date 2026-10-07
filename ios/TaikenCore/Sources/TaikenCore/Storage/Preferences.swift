import Foundation

// MARK: - 情報の種類ごとの許可 (指示書 §19)

/// OSの許可とは別に、アプリ内でも情報の種類ごとにAIへ渡すかを選べる。
public enum ConsentKey {
    public static let useCalendar = "consent.useCalendar"
    public static let sendEventTitles = "consent.sendEventTitles"
    public static let useChatContext = "consent.useChatContext"
    public static let useHistory = "consent.useHistory"
    public static let useLocation = "consent.useLocation"
    public static let allowWebSearch = "consent.allowWebSearch"
}

public struct ConsentSnapshot: Sendable, Equatable {
    public var useCalendar: Bool
    public var sendEventTitles: Bool
    public var useChatContext: Bool
    public var useHistory: Bool
    /// 既定はオフ (必要な人だけが有効にする)
    public var useLocation: Bool
    public var allowWebSearch: Bool

    public init(useCalendar: Bool = true, sendEventTitles: Bool = true, useChatContext: Bool = true, useHistory: Bool = true, useLocation: Bool = false, allowWebSearch: Bool = false) {
        self.useCalendar = useCalendar
        self.sendEventTitles = sendEventTitles
        self.useChatContext = useChatContext
        self.useHistory = useHistory
        self.useLocation = useLocation
        self.allowWebSearch = allowWebSearch
    }

    public static var defaultValues: [String: Any] {
        [
            ConsentKey.useCalendar: true,
            ConsentKey.sendEventTitles: true,
            ConsentKey.useChatContext: true,
            ConsentKey.useHistory: true,
            ConsentKey.useLocation: false,
            ConsentKey.allowWebSearch: false,
        ]
    }

    public static func load(from defaults: UserDefaults) -> ConsentSnapshot {
        defaults.register(defaults: defaultValues)
        return ConsentSnapshot(
            useCalendar: defaults.bool(forKey: ConsentKey.useCalendar),
            sendEventTitles: defaults.bool(forKey: ConsentKey.sendEventTitles),
            useChatContext: defaults.bool(forKey: ConsentKey.useChatContext),
            useHistory: defaults.bool(forKey: ConsentKey.useHistory),
            useLocation: defaults.bool(forKey: ConsentKey.useLocation),
            allowWebSearch: defaults.bool(forKey: ConsentKey.allowWebSearch)
        )
    }
}

// MARK: - 通知の設定

public struct NotificationPreferences: Codable, Sendable, Equatable {
    public var enabled: Bool
    /// この時刻から quietEndHour までは通知しない (日をまたいでよい)
    public var quietStartHour: Int
    public var quietEndHour: Int
    public var maxPerDay: Int
    public var minimumIntervalHours: Int

    public init(enabled: Bool = false, quietStartHour: Int = 22, quietEndHour: Int = 8, maxPerDay: Int = 2, minimumIntervalHours: Int = 3) {
        self.enabled = enabled
        self.quietStartHour = quietStartHour
        self.quietEndHour = quietEndHour
        self.maxPerDay = maxPerDay
        self.minimumIntervalHours = minimumIntervalHours
    }

    /// 範囲外の値を直した値
    public var normalized: NotificationPreferences {
        NotificationPreferences(
            enabled: enabled,
            quietStartHour: min(23, max(0, quietStartHour)),
            quietEndHour: min(23, max(0, quietEndHour)),
            maxPerDay: min(5, max(1, maxPerDay)),
            minimumIntervalHours: min(12, max(1, minimumIntervalHours))
        )
    }
}

/// UserDefaults を使う小さな保存先 (UserDefaults 自体がスレッドセーフ)
public final class DefaultsStore: @unchecked Sendable {
    public let defaults: UserDefaults

    public init(_ defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: 許可

    public func consent() -> ConsentSnapshot { ConsentSnapshot.load(from: defaults) }

    // MARK: 通知の設定

    private static let notificationKey = "notifications.preferences"

    public func notificationPreferences() -> NotificationPreferences {
        guard let data = defaults.data(forKey: Self.notificationKey),
              let value = try? JSONDecoder().decode(NotificationPreferences.self, from: data) else { return NotificationPreferences() }
        return value.normalized
    }

    public func saveNotificationPreferences(_ value: NotificationPreferences) {
        if let data = try? JSONEncoder().encode(value.normalized) { defaults.set(data, forKey: Self.notificationKey) }
    }

    // MARK: インストールID

    private static let installKey = "app.installID"

    /// レート制御用のランダムなID。個人を特定する情報は含まない。
    public func installID() -> String {
        if let id = defaults.string(forKey: Self.installKey) { return id }
        let id = UUID().uuidString
        defaults.set(id, forKey: Self.installKey)
        return id
    }

    // MARK: 全消去

    public func removeAll(keepingConsent: Bool = true) {
        for key in [Self.notificationKey, UserDefaultsProposalCache.key, UserDefaultsNotificationLedger.key] {
            defaults.removeObject(forKey: key)
        }
        if !keepingConsent {
            for key in ConsentSnapshot.defaultValues.keys { defaults.removeObject(forKey: key) }
        }
    }
}

/// 最後の提案を当日中だけ覚えておき、オフラインでも開いた瞬間に表示できるようにする。
public final class UserDefaultsProposalCache: ProposalCaching, @unchecked Sendable {
    static let key = "home.lastProposal"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func load() -> CachedProposal? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(CachedProposal.self, from: data)
    }

    public func save(_ proposal: CachedProposal) {
        if let data = try? JSONEncoder().encode(proposal) { defaults.set(data, forKey: Self.key) }
    }

    public func clear() { defaults.removeObject(forKey: Self.key) }
}

/// 通知を出した時刻を直近分だけ保存する
public final class UserDefaultsNotificationLedger: NotificationLedger, @unchecked Sendable {
    static let key = "notifications.deliveries"
    private let defaults: UserDefaults
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func deliveries(since date: Date) -> [Date] {
        lock.withLock { stored() }.filter { $0 >= date }
    }

    public func recordDelivery(at date: Date) {
        lock.withLock {
            // 2日より古い記録は不要
            let recent = stored().filter { date.timeIntervalSince($0) < 2 * 86_400 } + [date]
            defaults.set(recent.map(\.timeIntervalSince1970), forKey: Self.key)
        }
    }

    private func stored() -> [Date] {
        (defaults.array(forKey: Self.key) as? [Double] ?? []).map(Date.init(timeIntervalSince1970:))
    }
}
