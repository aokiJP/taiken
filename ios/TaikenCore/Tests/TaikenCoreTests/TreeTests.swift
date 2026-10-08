import Foundation
import XCTest
@testable import TaikenCore

/// 体験の樹: 組み立て・芽・配置・自分の樹 (編む・結ぶ)・書き出し
final class TreeBuilderTests: XCTestCase {
    private let content = TaikenContent.shared

    func testEmptyTreeStartsFromTheRoots() {
        let tree = TreeBuilder.build(garden: .empty, entries: [])
        XCTAssertEqual(tree.nodes.count, content.experiences.count)
        XCTAssertEqual(tree.buds, content.elements.map(\.root), "何も灯っていなければ、10の根が芽")
        XCTAssertTrue(tree.lives.isEmpty)
        XCTAssertNil(tree.activeNode)
        for element in content.elements {
            XCTAssertEqual(tree.node(element.root)?.kind, .root)
            XCTAssertEqual(tree.depths[element.root], 0)
            XCTAssertEqual(tree.state(of: element.root), .bud)
        }
        // どの体験も、要素の根からの道すじを持つ
        for node in tree.nodes {
            let path = tree.path(to: node.id)
            XCTAssertEqual(path.last?.id, node.id)
            XCTAssertEqual(path.first?.kind, .root, node.id)
            XCTAssertEqual(path.first?.primaryElement, node.primaryElement, node.id)
        }
        XCTAssertEqual(tree.state(of: "meal-texture"), .quiet)
    }

    func testLivingAnExperienceOpensItsBuds() {
        let tree = TreeBuilder.build(garden: .empty, entries: [livedEntry("meal-first-bite")])
        XCTAssertEqual(tree.state(of: "meal-first-bite"), .lit)
        XCTAssertEqual(tree.buds, ["meal-texture", "taste-last-bite", "taste-water", "meal-screen-down"])
        XCTAssertEqual(tree.budParents["meal-texture"], "meal-first-bite")
        XCTAssertEqual(tree.state(of: "meal-texture"), .bud)
        XCTAssertEqual(tree.opened(by: "meal-first-bite").map(\.id), ["meal-texture", "taste-last-bite", "taste-water"])
        XCTAssertEqual(tree.lives["meal-first-bite"]?.litCount, 1)
        XCTAssertEqual(tree.litNodes.map(\.id), ["meal-first-bite"])
    }

    func testRecentLivesComeFirstAndRepeatsStack() {
        let entries = [
            livedEntry("meal-first-bite", daysAgo: 5),
            livedEntry("root-hear", daysAgo: 1),
            livedEntry("meal-first-bite", daysAgo: 3, note: "二度目"),
        ]
        let tree = TreeBuilder.build(garden: .empty, entries: entries)
        XCTAssertEqual(tree.litNodes.map(\.id), ["root-hear", "meal-first-bite"])
        XCTAssertEqual(tree.lives["meal-first-bite"]?.litCount, 2, "重ねた印")
        XCTAssertEqual(tree.buds.first, "commute-sounds", "最近灯った体験の芽が先")
        let context = tree.context()
        XCTAssertEqual(context.lived.map(\.id), ["root-hear", "meal-first-bite"])
        XCTAssertEqual(context.lived.first?.elements, ["hear"])
    }

    func testFewBudsInviteUntouchedRoots() {
        // 葉の体験 (先につながりの無い体験) だけが灯っていると、芽が少ないので、まだ触れていない要素の根を足す
        let tree = TreeBuilder.build(garden: .empty, entries: [livedEntry("study-yesterday")])
        XCTAssertTrue(tree.buds.contains("root-see"))
        XCTAssertFalse(tree.buds.contains("root-think"), "触れた要素の根は足さない")
    }

    func testActiveExperienceIsNotABud() {
        let tree = TreeBuilder.build(garden: .empty, entries: [livedEntry("meal-first-bite", daysAgo: 2), livedEntry("meal-texture", daysAgo: 0, status: .active)])
        XCTAssertEqual(tree.state(of: "meal-texture"), .active)
        XCTAssertFalse(tree.buds.contains("meal-texture"))
        XCTAssertEqual(tree.activeNode?.id, "meal-texture")
    }

