import Foundation
import SwiftData
import TaikenCore

/// HistoryRepository の SwiftData 実装。保存先は端末内のみ。
@MainActor
final class SwiftDataHistoryRepository: HistoryRepository {
    /// ModelContext は container を強く参照しないので、ここで持っておく (先に解放されると使ったときに落ちる)
    private let container: ModelContainer
    private let context: ModelContext

    init(container: ModelContainer) {
        self.container = container
        context = container.mainContext
    }

    func add(_ entry: HistoryEntry) throws {
        context.insert(ExperienceRecord(entry))
        try save()
    }

    func update(_ entry: HistoryEntry) throws {
        guard let record = record(id: entry.id) else { return }
        record.apply(entry)
        try save()
    }

    func entry(id: UUID) -> HistoryEntry? {
        record(id: id)?.entry
    }

    func entries(since: Date?, limit: Int?) -> [HistoryEntry] {
        var descriptor: FetchDescriptor<ExperienceRecord>
        if let since {
            descriptor = FetchDescriptor(
                predicate: #Predicate { $0.createdAt >= since },
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
        } else {
            descriptor = FetchDescriptor(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        }
        if let limit { descriptor.fetchLimit = limit }
        return ((try? context.fetch(descriptor)) ?? []).map(\.entry)
    }

    func delete(id: UUID) throws {
        guard let record = record(id: id) else { return }
        context.delete(record)
        try save()
    }

    func deleteAll() throws {
        try context.delete(model: ExperienceRecord.self)
        try save()
    }

    private func record(id: UUID) -> ExperienceRecord? {
        var descriptor = FetchDescriptor<ExperienceRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    private func save() throws {
        do {
            try context.save()
        } catch {
            // 中途半端な変更を残さない
            context.rollback()
            throw AppError.storage
        }
    }
}
