import Foundation

/// 体験ライブラリ・要素・テーマ・気分。
/// 正は contracts/content.ja.json で、iOS と Backend が同じ内容のコピーを持つ (テストで一致を確認する)。
///
/// 体験はそれぞれ 1〜3 個の「要素」(見る・聴く・嗅ぐ・味わう・触れる・動く・休む・考える・言葉にする・人と) でできていて、
/// 「つながり」(opens) で次の体験へ枝を伸ばす。要素ごとに、いちばん小さなかたちの体験が「根」になる。
public struct TaikenContent: Decodable, Sendable {
    /// 体験の要素。体験の樹の根元の10本の枝
    public struct Element: Decodable, Sendable, Hashable, Identifiable {
        public let id: String
        /// 印に刻むひと文字 (見・聴・香・味・触・動・休・考・言・人)
        public let glyph: String
        /// 見る・聴く…
        public let label: String
        /// ひとことの説明
        public let hint: String
        /// 根になる体験の id
        public let root: String
        /// AIが作った体験の要素を推し量るための手がかり
        public let keywords: [String]
    }

    public struct Theme: Decodable, Sendable, Hashable, Identifiable {
        public let id: String
        public let label: String
        public let keywords: [String]
    }

    public struct MoodEntry: Decodable, Sendable, Hashable, Identifiable {
        public let id: String
        public let label: String
        public let keywords: [String]
    }

    /// 体験から体験へのつながり
    public struct Link: Decodable, Sendable, Hashable {
        public enum Kind: String, Decodable, Sendable, CaseIterable {
            /// 同じ要素で、より細やかに
            case deepen
            /// 同じ要素で、別の場面へ
            case widen
            /// 別の要素へ渡る
            case cross

            public init(from decoder: any Decoder) throws {
                self = Kind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .cross
            }
        }

        public let to: String
        public let kind: Kind

        public init(to: String, kind: Kind) {
            self.to = to
            self.kind = kind
        }
    }

    /// ライブラリの体験1件
    public struct LibraryExperience: Decodable, Sendable, Hashable, Identifiable {
        public let id: String
        public let title: String
        public let perspective: String
        public let invitation: String
        public let reflectionQuestion: String
        public let tags: [String]
        /// study / work / commute ... / rest / morning / night / outdoors / general
        public let themes: [String]
        public let moods: [String]
        /// 空ならいつでも
        public let times: [String]
        /// low / medium
        public let effort: String
        /// 要素の id。先頭が主な要素
        public let elements: [String]
        /// この体験からひらく体験
        public let opens: [Link]

        public init(
            id: String, title: String, perspective: String, invitation: String, reflectionQuestion: String, tags: [String],
            themes: [String], moods: [String], times: [String], effort: String, elements: [String], opens: [Link] = []
        ) {
            self.id = id
            self.title = title
            self.perspective = perspective
            self.invitation = invitation
            self.reflectionQuestion = reflectionQuestion
            self.tags = tags
            self.themes = themes
            self.moods = moods
            self.times = times
            self.effort = effort
            self.elements = elements
            self.opens = opens
        }

        enum CodingKeys: String, CodingKey {
            case id, title, perspective, invitation, reflectionQuestion, tags, themes, moods, times, effort, elements, opens
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            title = try c.decode(String.self, forKey: .title)
            perspective = try c.decode(String.self, forKey: .perspective)
            invitation = try c.decode(String.self, forKey: .invitation)
            reflectionQuestion = try c.decode(String.self, forKey: .reflectionQuestion)
            tags = try c.decode([String].self, forKey: .tags)
            themes = try c.decode([String].self, forKey: .themes)
            moods = try c.decode([String].self, forKey: .moods)
            times = try c.decode([String].self, forKey: .times)
            effort = try c.decode(String.self, forKey: .effort)
            elements = try c.decodeIfPresent([String].self, forKey: .elements) ?? []
            opens = try c.decodeIfPresent([Link].self, forKey: .opens) ?? []
        }

        /// 主な要素
        public var primaryElement: String? { elements.first }
    }