    func testOldRecordsFindTheirPlace() {
        // 3.0 より前の記録: node_id も要素も無い
        let library = HistoryEntry(createdAt: referenceDate, title: "いちばん小さな音", theme: nil, invitation: "i", perspective: "p", tags: ["sensory"], status: .completed, rating: .positive)
        let found = HistoryEntry(createdAt: referenceDate, title: "渡っていくもの", theme: nil, invitation: "移動の途中で一度だけ空を見上げて、渡っていくものを探してみませんか？", perspective: "p", tags: ["observation"], status: .completed, rating: .positive)
        let declined = HistoryEntry(createdAt: referenceDate, title: "断った体験", theme: nil, invitation: "i", perspective: "p", tags: [], status: .declined)
        let tree = TreeBuilder.build(garden: .empty, entries: [library, found, declined])
        XCTAssertEqual(tree.nodeID(of: library), "night-quiet-sound")
        let foundID = try? XCTUnwrap(tree.nodeID(of: found))
        XCTAssertTrue(foundID?.hasPrefix("h-") == true)
        let node = tree.node(foundID ?? "")
        XCTAssertEqual(node?.kind, .found)
        XCTAssertEqual(node?.primaryElement, "see", "空を見上げる → 見る")
        XCTAssertEqual(tree.parents[foundID ?? ""], "root-see", "要素の根から伸びる")
        XCTAssertNil(tree.nodeID(of: declined), "断った体験は樹に載らない")
        XCTAssertEqual(tree.state(of: foundID ?? ""), .lit)
    }

    func testGardenNodesAndTies() {
        let woven = PersonalNode(id: "w-aaaa", kind: .woven, title: "湯気の形", invitation: "湯気の形を見てみませんか？", elements: ["see", "taste"], growsFrom: "rest-warm-cup", createdAt: referenceDate)
        let garden = Garden(nodes: [woven], ties: [Tie(between: "meal-first-bite", and: "root-hear", note: "どちらも、最初の一回", createdAt: referenceDate)])
        let tree = TreeBuilder.build(garden: garden, entries: [livedEntry("meal-first-bite"), livedEntry("root-hear")])
        XCTAssertEqual(tree.node("w-aaaa")?.kind, .woven)
        XCTAssertTrue(tree.incoming(to: "w-aaaa").contains { $0.from == "rest-warm-cup" && $0.kind == .grow })
        XCTAssertEqual(tree.parents["w-aaaa"], "root-see", "主な要素 (見る) の中では、根につながる")
        let ties = tree.ties(of: "root-hear")
        XCTAssertEqual(ties.count, 1)
        XCTAssertEqual(ties.first?.note, "どちらも、最初の一回")
        XCTAssertTrue(tree.outgoing(from: "meal-first-bite").allSatisfy { $0.kind != .tie }, "結びは「ひらく」には数えない")
    }

    func testTieIsUndirectedAndTrimmed() {
        let tie = Tie(between: "b", and: "a", note: "  " + String(repeating: "あ", count: 60), createdAt: referenceDate)
        XCTAssertEqual(tie.a, "a")
        XCTAssertEqual(tie.b, "b")
        XCTAssertTrue(tie.connects("b", "a"))
        XCTAssertEqual(tie.other(than: "a"), "b")
        XCTAssertEqual(tie.note?.count, 40)
        XCTAssertNil(Tie(between: "a", and: "b", note: "   ", createdAt: referenceDate).note)
    }
}

