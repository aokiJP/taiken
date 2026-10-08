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
    /// 体験の樹の上のどの体験か (ライブラリの id、または自分で編んだ・見つけた体験の id)。3.0 より前の記録には無い
    public let nodeID: String?
    /// 要素の id (先頭が主な要素)。3.0 より前の記録には無い (そのときは名前と文から推し量る)
    public let elements: [String]

    public init(
        id: UUID = UUID(), createdAt: Date, finishedAt: Date? = nil, title: String, theme: String?,
        invitation: String, perspective: String, tags: [String], status: Status, rating: Rating? = nil, note: String? = nil,
        reflectionQuestion: String? = nil, nodeID: String? = nil, elements: [String] = []
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
        self.nodeID = nodeID
        self.elements = elements
    }

    public init(experience: Experience, theme: String?, status: Status, at date: Date) {
        self.init(
            createdAt: date, title: experience.title, theme: theme, invitation: experience.invitation,
            perspective: experience.perspective, tags: experience.tags, status: status,
            reflectionQuestion: experience.reflectionQuestion, nodeID: experience.nodeID, elements: experience.elements
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, createdAt, finishedAt, title, theme, invitation, perspective, tags, status, rating, note, reflectionQuestion
        case nodeID, elements
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        finishedAt = try c.decodeIfPresent(Date.self, forKey: .finishedAt)
        title = try c.decode(String.self, forKey: .title)
        theme = try c.decodeIfPresent(String.self, forKey: .theme)
        invitation = try c.decode(String.self, forKey: .invitation)
        perspective = try c.decode(String.self, forKey: .perspective)
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        status = try c.decode(Status.self, forKey: .status)
        rating = try c.decodeIfPresent(Rating.self, forKey: .rating)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        reflectionQuestion = try c.decodeIfPresent(String.self, forKey: .reflectionQuestion)
        nodeID = try c.decodeIfPresent(String.self, forKey: .nodeID)
        elements = try c.decodeIfPresent([String].self, forKey: .elements) ?? []
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
            tags: tags, reflectionQuestion: reflectionQuestion, nodeID: nodeID, elements: resolvedElements()
        )
    }

    /// この記録の要素。記録に無ければ、ライブラリの同じ体験か、名前と文から推し量る
    public func resolvedElements(content: TaikenContent = .shared) -> [String] {
        let known = content.knownElements(elements)
        if !known.isEmpty { return known }
        if let nodeID, let item = content.experience(nodeID) { return item.elements }
        if let item = content.experience(titled: title) { return item.elements }
        return ElementClassifier(content: content).classify(title: title, invitation: invitation, perspective: perspective, tags: tags)
    }

    /// 体験帳の印に刻む一文字 (主な要素の字)
    public var sealCharacter: String {
        ElementClassifier.glyph(for: resolvedElements())
    }

    public func reference(timeZone: TimeZone = .current) -> ExperienceRef {
        ExperienceRef(title: title, theme: theme, reaction: reaction, rating: rating, date: APICoding.dayString(createdAt, timeZone: timeZone))
    }

    /// 同じ記録の、樹の上の位置だけを変えたもの
    public func placed(nodeID: String?, elements: [String]) -> HistoryEntry {
        HistoryEntry(
            id: id, createdAt: createdAt, finishedAt: finishedAt, title: title, theme: theme, invitation: invitation,
            perspective: perspective, tags: tags, status: status, rating: rating, note: note,
            reflectionQuestion: reflectionQuestion, nodeID: nodeID, elements: elements
        )
    }
}

/// 体験タグの日本語名 (表示用。反応の傾向にも使う)
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

    /// 時間の長さを表すタグより、体験の性質を表すタグを代表にする
    public static func primary(of tags: [String]) -> String? {
        tags.first { $0 != "short" && $0 != "long_duration" && labels[$0] != nil } ?? tags.first { labels[$0] != nil }
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
