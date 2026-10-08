import Foundation

/// 自分の樹にだけある体験と、体験どうしを結んだ糸。端末の中にだけ置く (体験帳と同じ扱い)。
///
/// - 編んだ体験 (woven): 自分で書いた体験。どの体験から伸ばすかを選べる
/// - 見つけた体験 (found): AIが新しく作り、自分で「やってみる」を選んだ体験。ライブラリに無いので、ここで樹に植える
/// - 結び (ties): 灯った体験どうしを、自分で結んだ朱の糸。何が響き合ったかを短く添えられる
public struct Garden: Codable, Sendable, Equatable {
    public var version: Int
    public var nodes: [PersonalNode]
    public var ties: [Tie]

    public init(version: Int = 1, nodes: [PersonalNode] = [], ties: [Tie] = []) {
        self.version = version
        self.nodes = nodes
        self.ties = ties
    }

    public static let empty = Garden()

    public var isEmpty: Bool { nodes.isEmpty && ties.isEmpty }

    public func node(_ id: String) -> PersonalNode? { nodes.first { $0.id == id } }

    public func node(titled title: String) -> PersonalNode? { nodes.first { $0.title == title } }
}

/// 自分の樹にだけある体験
public struct PersonalNode: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        /// 自分で編んだ
        case woven
        /// AIが作った体験を、やってみることにした
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
    /// どの体験から伸びているか
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

    /// 新しい id (英小文字と数字。API の id の形に合わせる)
    public static func makeID(kind: Kind) -> String {
        let prefix = kind == .woven ? "w-" : "f-"
        let raw = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        return prefix + String(raw.prefix(12))
    }
}

/// 体験どうしを結んだ糸 (向きは無い)
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