final class TreeLayoutTests: XCTestCase {
    func testLayoutIsDeterministicAndRadial() {
        let tree = TreeBuilder.build(garden: .empty, entries: [livedEntry("meal-first-bite")])
        let first = TreeLayout.make(tree: tree)
        let second = TreeLayout.make(tree: TreeBuilder.build(garden: .empty, entries: [livedEntry("meal-first-bite")]))
        XCTAssertEqual(first, second, "同じ樹は、いつも同じ配置")
        XCTAssertEqual(first.positions.count, tree.nodes.count)
        XCTAssertEqual(first.sectors.map(\.element), TaikenContent.shared.elements.map(\.id))

        // 扇は一周をすき間なく分ける
        let total = first.sectors.reduce(0) { $0 + ($1.end - $1.start) }
        XCTAssertEqual(total, 2 * Double.pi, accuracy: 1e-9)
        // 最初の要素 (見る) は真上
        XCTAssertEqual(first.sectors[0].center, -Double.pi / 2, accuracy: 1e-9)

        let center = TreeLayout.Point(x: 0, y: 0)
        for node in tree.nodes {
            let point = try? XCTUnwrap(first.position(of: node.id))
            let r = point?.distance(to: center) ?? 0
            XCTAssertFalse(r.isNaN)
            let depth = Double(tree.depths[node.id] ?? 0)
            XCTAssertEqual(r, TreeLayout.rootRadius + depth * TreeLayout.ringStep, accuracy: 0.03, node.id)
        }
        XCTAssertGreaterThan(first.radius, TreeLayout.rootRadius)
    }

    func testNodesOnTheSameRingDoNotOverlap() {
        let layout = TreeLayout.make(tree: TreeBuilder.build(garden: .empty, entries: []))
        let points = Array(layout.positions.values)
        var closest = Double.infinity
        for i in 0..<points.count {
            for j in (i + 1)..<points.count {
                closest = min(closest, points[i].distance(to: points[j]))
            }
        }
        XCTAssertGreaterThan(closest, 0.04, "体験どうしが重ならない")
    }

    func testSignatureChangesOnlyWithShape() {
        let a = TreeBuilder.build(garden: .empty, entries: [])
        let b = TreeBuilder.build(garden: .empty, entries: [livedEntry("meal-first-bite")])
        XCTAssertEqual(TreeLayout.signature(of: a), TreeLayout.signature(of: b), "灯っただけでは配置は変わらない")
        let woven = PersonalNode(id: "w-bbbb", kind: .woven, title: "新しい体験", invitation: "してみませんか？", elements: ["word"], createdAt: referenceDate)
        let c = TreeBuilder.build(garden: Garden(nodes: [woven]), entries: [])
        XCTAssertNotEqual(TreeLayout.signature(of: a), TreeLayout.signature(of: c))
    }
}

final class ElementClassifierTests: XCTestCase {
    private let classifier = ElementClassifier()

    func testReadsElementsFromWords() {
        XCTAssertEqual(classifier.classify(title: "雨の匂い", invitation: "外に出たら、雨の匂いを確かめてみませんか？", perspective: "", tags: []).first, "smell")
        XCTAssertEqual(classifier.classify(title: "最後まで聞く", invitation: "相手の話を最後まで聞いてみませんか？", perspective: "", tags: []).first, "hear")
        XCTAssertEqual(classifier.classify(title: "一行日記", invitation: "今日のことを一行だけ書いてみませんか？", perspective: "", tags: []).first, "word")
        let both = classifier.classify(title: "歩きながら空を見る", invitation: "歩く途中で、空の色を見てみませんか？", perspective: "", tags: [])
        XCTAssertEqual(Set(both.prefix(2)), ["see", "move"])
    }

    func testFallsBackToTagsAndThenSeeing() {
        XCTAssertEqual(classifier.classify(title: "x", invitation: "y", perspective: "", tags: ["social"]), ["people"])
        XCTAssertEqual(classifier.classify(title: "x", invitation: "y", perspective: "", tags: []), ["see"])
    }

    func testExperienceElementsPreferWhatIsGiven() {
        let given = Experience(title: "x", perspective: "p", invitation: "i", reason: "", difficulty: .low, tags: [], elements: ["taste", "bogus", "taste"])
        XCTAssertEqual(ElementClassifier.elements(of: given), ["taste"])
        let library = Experience(title: "三つの音", perspective: "p", invitation: "i", reason: "", difficulty: .low, tags: [])
        XCTAssertEqual(ElementClassifier.elements(of: library), ["hear", "move"])
        XCTAssertEqual(ElementClassifier.glyph(for: ["hear", "move"]), "聴")
    }
}

