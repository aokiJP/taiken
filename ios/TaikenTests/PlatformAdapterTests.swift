import Security
import SwiftData
import XCTest
import TaikenCore
@testable import Taiken

/// iOS の機能を使う実装 (SwiftData・Keychain) のテスト。シミュレータで実行する。
/// UIに依存しないロジックは TaikenCore のテスト (swift test) で検証している。
@MainActor
final class SwiftDataHistoryRepositoryTests: XCTestCase {
    private func makeRepository() -> SwiftDataHistoryRepository {
        SwiftDataHistoryRepository(container: PersistenceFactory.makeContainer(inMemory: true))
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
        XCTAssertNil(home.proposal, "きっかけは、求められたときだけ")
        await home.requestPrompt()
        home.tryIt()
        XCTAssertNotNil(home.activeEntry)
        home.finish(rating: .positive)
        XCTAssertEqual(repo.entries(since: nil, limit: nil).first?.rating, .positive)

        // 自分で見つけた体験を記す (誘いかけの無い記録も、SwiftData にそのまま残る)
        home.dismissCompleted()
        home.record(LivedDraft(text: "帰り道、パン屋の前で足が止まった", elements: ["smell", "move"]))
        let lived = repo.entries(since: nil, limit: nil).first
        XCTAssertEqual(lived?.title, "帰り道、パン屋の前で足が止まった")
        XCTAssertEqual(lived?.isSelfRecorded, true)
        XCTAssertEqual(lived?.status, .completed)
        XCTAssertEqual(lived?.elements, ["smell", "move"])
    }
}

final class KeychainConnectionStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private let service = "com.example.taiken.tests.\(UUID().uuidString)"

    override func setUpWithError() throws {
        defaults = UserDefaults(suiteName: "KeychainConnectionStoreTests-\(UUID().uuidString)")
        // 署名なしでビルドしたテスト (CI のシミュレータ) ではキーチェーンの権限が無い。その場合は確かめられないので飛ばす
        let probe: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "probe",
            kSecValueData as String: Data("probe".utf8),
        ]
        let status = SecItemAdd(probe as CFDictionary, nil)
        SecItemDelete(probe as CFDictionary)
        if status == errSecMissingEntitlement {
            throw XCTSkip("キーチェーンを使う権限が無い (署名なしのテスト)")
        }
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
        XCTAssertEqual(deps.engineState.engine, .library)
        await deps.home.refresh()
        XCTAssertNil(deps.home.proposal, "きっかけは、求められたときだけ")
        await deps.home.requestPrompt()
        XCTAssertEqual(deps.home.proposal?.source, .local)
        XCTAssertNotNil(deps.home.proposalLineage, "きっかけには、樹の上の位置が添えられる")
        deps.deleteAllLocalData()
        XCTAssertNil(deps.home.proposal)
        XCTAssertTrue(deps.history.isEmpty)
        XCTAssertTrue(deps.trees.garden.isEmpty, "身についた技・編んだ技・結びも消える")
        XCTAssertTrue(deps.tree.tree.learnedNodes.isEmpty)
        XCTAssertEqual(deps.tree.tree.totalRank, 0)
    }

    func testSeededTreeHasLearnedSkillsWovenSkillAndTie() throws {
        let deps = AppDependencies.preview()
        let tree = deps.tree.tree
        let woven = try XCTUnwrap(tree.nodes.first { $0.kind == .woven })
        XCTAssertEqual(woven.title, "湯気のゆくえ")
        XCTAssertEqual(woven.after, ["see-tomeru"])
        XCTAssertEqual(tree.state(of: woven.id), .learned)
        XCTAssertEqual(deps.tree.tied(to: "see-tomeru").map(\.node.id), ["taste-hitokuchi"])
        XCTAssertTrue(tree.learnedNodes.contains { $0.id == "flash-hibiki" }, "糸を結ぶと、響き合いが閃く")
        XCTAssertFalse(tree.sproutingElements.isEmpty, "見本では、芽を残しておく")
        XCTAssertFalse(deps.history.vaultFiles().isEmpty)

        // 技の稽古から体験を始めると、ホームの「体験中」になり、ホームへ戻る
        deps.router.openTree(focus: "see-tomeru")
        XCTAssertEqual(deps.router.path.count, 1)
        let node = try XCTUnwrap(deps.tree.node("see-tomeru"))
        let practice = try XCTUnwrap(deps.tree.practices(of: node.id).first)
        deps.tree.start(practice: practice, for: node)
        XCTAssertEqual(deps.home.activeEntry?.nodeID, practice.id)
        XCTAssertTrue(deps.router.path.isEmpty)
    }

    func testMarkdownVaultArchive() throws {
        let deps = AppDependencies.preview()
        let url = try VaultArchive.make(files: deps.history.vaultFiles())
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let data = try Data(contentsOf: url)
        XCTAssertGreaterThan(data.count, 1000)
        XCTAssertEqual(Array(data.prefix(2)), [0x50, 0x4B], "zip のはじまり (PK)")
    }

    func testDeepLinksRouteOnlyAfterOnboarding() {
        let deps = AppDependencies.preview()
        deps.defaults.defaults.set(false, forKey: OnboardingKey.completed)
        deps.open(DeepLink.journal.url)
        XCTAssertTrue(deps.router.path.isEmpty)

        deps.defaults.defaults.set(true, forKey: OnboardingKey.completed)
        deps.open(DeepLink.journal.url)
        XCTAssertEqual(deps.router.path.count, 1)
        deps.open(DeepLink.tree.url)
        XCTAssertEqual(deps.router.path.count, 1, "技の樹は、ホームの上に開く")
        deps.open(DeepLink.talk.url)
        XCTAssertTrue(deps.router.path.isEmpty)
        XCTAssertEqual(deps.router.sheet, .chat)
        deps.open(DeepLink.today.url)
        XCTAssertNil(deps.router.sheet)
        // 「体験を記す」は、ホームに戻ってから開く
        deps.router.openJournal()
        deps.open(DeepLink.record.url)
        XCTAssertTrue(deps.router.path.isEmpty)
        XCTAssertTrue(deps.router.recordRequested)
        // 知らない URL は無視する
        deps.open(URL(string: "https://example.com/journal")!)
        XCTAssertNil(deps.router.sheet)
    }

    func testDeepLinkRoundTrip() {
        for link in [DeepLink.today, .journal, .tree, .talk, .record] {
            XCTAssertEqual(DeepLink(url: link.url), link)
        }
        XCTAssertNil(DeepLink(url: URL(string: "taiken://unknown")!))
    }
}

