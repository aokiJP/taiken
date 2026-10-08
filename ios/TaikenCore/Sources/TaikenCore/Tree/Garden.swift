import Foundation

/// 自分の樹にだけあるもの。端末の中にだけ置く (体験帳と同じ扱い)。
///
/// - 身についた技 (learned): 芽を使って伸ばした技と、閃いた技。いつ身についたか
/// - 記録と技 (uses): 記した体験で、どの技を使ったか (自分で選んだもの)
/// - 編んだ技 (nodes, woven): 自分で名づけて樹に植えた技。3.0 で編んだ体験も、ここに残っている
/// - 結び (ties): 響き合った技どうしを、自分で結んだ朱の糸
/// - 見届け (seen): 4.0 にしてから、樹の伸びを見せたか
///
/// 経験と段は体験帳から毎回数え直すので、ここには置かない (食い違う二つの真実を持たない)。
public struct Garden: Codable, Sendable, Equatable {
    public static let currentVersion = 2

    public var version: Int
    public var nodes: [PersonalNode]
    public var ties: [Tie]
    public var learned: [LearnedSkill]
    public var uses: [SkillUse]
    /// 4.0 の樹の伸びを、いちど見届けたか (3.0 から来たときに一度だけ「これまでの体験から」を見せる)
    public var seen: Bool

    public init(
        version: Int = Garden.currentVersion, nodes: [PersonalNode] = [], ties: [Tie] = [], learned: [LearnedSkill] = [],
        uses: [SkillUse] = [], seen: Bool = false
    ) {
        self.version = version
        self.nodes = nodes
        self.ties = ties
        self.learned = learned
        self.uses = uses
        self.seen = seen
    }

    enum CodingKeys: String, CodingKey {
        case version, nodes, ties, learned, uses, seen
    }

    /// 3.0 の形 (version 1: nodes と ties だけ) も読む
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        nodes = try c.decodeIfPresent([PersonalNode].self, forKey: .nodes) ?? []
        ties = try c.decodeIfPresent([Tie].self, forKey: .ties) ?? []
        learned = try c.decodeIfPresent([LearnedSkill].self, forKey: .learned) ?? []
        uses = try c.decodeIfPresent([SkillUse].self, forKey: .uses) ?? []
        seen = try c.decodeIfPresent(Bool.self, forKey: .seen) ?? false
    }

    public static let empty = Garden()

    public var isEmpty: Bool { nodes.isEmpty && ties.isEmpty && learned.isEmpty && uses.isEmpty }

    public func node(_ id: String) -> PersonalNode? { nodes.first { $0.id == id } }

    public func node(titled title: String) -> PersonalNode? { nodes.first { $0.title == title } }

    /// 編んだ技 (3.0 で見つけた体験は、樹には出さない。記録は体験帳に残っている)
    public var wovenNodes: [PersonalNode] { nodes.filter { $0.kind == .woven } }

    public func learned(_ id: String) -> LearnedSkill? { learned.first { $0.id == id } }

    public func isLearned(_ id: String) -> Bool { learned.contains { $0.id == id } }

    /// 記録に結んだ技
    public func skills(usedIn entryID: UUID) -> [String] {
        uses.first { $0.entryID == entryID }?.skills ?? []
    }
}

/// 身についた技
public struct LearnedSkill: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    /// 芽を使った要素 (閃きは芽を使わないので nil)
    public let element: String?
    public let learnedAt: Date

    public init(id: String, element: String?, learnedAt: Date) {
        self.id = id
        self.element = element
        self.learnedAt = learnedAt
    }
}

/// 記した体験で使った技 (自分で選んだもの。稽古から始めた体験は、選ばなくてもその技に数える)
public struct SkillUse: Codable, Sendable, Hashable {
    public let entryID: UUID
    public var skills: [String]

    public init(entryID: UUID, skills: [String]) {
        self.entryID = entryID
        self.skills = skills
    }
}

