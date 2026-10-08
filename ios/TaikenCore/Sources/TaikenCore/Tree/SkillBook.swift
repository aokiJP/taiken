import Foundation

/// 技の樹の設計図。正は contracts/skills.ja.json で、iOS がコピーを持つ (テストで一致を確認する)。
///
/// 樹の節は「お題」ではなく、自分の中に育つ感覚や力 (技)。
/// - 一の技: 要素の一段から。根の先にある
/// - 二の技: 三段から。一の技の先にある
/// - 奥義: 六段から。二の技のうち2つの先にある
/// - 渡り技: ふたつの要素のどちらも二段から。どちらかの一の技の先にある
/// - 閃き: 条件は明かさない。暮らし方の組み合わせから、思いがけず身につく (芽は使わない)
///
/// 稽古 (practice) は体験ライブラリの体験。技の見方で、いつもの一日を過ごす入口になる。
public struct SkillBook: Decodable, Sendable {
    public struct Skill: Decodable, Sendable, Hashable, Identifiable {
        public enum Kind: String, Decodable, Sendable {
            /// 一の技・二の技
            case art
            /// 奥義
            case secret
            /// 渡り技 (ふたつの要素のあいだ)
            case cross
            /// 閃き (条件を明かさない)
            case flash
        }

        public let id: String
        public let kind: Kind
        /// 主な要素 (樹の上の置き場所と、印の字)
        public let element: String
        /// 渡り技の、もう一方の要素
        public let also: [String]
        public let name: String
        /// 名前の読み (ひらがな)
        public let reading: String
        /// 身につくと、できるようになること (一文)
        public let ability: String
        /// 閃き: 閃いたときのこと (身についたあとにだけ見せる)
        public let found: String?
        /// 先にあるとよい技
        public let after: [String]
        /// after のうち、いくつ身についていればよいか
        public let needs: Int
        /// 要素ごとに要る段
        public let rank: [String: Int]
        /// 稽古 (体験ライブラリの id)
        public let practice: [String]
        /// 記した体験の言葉から、この技を使ったかもしれないと推し量る手がかり
        public let keywords: [String]
        public let flash: FlashRule?

        /// 要素 (先頭が主な要素)
        public var elements: [String] { [element] + also }

        public init(
            id: String, kind: Kind, element: String, also: [String] = [], name: String, reading: String = "", ability: String,
            found: String? = nil, after: [String] = [], needs: Int = 0, rank: [String: Int] = [:], practice: [String] = [],
            keywords: [String] = [], flash: FlashRule? = nil
        ) {
            self.id = id
            self.kind = kind
            self.element = element
            self.also = also
            self.name = name
            self.reading = reading
            self.ability = ability
            self.found = found
            self.after = after
            self.needs = needs
            self.rank = rank
            self.practice = practice
            self.keywords = keywords
            self.flash = flash
        }

        enum CodingKeys: String, CodingKey {
            case id, kind, element, also, name, reading, ability, found, after, needs, rank, practice, keywords, flash
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            kind = try c.decode(Kind.self, forKey: .kind)
            element = try c.decode(String.self, forKey: .element)
            also = try c.decodeIfPresent([String].self, forKey: .also) ?? []
            name = try c.decode(String.self, forKey: .name)
            reading = try c.decodeIfPresent(String.self, forKey: .reading) ?? ""
            ability = try c.decode(String.self, forKey: .ability)
            found = try c.decodeIfPresent(String.self, forKey: .found)
            after = try c.decodeIfPresent([String].self, forKey: .after) ?? []
            needs = try c.decodeIfPresent(Int.self, forKey: .needs) ?? 0
            rank = try c.decodeIfPresent([String: Int].self, forKey: .rank) ?? [:]
            practice = try c.decodeIfPresent([String].self, forKey: .practice) ?? []
            keywords = try c.decodeIfPresent([String].self, forKey: .keywords) ?? []
            flash = try c.decodeIfPresent(FlashRule.self, forKey: .flash)
        }
    }