/// 古い体験帳 (v1: 問いの無い体験帳・v2: 樹の位置の無い体験帳) から v3 への移行で、記録が失われないこと (4.0 も v3 のまま)
@MainActor
final class SchemaMigrationTests: XCTestCase {
    func testV1StoreOpensWithV3WithoutLosingEntries() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("taiken.store")
        let id = UUID()

        do {
            let schema = Schema(versionedSchema: TaikenSchemaV1.self)
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
            let record = TaikenSchemaV1.ExperienceRecord(
                id: id, createdAt: Date(timeIntervalSince1970: 1_790_000_000), title: "ひと口目の味",
                invitation: "最初のひと口だけ、味に集中してみませんか？", perspective: "食事ではなく、味の観察として",
                tags: ["sensory"], statusRaw: "completed"
            )
            record.ratingRaw = "positive"
            record.note = "思ったより甘かった"
            container.mainContext.insert(record)
            try container.mainContext.save()
        }

        var failure: Error?
        let container = PersistenceFactory.makeContainer(inMemory: false, storeURL: url) { failure = $0 }
        XCTAssertNil(failure)
        let repo = SwiftDataHistoryRepository(container: container)
        let entry = try XCTUnwrap(repo.entry(id: id))
        XCTAssertEqual(entry.title, "ひと口目の味")
        XCTAssertEqual(entry.rating, .positive)
        XCTAssertEqual(entry.note, "思ったより甘かった")
        XCTAssertNil(entry.reflectionQuestion)

        // 問いも保存できる
        let next = HistoryEntry(
            createdAt: Date(), title: "いちばん遠くを見る", theme: nil, invitation: "i", perspective: "p",
            tags: ["observation"], status: .active, reflectionQuestion: "いちばん遠くに、何が見えましたか？"
        )
        try repo.add(next)
        XCTAssertEqual(repo.entry(id: next.id)?.reflectionQuestion, "いちばん遠くに、何が見えましたか？")
    }

    func testV2StoreOpensWithV3AndFindsItsPlaceOnTheTree() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("migration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("taiken.store")
        let id = UUID()
        let library = try XCTUnwrap(TaikenContent.shared.experience("meal-first-bite"))

        do {
            let schema = Schema(versionedSchema: TaikenSchemaV2.self)
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
            let record = TaikenSchemaV2.ExperienceRecord(
                id: id, createdAt: Date(timeIntervalSince1970: 1_790_000_000), title: library.title,
                invitation: library.invitation, perspective: library.perspective, tags: library.tags, statusRaw: "completed"
            )
            record.ratingRaw = "positive"
            record.reflectionQuestion = library.reflectionQuestion
            container.mainContext.insert(record)
            try container.mainContext.save()
        }

        var failure: Error?
        let container = PersistenceFactory.makeContainer(inMemory: false, storeURL: url) { failure = $0 }
        XCTAssertNil(failure)
        let repo = SwiftDataHistoryRepository(container: container)
        let entry = try XCTUnwrap(repo.entry(id: id))
        XCTAssertEqual(entry.title, library.title)
        XCTAssertEqual(entry.reflectionQuestion, library.reflectionQuestion)
        XCTAssertNil(entry.nodeID, "古い記録には樹の位置が無い")

        // 名前から、ライブラリの体験の要素が見つかり、その要素の経験になる
        XCTAssertEqual(entry.resolvedElements(), library.elements)
        let tree = TreeBuilder.build(garden: .empty, entries: repo.entries(since: nil, limit: nil))
        for element in library.elements {
            XCTAssertEqual(tree.progress(of: element).experience, 1)
            XCTAssertEqual(tree.progress(of: element).rank, 1, "一つで一段")
        }

        // v3 では樹の位置と要素も保存できる
        let next = HistoryEntry(
            createdAt: Date(), title: "湯気のゆくえ", theme: nil, invitation: "i", perspective: "p", tags: ["observation"],
            status: .active, nodeID: "w-abc", elements: ["see", "pause"]
        )
        try repo.add(next)
        XCTAssertEqual(repo.entry(id: next.id)?.nodeID, "w-abc")
        XCTAssertEqual(repo.entry(id: next.id)?.elements, ["see", "pause"])
    }
}
