import Foundation

/// 体験履歴の1件 (指示書 §15)。保存先 (SwiftData など) に依存しない値型。
public struct HistoryEntry: Codable, Hashable, Sendable, Identifiable {
    public enum Status: String, Codable, Sendable, CaseIterable {
        /// やってみている
        case active
        /// 終えた
        case completed
        /// 今はやらない
        case declined
        /// 別の提案を選んだ
        case skipped
    }

    public let id: UUID
    public let createdAt: Date
    public var finishedAt: Date?
    public let title: String
    public let theme: String?
    public let invitation: String
    public let perspective: String
    public let tags: [String]
    public var status: Status
    public var rating: Rating?
    /// ひとこと感想 (任意・端末内のみ。AIへは送らない)
    public var note: String?

    public init(
        id: UUID = UUID(), createdAt: Date, finishedAt: Date? = nil, title: String, theme: String?,
        invitation: String, perspective: String, tags: [String], status: Status, rating: Rating? = nil, note: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.finishedAt = finishedAt
        self.title = title
        self.theme = theme
        self.invitation = invitation
        self.perspective = perspective
        self.tags = tags
        self.status = status
        self.rating = rating
        self.note = note
    }

    public init(experience: Experience, theme: String?, status: Status, at date: Date) {
        self.init(
            createdAt: date, title: experience.title, theme: theme, invitation: experience.invitation,
            perspective: experience.perspective, tags: experience.tags, status: status
        )
    }

    public var reaction: Reaction {
        switch status {
        case .active: .accepted
        case .completed: .completed
        case .declined: .declined
        case .skipped: .alternative
        }
    }

    /// ユーザーが実際に選んだ体験か (履歴画面に出すもの)
    public var wasChosen: Bool { status == .active || status == .completed }

    public var experience: Experience {
        Experience(title: title, perspective: perspective, invitation: invitation, reason: "", difficulty: .low, tags: tags)
    }

    public func reference(timeZone: TimeZone = .current) -> ExperienceRef {
        ExperienceRef(title: title, theme: theme, reaction: reaction, rating: rating, date: APICoding.dayString(createdAt, timeZone: timeZone))
    }
}

/// 体験タグの日本語名 (表示用)
public enum ExperienceTag {
    public static let labels: [String: String] = [
        "new_perspective": "新しい視点",
        "question": "問い",
        "small_challenge": "小さな挑戦",
        "observation": "観察",
        "sensory": "五感",
        "reflection": "ふり返り",
        "social": "人との関わり",
        "creative": "つくること",
        "competitive": "競う要素",
        "short": "短い時間",
        "long_duration": "長い時間",
    ]

    public static func label(_ tag: String) -> String { labels[tag] ?? tag }
}
