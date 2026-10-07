import SwiftData
import XCTest
import TaikenCore
@testable import Taiken

/// iOS の機能を使う実装 (SwiftData・Keychain) のテスト。シミュレータで実行する。
/// UIに依存しないロジックは TaikenCore のテスト (swift test) で検証している。
@MainActor
final class SwiftDataHistoryRepositoryTests: XCTestCase {
    private func makeRepository() -> SwiftDataHistoryRepository {
        SwiftDataHistoryRepository(context: PersistenceFactory.makeContainer(inMemory: true).mainContext)
    }

    private func entry(_ title: String, at date: Date, status: HistoryEntry.Status = .active) -> HistoryEntry {
        HistoryEntry(createdAt: date, title: title, theme: nil, invitation: "i", perspective: "p", tags: ["short"], status: status)
    }

    func testAddFetchUpdateDelete() throws {
        let repo = makeRepository()
        let now = Date()
        let old = entry("old", at: now.addingTimeInterval(-86_400), status: .completed)
        let new = entry("new", at: now)
        try repo.add(old)
        try repo.add(new)

        XCTAssertEqual(repo.entries(since: nil, limit: nil).map(\.title), ["new", "old"])
        XCTAssertEqual(repo.entries(since: now.addingTimeInterval(-60), limit: nil).map(\.title), ["new"])
        XCTAssertEqual(repo.entries(since: nil, limit: 1).count, 1)
        XCTAssertEqual(repo.activeEntry()?.title, "new")

        try repo.finish(id: new.id, rating: .positive, note: "メモ", at: now)
        let finished = try XCTUnwrap(repo.entry(id: new.id))
        XCTAssertEqual(finished.status, .completed)
        XCTAssertEqual(finished.rating, .positive)
        XCTAssertEqual(finished.note, "メモ")
        XCTAssertNil(repo.activeEntry())

        try repo.delete(id: old.id)
        XCTAssertEqual(repo.entries(since: nil, limit: nil).count, 1)
        try repo.deleteAll()
        XCTAssertTrue(repo.entries(since: nil, limit: nil).isEmpty)
    }

    func testHomeViewModelWorksWithSwiftData() async {
        let repo = makeRepository()
        let assembler = ContextAssembler(
            calendarProvider: FixedCalendarProvider.sample(),
            locationProvider: FixedLocationProvider(),
            history: repo,
            memory: ConversationMemory(),
            consent: { ConsentSnapshot() }
        )
        let home = HomeViewModel(service: LocalExperienceService(), assembler: assembler, history: repo, cache: InMemoryProposalCache())
        await home.refresh()
        home.tryIt()
        XCTAssertNotNil(home.activeEntry)
        home.finish(rating: .positive)
        XCTAssertEqual(repo.entries(since: nil, limit: nil).first?.rating, .positive)
    }
}

final class KeychainConnectionStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let service = "com.example.taiken.tests.\(UUID().uuidString)"

    override func setUp() {
        defaults = UserDefaults(suiteName: "KeychainConnectionStoreTests-\(UUID().uuidString)")
    }

    func testSavesTokenInKeychainAndURLInDefaults() throws {
        let store = KeychainConnectionStore(defaults: defaults, service: service, developmentDefault: nil)
        XCTAssertNil(store.load())

        let endpoint = BackendEndpoint(baseURL: URL(string: "https://taiken.example")!, token: "secret")
        try store.save(endpoint)
        XCTAssertEqual(store.load(), endpoint)
        // トークンは UserDefaults に平文で残らない
        XCTAssertFalse(defaults.dictionaryRepresentation().values.contains { ($0 as? String) == "secret" })

        try store.save(BackendEndpoint(baseURL: endpoint.baseURL, token: "rotated"))
        XCTAssertEqual(store.load()?.token, "rotated")

        try store.clear()
        XCTAssertNil(store.load())
    }

    func testDevelopmentDefaultIsUsedUntilDisconnected() throws {
        let dev = URL(string: "http://localhost:8787")!
        let store = KeychainConnectionStore(defaults: defaults, service: service, developmentDefault: dev)
        XCTAssertEqual(store.load()?.baseURL, dev)
        try store.clear()
        XCTAssertNil(store.load())
    }
}

@MainActor
final class AppDependenciesTests: XCTestCase {
    func testPreviewGraphStartsInLocalMode() async {
        let deps = AppDependencies.preview()
        XCTAssertTrue(deps.isLocalMode)
        await deps.home.refresh()
        XCTAssertEqual(deps.home.proposal?.source, .local)
        deps.deleteAllLocalData()
        XCTAssertNil(deps.home.proposal)
    }
}