    public let version: Int
    public let elements: [Element]
    public let themes: [Theme]
    public let moods: [MoodEntry]
    public let experiences: [LibraryExperience]

    private let experienceIndex: [String: Int]
    private let titleIndex: [String: Int]
    private let elementIndex: [String: Int]
    private let rootIDs: Set<String>

    enum CodingKeys: String, CodingKey {
        case version, elements, themes, moods, experiences
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            version: try c.decode(Int.self, forKey: .version),
            elements: try c.decodeIfPresent([Element].self, forKey: .elements) ?? [],
            themes: try c.decode([Theme].self, forKey: .themes),
            moods: try c.decode([MoodEntry].self, forKey: .moods),
            experiences: try c.decode([LibraryExperience].self, forKey: .experiences)
        )
    }

    public init(version: Int, elements: [Element], themes: [Theme], moods: [MoodEntry], experiences: [LibraryExperience]) {
        self.version = version
        self.elements = elements
        self.themes = themes
        self.moods = moods
        self.experiences = experiences
        var byID: [String: Int] = [:]
        var byTitle: [String: Int] = [:]
        for (index, item) in experiences.enumerated() {
            if byID[item.id] == nil { byID[item.id] = index }
            if byTitle[item.title] == nil { byTitle[item.title] = index }
        }
        experienceIndex = byID
        titleIndex = byTitle
        var elementByID: [String: Int] = [:]
        for (index, element) in elements.enumerated() where elementByID[element.id] == nil {
            elementByID[element.id] = index
        }
        elementIndex = elementByID
        rootIDs = Set(elements.map(\.root))
    }

    /// アプリ全体で使う内容。読み込めなければ最小限の内容で動き続ける
    public static let shared: TaikenContent = load()

    public static func decode(_ data: Data) throws -> TaikenContent {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(TaikenContent.self, from: data)
    }

    public static var resourceURL: URL? {
        Bundle.module.url(forResource: "content.ja", withExtension: "json")
    }

    static func load() -> TaikenContent {
        guard let url = resourceURL,
              let data = try? Data(contentsOf: url),
              let content = try? decode(data),
              content.isWellFormed
        else { return minimal }
        return content
    }

    /// 要素と根がそろっていて、体験がある
    public var isWellFormed: Bool {
        !elements.isEmpty && !experiences.isEmpty && elements.allSatisfy { experience($0.root) != nil }
    }

    // MARK: - 引く

    public func theme(_ id: String) -> Theme? { themes.first { $0.id == id } }

    public func experience(_ id: String) -> LibraryExperience? {
        experienceIndex[id].map { experiences[$0] }
    }

    public func experience(titled title: String) -> LibraryExperience? {
        titleIndex[title].map { experiences[$0] }
    }

    public func element(_ id: String) -> Element? {
        elementIndex[id].map { elements[$0] }
    }

    /// 要素の並び順 (樹の上で時計回りに並ぶ順番)
    public func elementOrder(_ id: String) -> Int? { elementIndex[id] }

    public func isRoot(_ experienceID: String) -> Bool { rootIDs.contains(experienceID) }

    /// 知っている要素だけを、重複なく、もとの順番で残す
    public func knownElements(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { elementIndex[$0] != nil && seen.insert($0).inserted }
    }

    /// リソースが壊れていたときの最小限の内容 (アプリを止めないため)
    static let minimal: TaikenContent = {
        let see = Element(
            id: "see", glyph: "見", label: "見る", hint: "目に入るものに目を向ける", root: "daily-difference", keywords: ["見"]
        )
        let everyday = LibraryExperience(
            id: "daily-difference", title: "いつもの中の違い",
            perspective: "何気ない時間を、昨日との小さな違いを見つける時間として捉える。",
            invitation: "今日のどこかで、昨日とは少し違うことをひとつ見つけてみませんか？",
            reflectionQuestion: "どんな違いが見つかりましたか？",
            tags: ["observation", "short"], themes: ["general"], moods: [], times: [], effort: "low", elements: ["see"]
        )
        return TaikenContent(version: 0, elements: [see], themes: [], moods: [], experiences: [everyday])
    }()
}
