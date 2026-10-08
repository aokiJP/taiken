import Foundation
import SwiftData
import TaikenCore

// 体験帳の保存形式。モデルを変えるときは新しい VersionedSchema を足し、
// TaikenMigrationPlan に移行手順を足す (既存ユーザーの体験帳を壊さないため)。
// 古いスキーマの型は、移行のために残しておく (中身を変えない)。

enum TaikenSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] { [ExperienceRecord.self] }

    @Model
    final class ExperienceRecord {
        @Attribute(.unique) var id: UUID
        var createdAt: Date
        var finishedAt: Date?
        var title: String
        var theme: String?
        var invitation: String
        var perspective: String
        var tags: [String]
        var statusRaw: String
        var ratingRaw: String?
        var note: String?

        init(id: UUID, createdAt: Date, title: String, invitation: String, perspective: String, tags: [String], statusRaw: String) {
            self.id = id
            self.createdAt = createdAt
            self.title = title
            self.invitation = invitation
            self.perspective = perspective
            self.tags = tags
            self.statusRaw = statusRaw
        }
    }
}

/// v2.0: 体験のあとに思い返す問い (reflectionQuestion) を足した。
/// 任意の項目を足しただけなので、軽量移行 (データの書き換えなし) で移れる
enum TaikenSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [ExperienceRecord.self] }

    @Model
    final class ExperienceRecord {
        @Attribute(.unique) var id: UUID
        var createdAt: Date
        var finishedAt: Date?
        var title: String
        var theme: String?
        var invitation: String
        var perspective: String
        var tags: [String]
        var statusRaw: String
        var ratingRaw: String?
        var note: String?
        var reflectionQuestion: String?

        init(id: UUID, createdAt: Date, title: String, invitation: String, perspective: String, tags: [String], statusRaw: String) {
            self.id = id
            self.createdAt = createdAt
            self.title = title
            self.invitation = invitation
            self.perspective = perspective
            self.tags = tags
            self.statusRaw = statusRaw
        }
    }
}

/// v3.0: 体験の樹の上の位置 (nodeID) と要素 (elementsText: "taste,word") を足した。
/// 任意の項目を足しただけなので、軽量移行で移れる。古い記録は名前と文から樹の上の位置を推し量る
enum TaikenSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] { [ExperienceRecord.self] }

    @Model
    final class ExperienceRecord {
        @Attribute(.unique) var id: UUID
        var createdAt: Date
        var finishedAt: Date?
        var title: String
        var theme: String?
        var invitation: String
        var perspective: String
        var tags: [String]
        var statusRaw: String
        var ratingRaw: String?
        var note: String?
        var reflectionQuestion: String?
        var nodeID: String?
        /// 要素の id をカンマでつないだもの (先頭が主な要素)
        var elementsText: String?

        init(_ entry: HistoryEntry) {
            id = entry.id
            createdAt = entry.createdAt
            finishedAt = entry.finishedAt
            title = entry.title
            theme = entry.theme
            invitation = entry.invitation
            perspective = entry.perspective
            tags = entry.tags
            statusRaw = entry.status.rawValue
            ratingRaw = entry.rating?.rawValue
            note = entry.note
            reflectionQuestion = entry.reflectionQuestion
            nodeID = entry.nodeID
            elementsText = entry.elements.isEmpty ? nil : entry.elements.joined(separator: ",")
        }

        /// 変更できる項目だけを反映する
        func apply(_ entry: HistoryEntry) {
            finishedAt = entry.finishedAt
            statusRaw = entry.status.rawValue
            ratingRaw = entry.rating?.rawValue
            note = entry.note
        }

        var entry: HistoryEntry {
            HistoryEntry(
                id: id,
                createdAt: createdAt,
                finishedAt: finishedAt,
                title: title,
                theme: theme,
                invitation: invitation,
                perspective: perspective,
                tags: tags,
                status: HistoryEntry.Status(rawValue: statusRaw) ?? .completed,
                rating: ratingRaw.flatMap(Rating.init(rawValue:)),
                note: note,
                reflectionQuestion: reflectionQuestion,
                nodeID: nodeID,
                elements: elementsText.map { $0.split(separator: ",").map(String.init) } ?? []
            )
        }
    }
}

typealias ExperienceRecord = TaikenSchemaV3.ExperienceRecord

enum TaikenMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [TaikenSchemaV1.self, TaikenSchemaV2.self, TaikenSchemaV3.self] }
    static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: TaikenSchemaV1.self, toVersion: TaikenSchemaV2.self),
            .lightweight(fromVersion: TaikenSchemaV2.self, toVersion: TaikenSchemaV3.self),
        ]
    }
}

enum PersistenceFactory {
    /// 体験帳の保存先。
    /// - アプリ自身の領域に置く (App Group には置かない: ウィジェットに体験帳全体を見せる必要はない)
    /// - iCloud に同期しない
    /// - 保存領域が壊れていてもアプリは起動させる (その場合、体験帳はこの起動中だけ保持)
    static func makeContainer(inMemory: Bool, storeURL: URL? = nil, onFailure: (Error) -> Void = { _ in }) -> ModelContainer {
        let schema = Schema(versionedSchema: TaikenSchemaV3.self)
        let configuration: ModelConfiguration
        if let storeURL {
            configuration = ModelConfiguration(schema: schema, url: storeURL, cloudKitDatabase: .none)
        } else {
            configuration = ModelConfiguration(
                schema: schema, isStoredInMemoryOnly: inMemory, groupContainer: .none, cloudKitDatabase: .none
            )
        }
        do {
            return try ModelContainer(for: schema, migrationPlan: TaikenMigrationPlan.self, configurations: configuration)
        } catch {
            onFailure(error)
            do {
                return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
            } catch {
                fatalError("ModelContainer を作成できません: \(error)")
            }
        }
    }
}