final class GardenStoreTests: XCTestCase {
    func testFileStoreRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("garden-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileGardenStore(url: directory.appendingPathComponent("garden.json"))
        XCTAssertEqual(store.load(), .empty, "まだ無ければ空")
        let garden = Garden(
            nodes: [PersonalNode(id: "w-cccc", kind: .woven, title: "影を踏む", invitation: "影を踏んでみませんか？", elements: ["move"], createdAt: referenceDate)],
            ties: [Tie(between: "w-cccc", and: "root-move", createdAt: referenceDate)]
        )
        try store.save(garden)
        XCTAssertEqual(FileGardenStore(url: store.url).load(), garden)
        store.delete()
        XCTAssertEqual(store.load(), .empty)
    }

    func testBrokenFileReadsAsEmpty() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("garden-broken-\(UUID().uuidString).json")
        try Data("{".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(FileGardenStore(url: url).load(), .empty)
    }

    func testPersonalIDsLookLikeIDs() {
        let woven = PersonalNode.makeID(kind: .woven)
        XCTAssertTrue(woven.hasPrefix("w-"))
        XCTAssertEqual(woven.count, 14)
        XCTAssertNotNil(Experience.cleanID(woven))
        XCTAssertTrue(PersonalNode.makeID(kind: .found).hasPrefix("f-"))
    }
}

@MainActor
final class TreeSourceTests: XCTestCase {
    private func make(_ entries: [HistoryEntry] = []) -> (TreeSource, InMemoryHistoryRepository, InMemoryGardenStore) {
        let history = InMemoryHistoryRepository(entries)
        let store = InMemoryGardenStore()
        return (TreeSource(history: history, store: store, now: { referenceDate }), history, store)
    }

    func testPlacesLibraryExperiencesWithoutPlantingAnything() async {
        let (source, _, store) = make()
        let picked = Experience(title: "三つの音", perspective: "p", invitation: "i", reason: "", difficulty: .low, tags: [])
        let placed = source.place(picked)
        XCTAssertEqual(placed.nodeID, "commute-sounds")
        XCTAssertEqual(placed.elements, ["hear", "move"])
        XCTAssertTrue(store.load().nodes.isEmpty)
    }

    func testPlantsNewExperiencesAsFound() async {
        let (source, history, store) = make([livedEntry("meal-first-bite")])
        let ai = Experience(
            title: "湯気の向こう", perspective: "湯気を、景色を変えるものとして見る。", invitation: "温かい飲み物の湯気越しに、部屋を眺めてみませんか？",
            reason: "", difficulty: .low, tags: ["observation"], elements: ["see", "taste"], growsFrom: "meal-first-bite"
        )
        let placed = source.place(ai)
        let id = try? XCTUnwrap(placed.nodeID)
        XCTAssertTrue(id?.hasPrefix("f-") == true)
        XCTAssertEqual(store.load().nodes.first?.growsFrom, "meal-first-bite")
        XCTAssertEqual(source.revision, 1)
        // 同じ名前の体験をもう一度やってみても、二つ植えない
        XCTAssertEqual(source.place(ai).nodeID, id)
        XCTAssertEqual(store.load().nodes.count, 1)

        // やめて記録が無ければ片づける
        source.discardFoundIfUnused(id)
        XCTAssertTrue(store.load().nodes.isEmpty)
        _ = history
    }

    func testUnknownParentIsIgnored() async {
        let (source, _, store) = make()
        let ai = Experience(title: "新しい体験", perspective: "p", invitation: "してみませんか？", reason: "", difficulty: .low, tags: [], growsFrom: "nope-nope")
        XCTAssertNil(source.place(ai).growsFrom)
        XCTAssertNil(store.load().nodes.first?.growsFrom)
    }

