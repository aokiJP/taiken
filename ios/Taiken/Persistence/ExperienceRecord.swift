import Foundation
import SwiftData
import TaikenCore

// 体験履歴の保存形式。将来モデルを変えるときは TaikenSchemaV2 を追加し、
// TaikenMigrationPlan に移行手順を足す (既存ユーザーの履歴を壊さないため)。

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
                note: note
            )
        }
    }
}

typealias ExperienceRecord = TaikenSchemaV1.ExperienceRecord

enum TaikenMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [TaikenSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

enum PersistenceFactory {
    /// 保存領域が壊れていてもアプリは起動させる (その場合、履歴はこの起動中だけ保持)
    static func makeContainer(inMemory: Bool, onFailure: (Error) -> Void = { _ in }) -> ModelContainer {
        let schema = Schema(versionedSchema: TaikenSchemaV1.self)
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: TaikenMigrationPlan.self,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
            )
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
