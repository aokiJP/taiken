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
    /// 体験のあとに思い返すための問い (提案に付いていた場合)
    public let reflectionQuestion: String?

    public init(
        id: UUID = UUID(), createdAt: Date, finishedAt: Date? = nil, title: String, theme: String?,
        invitation: String, perspective: String, tags: [String], status: Status, rating: Rating? = nil, note: String? = nil,
        reflectionQuestion: String? = nil
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
        self.reflectionQuestion = reflectionQuestion
    }

    public init(experience: Experience, theme: String?, status: Status, at date: Date) {
        self.init(
            createdAt: date, title: experience.title, theme: theme, invitation: experience.invitation,
            perspective: experience.perspective, tags: experience.tags, status: status,
            reflectionQuestion: experience.reflectionQuestion
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

    /// ユーザーが実際に選んだ体験か (体験帳に出すもの)
    public var wasChosen: Bool { status == .active || status == .completed }

    public var experience: Experience {
        Experience(
            title: title, perspective: perspective, invitation: invitation, reason: "", difficulty: .low,
            tags: tags, reflectionQuestion: reflectionQuestion
        )
    }

    /// 体験帳の印に刻む一文字
    public var sealCharacter: String { ExperienceTag.sealCharacter(ExperienceTag.primary(of: tags)) }

    public func reference(timeZone: TimeZone = .current) -> ExperienceRef {
        ExperienceRef(title: title, theme: theme, reaction: reaction, rating: rating, date: APICoding.dayString(createdAt, timeZone: timeZone))
    }
}

/// 体験タグの日本語名と、体験帳の「印」に刻む文字 (表示用)
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

    /// 印の文字。体験の性質を一文字で表す
    public static let seals: [String: String] = [
        "new_perspective": "新",
        "question": "問",
        "small_challenge": "試",
        "observation": "観",
        "sensory": "感",
        "reflection": "思",
        "social": "縁",
        "creative": "創",
        "competitive": "競",
        "short": "刻",
        "long_duration": "久",
    ]

    public static func label(_ tag: String) -> String { labels[tag] ?? tag }

    /// 時間の長さを表すタグより、体験の性質を表すタグを代表にする
    public static func primary(of tags: [String]) -> String? {
        tags.first { $0 != "short" && $0 != "long_duration" && labels[$0] != nil } ?? tags.first { labels[$0] != nil }
    }

    /// タグが無い・未知のときは「体」
    public static func sealCharacter(_ tag: String?) -> String {
        tag.flatMap { seals[$0] } ?? "体"
    }

    /// 画面に並べるタグ (表示名のあるものだけ。重複なし)
    public static func displayLabels(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.compactMap { tag in
            guard let label = labels[tag], seen.insert(tag).inserted else { return nil }
            return label
        }
    }
}