    func testWeaveValidatesAndPlants() async throws {
        let (source, _, _) = make()
        XCTAssertThrowsError(try source.weave(WeaveDraft(title: "", invitation: "i", elements: ["see"]))) { error in
            XCTAssertEqual(error as? WeaveError, .invalid(.missingTitle))
        }
        XCTAssertThrowsError(try source.weave(WeaveDraft(title: "三つの音", invitation: "i", elements: ["hear"]))) { error in
            XCTAssertEqual(error as? WeaveError, .invalid(.duplicateTitle))
        }
        XCTAssertThrowsError(try source.weave(WeaveDraft(title: "x", invitation: "i", elements: ["bogus"]))) { error in
            XCTAssertEqual(error as? WeaveError, .invalid(.missingElement))
        }
        let node = try source.weave(WeaveDraft(title: " 湯気の形 ", invitation: "湯気の形を見てみませんか？", reflectionQuestion: "どんな形でしたか？", elements: ["see", "taste"], growsFrom: "rest-warm-cup"))
        XCTAssertEqual(node.title, "湯気の形")
        XCTAssertEqual(node.kind, .woven)
        XCTAssertEqual(node.growsFrom, "rest-warm-cup")
        XCTAssertEqual(source.tree().node(node.id)?.kind, .woven)

        try source.revise(node.id, with: WeaveDraft(title: "湯気のかたち", invitation: "湯気を見てみませんか？", elements: ["see"], growsFrom: node.id))
        let revised = source.garden.node(node.id)
        XCTAssertEqual(revised?.title, "湯気のかたち")
        XCTAssertNil(revised?.growsFrom, "自分自身からは伸ばせない")

        try source.remove(node.id)
        XCTAssertNil(source.tree().node(node.id))
    }

    func testTiesBetweenKnownExperiencesOnly() async throws {
        let (source, _, store) = make([livedEntry("meal-first-bite"), livedEntry("root-hear")])
        let tie = try source.tie("meal-first-bite", "root-hear", note: "最初の一回")
        XCTAssertNotNil(tie)
        XCTAssertNil(try source.tie("root-hear", "meal-first-bite"), "同じ糸は二本にしない")
        XCTAssertNil(try source.tie("meal-first-bite", "meal-first-bite"))
        XCTAssertNil(try source.tie("meal-first-bite", "unknown-node"))
        XCTAssertEqual(store.load().ties.count, 1)
        try source.untie(XCTUnwrap(tie).id)
        XCTAssertTrue(store.load().ties.isEmpty)
    }

    func testStorageFailureDoesNotLoseTheExperience() async {
        let (source, _, store) = make()
        store.failWrites = true
        let ai = Experience(title: "新しい体験", perspective: "p", invitation: "してみませんか？", reason: "", difficulty: .low, tags: [])
        let placed = source.place(ai)
        XCTAssertNil(placed.nodeID, "植えられなくても、体験そのものは続けられる")
        XCTAssertFalse(placed.elements.isEmpty)
    }

    func testLineageDescribesWhereAnExperienceGrows() async {
        let (source, _, _) = make([livedEntry("meal-first-bite")])
        let bud = source.lineage(of: TaikenContent.shared.experience("meal-texture").map { libraryExperience($0) }!)
        XCTAssertEqual(bud.sentence, "「ひと口目の観察」から伸びる枝")
        XCTAssertTrue(bud.isBud)
        XCTAssertEqual(bud.elementText, "味わう · 言葉にする")

        let root = source.lineage(of: libraryExperience(TaikenContent.shared.experience("root-see")!))
        XCTAssertEqual(root.sentence, "「見る」の根 — いちばん小さなかたち")

        let new = source.lineage(of: Experience(title: "まだ無い体験", perspective: "p", invitation: "空を見てみませんか？", reason: "", difficulty: .low, tags: []))
        XCTAssertTrue(new.isNew)
        XCTAssertEqual(new.elements.first?.id, "see")
    }

    private func libraryExperience(_ item: TaikenContent.LibraryExperience) -> Experience {
        Experience(title: item.title, perspective: item.perspective, invitation: item.invitation, reason: "", difficulty: .low, tags: item.tags, nodeID: item.id, elements: item.elements)
    }
}