    /// 閃きの条件。書かれた条件をすべて満たしたときに閃く
    public struct FlashRule: Decodable, Sendable, Hashable {
        /// ひとつの体験で触れた五感 (見る・聴く・嗅ぐ・味わう・触れる) の数
        public var senses: Int?
        /// ひとつの体験で触れた要素の数
        public var elements: Int?
        /// 記した時間帯 (TimeOfDay の rawValue)
        public var times: [String]?
        /// その体験が触れている要素
        public var element: String?
        /// ひとつの日のうちに記した、別々の時間帯の数
        public var bands: Int?
        /// すべての要素が、この段に届いている
        public var allElements: Int?
        /// 記した日の数 (続けて、でなくてよい)
        public var days: Int?
        /// 自分で見つけて記した体験の数
        public var selfRecorded: Int?
        /// 結んだ糸の数
        public var ties: Int?
        /// 離に届いた技の数
        public var mastered: Int?

        public init(
            senses: Int? = nil, elements: Int? = nil, times: [String]? = nil, element: String? = nil, bands: Int? = nil,
            allElements: Int? = nil, days: Int? = nil, selfRecorded: Int? = nil, ties: Int? = nil, mastered: Int? = nil
        ) {
            self.senses = senses
            self.elements = elements
            self.times = times
            self.element = element
            self.bands = bands
            self.allElements = allElements
            self.days = days
            self.selfRecorded = selfRecorded
            self.ties = ties
            self.mastered = mastered
        }

        enum CodingKeys: String, CodingKey {
            case senses, elements, times, element, bands, days, ties, mastered
            case allElements = "all_elements"
            case selfRecorded = "self"
        }
    }

    /// 使うほど深まる: 守 (身についた) → 破 (ha 回) → 離 (ri 回)
    public struct MasterySteps: Decodable, Sendable, Hashable {
        public let ha: Int
        public let ri: Int

        public init(ha: Int, ri: Int) {
            self.ha = ha
            self.ri = ri
        }
    }

    public let version: Int
    public let mastery: MasterySteps
    public let skills: [Skill]

    private let index: [String: Int]
    private let practiceIndex: [String: [Int]]

    enum CodingKeys: String, CodingKey {
        case version, mastery, skills
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            version: try c.decode(Int.self, forKey: .version),
            mastery: try c.decodeIfPresent(MasterySteps.self, forKey: .mastery) ?? MasterySteps(ha: 3, ri: 7),
            skills: try c.decode([Skill].self, forKey: .skills)
        )
    }

    public init(version: Int, mastery: MasterySteps = MasterySteps(ha: 3, ri: 7), skills: [Skill]) {
        self.version = version
        self.mastery = mastery
        self.skills = skills
        var index: [String: Int] = [:]
        var practice: [String: [Int]] = [:]
        for (i, skill) in skills.enumerated() where index[skill.id] == nil {
            index[skill.id] = i
            for id in skill.practice { practice[id, default: []].append(i) }
        }
        self.index = index
        practiceIndex = practice
    }

    /// アプリ全体で使う技の樹。読み込めなければ空の樹で動き続ける (要素の根と段だけになる)
    public static let shared: SkillBook = load()

    public static func decode(_ data: Data) throws -> SkillBook {
        try JSONDecoder().decode(SkillBook.self, from: data)
    }

    public static var resourceURL: URL? {
        Bundle.module.url(forResource: "skills.ja", withExtension: "json")
    }

    static func load() -> SkillBook {
        guard let url = resourceURL, let data = try? Data(contentsOf: url), let book = try? decode(data) else { return .empty }
        return book
    }

    public static let empty = SkillBook(version: 0, skills: [])

    // MARK: - 引く

    public func skill(_ id: String) -> Skill? { index[id].map { skills[$0] } }

    /// この体験 (ライブラリの id) を稽古にしている技
    public func skills(practicing experienceID: String) -> [Skill] {
        (practiceIndex[experienceID] ?? []).map { skills[$0] }
    }

    /// 閃きの技 (身についていないものは、樹にも出さない)
    public var flashes: [Skill] { skills.filter { $0.kind == .flash } }
}
