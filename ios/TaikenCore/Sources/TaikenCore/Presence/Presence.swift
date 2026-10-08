import Foundation
import Synchronization

// 体験を「アプリの外」にも置いておくための出入口。
// - ExperiencePresence: 体験中の内容をロック画面 (Live Activity) に置く
// - WidgetPublishing: ホーム画面・ロック画面のウィジェットに今日の体験を出す
// 実装はアプリ側 (ActivityKit / WidgetKit + App Group) にあり、テストでは記録だけの実装に差し替える。

// MARK: - ロック画面 (Live Activity)

@MainActor
public protocol ExperiencePresence: AnyObject {
    /// 体験を始めた
    func begin(_ entry: HistoryEntry)
    /// 体験を終えた・やめた
    func end()
    /// 起動時など: 体験中でなければ残っている表示を片づける (ユーザーが消した表示を勝手に戻さない)
    func sync(active: HistoryEntry?)
}

/// 何もしない (プレビュー・ロック画面に出さない設定)
@MainActor
public final class NoPresence: ExperiencePresence {
    public init() {}
    public func begin(_ entry: HistoryEntry) {}
    public func end() {}
    public func sync(active: HistoryEntry?) {}
}

/// テスト用: 呼ばれた順番を記録する
@MainActor
public final class RecordingPresence: ExperiencePresence {
    public private(set) var events: [String] = []
    public init() {}
    public func begin(_ entry: HistoryEntry) { events.append("begin:\(entry.title)") }
    public func end() { events.append("end") }
    public func sync(active: HistoryEntry?) { events.append("sync:\(active?.title ?? "-")") }
}

// MARK: - ウィジェット

/// ウィジェットに渡す今日の状態。App Group の UserDefaults に JSON で置く
public struct WidgetSnapshot: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        /// 今日の提案がある
        case proposal
        /// 体験中
        case active
        /// ひと休み中・提案なし
        case resting
        case empty
    }

    public var kind: Kind
    public var title: String?
    public var invitation: String?
    public var reflectionQuestion: String?
    public var startedAt: Date?
    public var sealCharacter: String?
    public var solarTerm: String
    public var microSeason: String
    public var microSeasonMeaning: String
    public var updatedAt: Date

    public init(
        kind: Kind, title: String? = nil, invitation: String? = nil, reflectionQuestion: String? = nil, startedAt: Date? = nil,
        sealCharacter: String? = nil, season: MicroSeason, updatedAt: Date
    ) {
        self.kind = kind
        self.title = title
        self.invitation = invitation
        self.reflectionQuestion = reflectionQuestion
        self.startedAt = startedAt
        self.sealCharacter = sealCharacter
        solarTerm = season.solarTerm
        microSeason = season.name
        microSeasonMeaning = season.meaning
        self.updatedAt = updatedAt
    }

    /// 更新時刻以外が同じか (同じ内容でウィジェットを何度も描き直さない)
    public func hasSameContent(as other: WidgetSnapshot) -> Bool {
        var a = self
        var b = other
        a.updatedAt = .distantPast
        b.updatedAt = .distantPast
        return a == b
    }

    /// ウィジェットのプレビュー用
    public static func sample(now: Date = Date()) -> WidgetSnapshot {
        WidgetSnapshot(
            kind: .proposal, title: "渡っていくもの",
            invitation: "移動の途中で一度だけ空を見上げて、渡っていくものを探してみませんか？",
            reflectionQuestion: "空には、何が渡っていましたか？", sealCharacter: "観",
            season: MicroSeason.entry(48), updatedAt: now
        )
    }
}

public protocol WidgetPublishing: Sendable {
    func publish(_ snapshot: WidgetSnapshot)
}

/// App Group の UserDefaults に置く (アプリが書き、ウィジェットが読む)
public final class WidgetSnapshotStore: @unchecked Sendable {
    public static let key = "widget.snapshot"
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    /// 内容が変わったときだけ保存し、true を返す
    @discardableResult
    public func save(_ snapshot: WidgetSnapshot) -> Bool {
        if let current = load(), current.hasSameContent(as: snapshot) { return false }
        guard let data = try? JSONEncoder().encode(snapshot) else { return false }
        defaults.set(data, forKey: Self.key)
        return true
    }

    public func load() -> WidgetSnapshot? {
        guard let data = defaults.data(forKey: Self.key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    public func clear() {
        defaults.removeObject(forKey: Self.key)
    }
}

/// テスト用: 渡された状態を記録する
public final class RecordingWidgetPublisher: WidgetPublishing {
    private let stored = Mutex<[WidgetSnapshot]>([])
    public init() {}
    public var snapshots: [WidgetSnapshot] { stored.withLock { $0 } }
    public func publish(_ snapshot: WidgetSnapshot) { stored.withLock { $0.append(snapshot) } }
}