@MainActor
final class TreeFlowTests: XCTestCase {
    func testDoingAProposalGrowsTheTree() async {
        let h = Harness()
        let store = InMemoryGardenStore()
        let trees = TreeSource(history: h.history, store: store, now: { h.clock.now })
        let library = TaikenContent.shared.experience("meal-first-bite")!
        let response = ExperienceResponse(
            situation: Situation(summary: "s", observations: []), detectedActions: [], possibleObligations: [], experienceOpportunities: [],
            isObligation: false, confidence: 0.5,
            experience: Experience(title: library.title, perspective: library.perspective, invitation: library.invitation, reason: "r", difficulty: .low, tags: library.tags, reflectionQuestion: library.reflectionQuestion, nodeID: library.id, elements: library.elements),
            shouldNotify: false, notification: nil, source: .local
        )
        let model = HomeViewModel(service: StubService(experience: [.success(response)]), assembler: h.assembler, history: h.history, cache: h.cache, trees: trees)
        await model.generate()
        XCTAssertEqual(model.proposalLineage?.isRoot, true)
        model.tryIt()
        XCTAssertEqual(model.activeEntry?.nodeID, "meal-first-bite")
        XCTAssertEqual(model.activeLineage?.nodeID, "meal-first-bite")
        model.finish(rating: .positive, note: "甘かった")
        XCTAssertEqual(model.completedGrowth.map(\.id), ["meal-texture", "taste-last-bite", "taste-water"], "記したら、その先に芽が出る")
        XCTAssertEqual(trees.tree().state(of: "meal-first-bite"), .lit)
    }

    func testStartingFromTheTreeReplacesTheProposal() async {
        let h = Harness()
        let trees = TreeSource(history: h.history, store: InMemoryGardenStore(), now: { h.clock.now })
        let model = HomeViewModel(service: StubService(), assembler: h.assembler, history: h.history, cache: h.cache, trees: trees)
        await model.generate()
        XCTAssertEqual(model.stage, .proposal)
        let node = trees.tree().node("root-touch")!
        model.begin(node)
        XCTAssertEqual(model.stage, .active)
        XCTAssertEqual(model.activeEntry?.title, "手ざわり")
        XCTAssertEqual(model.activeEntry?.nodeID, "root-touch")
        XCTAssertNil(model.proposal)
        XCTAssertNil(h.cache.load(), "置いていた提案は片づける")
        XCTAssertTrue(h.history.storage.allSatisfy { $0.status != .declined }, "樹から選んだことは、提案を断ったことにしない")
    }

    func testAbandoningAFoundExperienceLeavesNoTrace() async {
        let h = Harness()
        let store = InMemoryGardenStore()
        let trees = TreeSource(history: h.history, store: store, now: { h.clock.now })
        let model = HomeViewModel(service: StubService(experience: [.success(sampleResponse(title: "AIの見つけた体験"))]), assembler: h.assembler, history: h.history, cache: h.cache, trees: trees)
        await model.generate()
        model.tryIt()
        XCTAssertEqual(store.load().nodes.count, 1)
        XCTAssertEqual(model.activeLineage?.isNew, false, "やってみた時点で樹に植わる")
        model.abandonActive()
        XCTAssertTrue(store.load().nodes.isEmpty)
    }

    func testRequestCarriesTheTreeOnlyWithHistoryConsent() async throws {
        var h = Harness(entries: [livedEntry("meal-first-bite")])
        let trees = TreeSource(history: h.history, store: InMemoryGardenStore(), now: { referenceDate })
        h.assembler.treeContext = { trees.context() }
        let request = await h.assembler.experienceRequest()
        XCTAssertEqual(request.tree?.lived.map(\.id), ["meal-first-bite"])
        XCTAssertEqual(request.tree?.buds.first, "meal-texture")

        h = Harness(consent: ConsentSnapshot(useHistory: false), entries: [livedEntry("meal-first-bite")])
        h.assembler.treeContext = { trees.context() }
        let withoutHistory = await h.assembler.experienceRequest()
        XCTAssertNil(withoutHistory.tree)
    }