/// 自分の樹にだけある技 (と、3.0 で編んだり見つけたりした体験)
///
/// 4.0 では、編んだもの (woven) は「自分で名づけた技」として読む:
/// - title: 技の名前
/// - perspective: できるようになること (3.0 の体験で空なら、誘いかけを使う)
/// - invitation: 自分の稽古 (この技の見方で、いつもの一日を過ごす入口。空でもよい)
public struct PersonalNode: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        /// 自分で編んだ
        case woven
        /// 3.0: AIが作った体験を、やってみることにした (4.0 では樹に出さない)
        case found
    }

    public let id: String
    public var kind: Kind
    public var title: String
    public var invitation: String
    public var perspective: String
    public var reflectionQuestion: String?
    /// 要素の id (先頭が主な要素)
    public var elements: [String]
    public var tags: [String]
    /// どの技から伸びているか (無ければ要素の根から)
    public var growsFrom: String?
    public let createdAt: Date

    public init(
        id: String, kind: Kind, title: String, invitation: String, perspective: String = "", reflectionQuestion: String? = nil,
        elements: [String], tags: [String] = [], growsFrom: String? = nil, createdAt: Date
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.invitation = invitation
        self.perspective = perspective
        self.reflectionQuestion = reflectionQuestion
        self.elements = elements
        self.tags = tags
        self.growsFrom = growsFrom
        self.createdAt = createdAt
    }

    /// 新しい id (英小文字と数字)
    public static func makeID(kind: Kind) -> String {
        let prefix = kind == .woven ? "w-" : "f-"
        let raw = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        return prefix + String(raw.prefix(12))
    }

    /// 技として読んだときの「できるようになること」
    public var ability: String {
        let text = perspective.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? invitation : text
    }
}

/// 技どうしを結んだ糸 (向きは無い)
public struct Tie: Codable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let a: String
    public let b: String
    /// 何が響き合ったか (任意・40文字まで)
    public var note: String?
    public let createdAt: Date

    public init(id: UUID = UUID(), between first: String, and second: String, note: String? = nil, createdAt: Date) {
        self.id = id
        // 向きを持たないので、いつも同じ順に並べて重複を見つけやすくする
        if first <= second {
            a = first
            b = second
        } else {
            a = second
            b = first
        }
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.note = trimmed?.isEmpty == false ? String(trimmed!.prefix(40)) : nil
        self.createdAt = createdAt
    }

    public func connects(_ first: String, _ second: String) -> Bool {
        (a == first && b == second) || (a == second && b == first)
    }

    public func other(than id: String) -> String? {
        if a == id { return b }
        if b == id { return a }
        return nil
    }
}

// MARK: - 保存先

public protocol GardenStore: Sendable {
    func load() -> Garden
    func save(_ garden: Garden) throws
}

/// テスト・プレビュー用
public final class InMemoryGardenStore: GardenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: Garden
    /// テスト用: true にすると保存が失敗する
    public var failWrites = false

    public init(_ garden: Garden = .empty) {
        value = garden
    }

    public func load() -> Garden { lock.withLock { value } }

    public func save(_ garden: Garden) throws {
        try lock.withLock {
            if failWrites { throw AppError.storage }
            value = garden
        }
    }
}

/// JSON ファイルに置く (アプリ自身の領域。App Group にも iCloud にも置かない)
public final class FileGardenStore: GardenStore, @unchecked Sendable {
    public let url: URL
    private let lock = NSLock()

    public init(url: URL) {
        self.url = url
    }

    /// アプリの Application Support の中 (なければ作る)
    public static func applicationSupport(fileName: String = "garden.json") -> FileGardenStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("Taiken", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return FileGardenStore(url: directory.appendingPathComponent(fileName))
    }

    public func load() -> Garden {
        lock.withLock {
            guard let data = try? Data(contentsOf: url) else { return .empty }
            return (try? Self.decoder.decode(Garden.self, from: data)) ?? .empty
        }
    }

    public func save(_ garden: Garden) throws {
        try lock.withLock {
            let data = try Self.encoder.encode(garden)
            do {
                #if os(iOS)
                try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                #else
                try data.write(to: url, options: [.atomic])
                #endif
            } catch {
                throw AppError.storage
            }
        }
    }

    public func delete() {
        lock.withLock { _ = try? FileManager.default.removeItem(at: url) }
    }

    static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