    func testTreeViewModel() async throws {
        let history = InMemoryHistoryRepository([livedEntry("meal-first-bite", daysAgo: 2), livedEntry("root-hear", daysAgo: 1)])
        let trees = TreeSource(history: history, store: InMemoryGardenStore(), now: { referenceDate })
        var started: [String] = []
        var changes = 0
        let model = TreeViewModel(source: trees, onStart: { started.append($0.id) }, onChange: { changes += 1 })
        XCTAssertEqual(model.sections.count, 10)
        XCTAssertEqual(model.sections.first?.nodes.first?.id, "root-see", "要素の一覧は根から")
        XCTAssertEqual(model.summary, "最近灯ったのは「いま聞こえる音」。聴く・味わうの枝に、灯りがあります。")
        model.query = "匂い"
        XCTAssertTrue(model.sections.allSatisfy { section in section.nodes.allSatisfy { $0.title.contains("匂い") || $0.invitation.contains("匂い") } })
        XCTAssertFalse(model.sections.isEmpty)
        model.query = ""

        XCTAssertEqual(model.tieCandidates(for: "root-hear").map(\.id), ["meal-first-bite"])
        model.tie("root-hear", "meal-first-bite", note: nil)
        XCTAssertEqual(changes, 1)
        XCTAssertTrue(model.tieCandidates(for: "root-hear").isEmpty)
        let link = try XCTUnwrap(model.tree.ties(of: "root-hear").first)
        model.untie(link)
        XCTAssertTrue(model.tree.ties(of: "root-hear").isEmpty)

        XCTAssertNil(model.weave(WeaveDraft(title: "", invitation: "", elements: [])))
        XCTAssertEqual(model.errorMessage, "名前をつけてください。")
        let woven = try XCTUnwrap(model.weave(WeaveDraft(title: "湯気の形", invitation: "湯気を見てみませんか？", elements: ["see"], growsFrom: "root-see")))
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.draft(for: woven).title, "湯気の形")
        XCTAssertNotNil(model.layout.position(of: woven.id), "編んだ体験も樹に置かれる")
        XCTAssertTrue(model.revise(woven.id, with: WeaveDraft(title: "湯気の形", invitation: "湯気をよく見てみませんか？", elements: ["see"])))
        model.start(woven)
        XCTAssertEqual(started, [woven.id])
        model.remove(woven.id)
        XCTAssertNil(model.node(woven.id))
        XCTAssertEqual(model.path(to: "meal-texture").map(\.id), ["meal-first-bite", "meal-texture"])
    }

    func testNodePageRelationsAndCaptions() async throws {
        let history = InMemoryHistoryRepository([
            livedEntry("meal-first-bite", daysAgo: 3),
            livedEntry("meal-first-bite", daysAgo: 1),
            livedEntry("root-hear", daysAgo: 0),
            livedEntry("root-see", daysAgo: 40),
        ])
        let trees = TreeSource(history: history, store: InMemoryGardenStore(), now: { referenceDate })
        let model = TreeViewModel(source: trees, onStart: { _ in })
        let now = referenceDate.addingTimeInterval(3600)

        // ひらく先・至る元・結び
        let opens = model.opens(from: "meal-first-bite")
        XCTAssertEqual(opens.first?.node.id, "meal-texture")
        XCTAssertEqual(Set(opens.map(\.node.id)).count, opens.count, "同じ体験は一度だけ")
        XCTAssertTrue(model.leadsHere(to: "meal-texture").contains { $0.node.id == "meal-first-bite" })
        model.tie("meal-first-bite", "root-hear", note: "どちらも最初の一回")
        let tied = model.tied(to: "root-hear")
        XCTAssertEqual(tied.map(\.node.id), ["meal-first-bite"])
        XCTAssertEqual(tied.first?.note, "どちらも最初の一回")
        XCTAssertEqual(tied.first?.kind, .tie)
        XCTAssertEqual(model.depth(of: "meal-first-bite"), 0)
        XCTAssertEqual(model.depth(of: "meal-texture"), 1)

        // 様子の一文 (数は目標にしない。記した事実だけ)
        XCTAssertEqual(model.caption(of: "meal-first-bite", now: now, calendar: tokyoCalendar), "灯った体験 · 2回記した · 最後は昨日")
        XCTAssertEqual(model.caption(of: "root-hear", now: now, calendar: tokyoCalendar), "灯った体験 · 今日記した")
        XCTAssertTrue(model.caption(of: "root-see", now: now, calendar: tokyoCalendar).hasSuffix("日に記した"))
        XCTAssertEqual(model.caption(of: "meal-texture", now: now, calendar: tokyoCalendar), "「ひと口目の観察」の先に出た芽")
        XCTAssertEqual(model.caption(of: "root-move", now: now, calendar: tokyoCalendar), "「動く」の根 · いちばん小さなかたち", "芽が足りていれば、根は静か")
        XCTAssertEqual(model.caption(of: "nope"), "")
        XCTAssertEqual(TreeViewModel.relativeDay(referenceDate.addingTimeInterval(-5 * 86_400), now: referenceDate, calendar: tokyoCalendar), "5日前")

        let woven = try XCTUnwrap(model.weave(WeaveDraft(title: "湯気の形", invitation: "湯気を見てみませんか？", elements: ["see"], growsFrom: "root-see")))
        let rootTitle = try XCTUnwrap(model.node("root-see")).title
        XCTAssertEqual(model.caption(of: woven.id), "あなたが編んだ体験 · 「\(rootTitle)」の先の芽", "灯った体験から伸ばすと芽になる")
        XCTAssertTrue(model.leadsHere(to: woven.id).contains { $0.node.id == "root-see" && $0.kind == .grow })
        let quietWoven = try XCTUnwrap(model.weave(WeaveDraft(title: "足音の数", invitation: "足音を数えてみませんか？", elements: ["move"], growsFrom: "root-move")))
        XCTAssertEqual(model.caption(of: quietWoven.id), "あなたが編んだ体験 · 「\(try XCTUnwrap(model.node("root-move")).title)」から")
        XCTAssertEqual(TreeViewModel.relativeDay(referenceDate.addingTimeInterval(-40 * 86_400), now: referenceDate, calendar: tokyoCalendar).hasSuffix("日"), true)
    }

    func testEmptyTreeSummaryInvitesAnyRoot() async {
        let trees = TreeSource(history: InMemoryHistoryRepository(), store: InMemoryGardenStore())
        let model = TreeViewModel(source: trees, onStart: { _ in })
        XCTAssertEqual(model.summary, "まだ灯った体験はありません。10の根のどこからでも始められます。")
        XCTAssertTrue(model.sections.allSatisfy { !$0.isTouched })
    }
}

final class VaultExportTests: XCTestCase {
    func testWritesPagesThatLinkLikeTheTree() throws {
        let garden = Garden(ties: [Tie(between: "meal-first-bite", and: "root-hear", note: "最初の一回", createdAt: referenceDate)])
        let tree = TreeBuilder.build(garden: garden, entries: [livedEntry("meal-first-bite", note: "甘かった"), livedEntry("root-hear")])
        let files = VaultExporter.files(tree: tree, exportedAt: referenceDate, calendar: tokyoCalendar)
        let byPath = Dictionary(uniqueKeysWithValues: files.map { ($0.path, $0.contents) })

        XCTAssertNotNil(byPath["はじめに.md"])
        XCTAssertEqual(files.filter { $0.path.hasPrefix("要素/") }.count, 10)
        let page = try XCTUnwrap(byPath["体験/ひと口目の観察.md"])
        XCTAssertTrue(page.contains("state: lit"))
        XCTAssertTrue(page.contains("- 深める → [[食感をことばに]]"))
        XCTAssertTrue(page.contains("[[いま聞こえる音]] — 最初の一回"))
        XCTAssertTrue(page.contains("「甘かった」"))
        XCTAssertTrue(page.contains("要素: [[味わう]]"))
        let day = try XCTUnwrap(byPath["体験帳/2026-10-07.md"])
        XCTAssertTrue(day.contains("[[ひと口目の観察]]"))
        XCTAssertEqual(Set(files.map(\.path)).count, files.count, "同じパスは無い")
    }

    func testFileNamesAreSafe() {
        XCTAssertEqual(VaultExporter.fileName("a/b:c?"), "a・b・c・")
        XCTAssertEqual(VaultExporter.fileName("  "), "無題")
        XCTAssertEqual(VaultExporter.fileName("..secret"), "secret")
    }

    func testWritesToAFolder() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("vault-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = VaultExporter.files(tree: TreeBuilder.build(garden: .empty, entries: []), exportedAt: referenceDate, calendar: tokyoCalendar)
        try VaultExporter.write(files, to: directory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("要素/見る.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("体験/目に留まるもの.md").path))
    }
}
