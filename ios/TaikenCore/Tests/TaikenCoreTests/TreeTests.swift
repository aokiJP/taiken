import Foundation
import XCTest
@testable import TaikenCore

// 技の樹: 経験と段と芽・霧と気配・伸ばす・守破離・閃き・配置・自分の樹 (編む・結ぶ)・書き出し

/// 自分で見つけて記した体験
func selfEntry(_ text: String, _ elements: [String], at date: Date = referenceDate) -> HistoryEntry {
    HistoryEntry.lived(LivedDraft(text: text, elements: elements), at: date)
}

/// 同じ要素に触れた、自分で記した体験をいくつか (一分ずつさかのぼる。同じ日の同じ時間帯)
func selfEntries(_ count: Int, _ elements: [String], from start: Date = referenceDate) -> [HistoryEntry] {
    (0..<count).map { selfEntry("体験\($0)", elements, at: start.addingTimeInterval(-Double($0) * 60)) }
}

func buildTree(_ entries: [HistoryEntry] = [], garden: Garden = .empty) -> ExperienceTree {
    TreeBuilder.build(garden: garden, entries: entries, calendar: tokyoCalendar)
}

func learned(_ ids: [String], element: String? = nil) -> [LearnedSkill] {
    ids.map { id in
        LearnedSkill(id: id, element: element ?? SkillBook.shared.skill(id)?.element, learnedAt: referenceDate.addingTimeInterval(-86_400))
    }
}

final class SkillBookTests: XCTestCase {
    /// アプリに入っている技の樹が contracts/skills.ja.json と同じ
    func testBundledSkillsMatchContract() throws {
        let bundled = try Data(contentsOf: XCTUnwrap(SkillBook.resourceURL))
        XCTAssertEqual(bundled, try Fixtures.data("skills.ja"), "contracts/tools/sync.sh で contracts/skills.ja.json をコピーしてください")
    }

    func testShapeOfTheBook() {
        let book = SkillBook.shared
        XCTAssertEqual(book.skills.count, 93)
        XCTAssertEqual(book.mastery, SkillBook.MasterySteps(ha: 3, ri: 7))
        for element in TaikenContent.shared.elements {
            let own = book.skills.filter { $0.element == element.id }
            XCTAssertEqual(own.filter { $0.kind == .art }.count, 6, element.id)
            XCTAssertEqual(own.filter { $0.kind == .secret }.count, 1, element.id)
        }
        XCTAssertEqual(book.skills.filter { $0.kind == .cross }.count, 14)
        XCTAssertEqual(book.flashes.count, 9)
        XCTAssertTrue(book.flashes.allSatisfy { $0.flash != nil && $0.found != nil && $0.practice.isEmpty })
        // ライブラリのどの体験も、どれかの技の稽古になっている
        for item in TaikenContent.shared.experiences {
            XCTAssertFalse(book.skills(practicing: item.id).isEmpty, item.id)
        }
        XCTAssertEqual(book.skill("cross-mitate")?.elements, ["see", "think"])
        XCTAssertEqual(book.skill("flash-jibun")?.flash?.selfRecorded, 10)
        XCTAssertEqual(book.skill("flash-tone")?.flash?.allElements, 1)
    }

    /// 技は「やること」ではなく、身につく見方や力。稽古 (体験ライブラリの体験) と同じ名前にしない
    func testSkillsAreNamedAsAbilitiesNotAsExperiences() {
        let titles = Set(TaikenContent.shared.experiences.map(\.title))
        for skill in SkillBook.shared.skills {
            XCTAssertFalse(titles.contains(skill.name), "\(skill.id): 「\(skill.name)」は体験ライブラリの体験の名前")
            XCTAssertTrue(skill.ability.hasSuffix("。"), skill.id)
            XCTAssertNil(skill.ability.range(of: "[一二三四五六七八九十]段", options: .regularExpression), "\(skill.id): 段は要素の深さの言葉")
        }
        XCTAssertEqual(TaikenContent.shared.element("people")?.quoted, "「人と」")
    }

    func testEmptyBookKeepsTheAppRunning() {
        let tree = TreeBuilder.build(book: .empty, garden: .empty, entries: [selfEntry("空", ["see"])], calendar: tokyoCalendar)
        XCTAssertEqual(tree.nodes.count, 10, "根だけになる")
        XCTAssertEqual(tree.progress(of: "see").rank, 1)
    }
}

final class RanksTests: XCTestCase {
    func testThresholdsGrowGently() {
        XCTAssertEqual((0...7).map(Ranks.threshold), [0, 1, 3, 6, 10, 15, 21, 28])
        XCTAssertEqual(Ranks.rank(for: 0), 0)
        XCTAssertEqual(Ranks.rank(for: 1), 1)
        XCTAssertEqual(Ranks.rank(for: 2), 1)
        XCTAssertEqual(Ranks.rank(for: 3), 2)
        XCTAssertEqual(Ranks.rank(for: 20), 5)
        XCTAssertEqual(Ranks.rank(for: 21), 6)
    }

    func testKanji() {
        XCTAssertEqual(Ranks.kanji(1), "一")
        XCTAssertEqual(Ranks.kanji(10), "十")
        XCTAssertEqual(Ranks.kanji(11), "十一")
        XCTAssertEqual(Ranks.kanji(23), "二十三")
        XCTAssertEqual(Ranks.label(3), "三段")
        XCTAssertEqual(Ranks.label(0), "まだ")
    }

    func testProgressWithinARank() {
        let progress = ElementProgress(element: "see", experience: 4, rank: 2, sprouts: 1)
        XCTAssertEqual(progress.gained, 1)
        XCTAssertEqual(progress.span, 3)
        XCTAssertEqual(progress.remaining, 2)
    }

    func testMasterySteps() {
        let steps = SkillBook.MasterySteps(ha: 3, ri: 7)
        XCTAssertEqual(Mastery.of(uses: 0, steps: steps), .shu)
        XCTAssertEqual(Mastery.of(uses: 3, steps: steps), .ha)
        XCTAssertEqual(Mastery.of(uses: 7, steps: steps), .ri)
        XCTAssertEqual(Mastery.ri.glyph, "離")
    }
}

final class TreeBuilderTests: XCTestCase {
    func testEmptyTreeShowsTheRootsAndOnlyTheFirstArts() {
        let tree = buildTree()
        XCTAssertEqual(tree.nodes.count, 10 + 84, "根と、閃きを除く技")
        XCTAssertEqual(tree.hiddenFlashes, 9)
        XCTAssertEqual(tree.totalRank, 0)
        XCTAssertTrue(tree.learnedNodes.isEmpty)
        for element in TaikenContent.shared.elements {
            let root = tree.root(of: element.id)
            XCTAssertEqual(root?.kind, .root)
            XCTAssertEqual(root?.title, element.label)
            XCTAssertEqual(tree.depths[ExperienceTree.rootID(element.id)], 0)
            XCTAssertEqual(tree.state(of: ExperienceTree.rootID(element.id)), .ready, "根からなら、どこからでも始められる")
        }
        // 名前が見えるのは一の技だけ。その先は霧
        XCTAssertEqual(tree.state(of: "see-tomeru"), .sensed)
        XCTAssertEqual(tree.state(of: "see-toome"), .unknown)
        XCTAssertEqual(tree.state(of: "see-manazashi"), .unknown)
        XCTAssertEqual(tree.state(of: "cross-mitate"), .unknown)
        XCTAssertEqual(tree.nodes.filter { tree.state(of: $0.id) == .sensed }.count, 30)
        // どの技も、主な要素の根からの道すじを持つ
        for node in tree.nodes {
            let path = tree.path(to: node.id)
            XCTAssertEqual(path.last?.id, node.id)
            XCTAssertEqual(path.first?.kind, .root, node.id)
            XCTAssertEqual(path.first?.primaryElement, node.primaryElement, node.id)
        }
        XCTAssertEqual(tree.path(to: "see-manazashi").count, 4, "根 → 一の技 → 二の技 → 奥義")
        if case .locked(let requirement) = tree.check("see-tomeru") {
            XCTAssertEqual(requirement.sentence, "見る 一段")
        } else {
            XCTFail("まだ届かない")
        }
    }

    func testRecordingGivesExperienceRankAndSprouts() {
        var tree = buildTree([selfEntry("夕焼けがきれいだった", ["see", "pause"])])
        XCTAssertEqual(tree.progress(of: "see"), ElementProgress(element: "see", experience: 1, rank: 1, sprouts: 1))
        XCTAssertEqual(tree.progress(of: "pause").rank, 1)
        XCTAssertEqual(tree.state(of: ExperienceTree.rootID("see")), .learned)
        XCTAssertEqual(tree.state(of: "see-tomeru"), .ready)
        XCTAssertEqual(tree.check("see-tomeru"), .available(charge: "see"))
        XCTAssertEqual(Set(tree.sproutingElements.map(\.id)), ["see", "pause"])
        XCTAssertEqual(tree.totalRank, 2)

        tree = buildTree(selfEntries(6, ["see"]))
        XCTAssertEqual(tree.progress(of: "see").rank, 3)
        XCTAssertEqual(tree.progress(of: "see").sprouts, 3)
        XCTAssertEqual(tree.progress(of: "see").remaining, 4)
    }

    func testOnlyCompletedRecordsCountAndOldRecordsFindTheirElements() {
        // 3.0 より前の記録: 要素も id も無い。名前と文から推し量る
        let old = HistoryEntry(createdAt: referenceDate, title: "いちばん小さな音", theme: nil, invitation: "i", perspective: "p", tags: ["sensory"], status: .completed, rating: .positive)
        let declined = livedEntry("rest-far", status: .declined)
        let active = livedEntry("rest-far", status: .active)
        let tree = buildTree([old, declined, active])
        XCTAssertEqual(tree.progress(of: "hear").experience, 1, "ライブラリの同じ名前の体験の要素")
        XCTAssertEqual(tree.progress(of: "pause").experience, 1)
        XCTAssertEqual(tree.progress(of: "see").experience, 0, "断った・体験中は数えない")
    }

    func testGrowingAnArtRevealsWhatIsNext() {
        let entries = selfEntries(3, ["see"])
        let garden = Garden(learned: learned(["see-tomeru"]))
        let tree = buildTree(entries, garden: garden)
        XCTAssertEqual(tree.state(of: "see-tomeru"), .learned)
        XCTAssertEqual(tree.mastery(of: "see-tomeru"), .shu)
        XCTAssertEqual(tree.progress(of: "see").sprouts, 1, "二段 − 使った芽1")
        XCTAssertEqual(tree.state(of: "see-toome"), .sensed, "隣の技が身につくと、名前が見える")
        XCTAssertEqual(tree.requirement(of: "see-toome")?.sentence, "見る 三段、「目を留める」が身についていること")
        XCTAssertEqual(tree.state(of: "see-tana"), .unknown, "別の枝はまだ霧")
        XCTAssertEqual(tree.learnedNodes.map(\.id), ["see-tomeru"])

        let deeper = buildTree(selfEntries(6, ["see"]), garden: garden)
        XCTAssertEqual(deeper.state(of: "see-toome"), .ready)
        XCTAssertEqual(deeper.check("see-toome"), .available(charge: "see"))
    }

    func testSproutsAreScarce() {
        // 一段で芽はひとつ。ひとつ伸ばしたら、ほかの一の技は条件がそろっていても芽を待つ
        let garden = Garden(learned: learned(["see-tomeru"]))
        let tree = buildTree([selfEntry("空", ["see"])], garden: garden)
        XCTAssertEqual(tree.state(of: "see-chigai"), .ready)
        XCTAssertEqual(tree.check("see-chigai"), .needsSprout(["see"]))
        XCTAssertFalse(tree.hasLearnable(inElement: "see"))
        XCTAssertEqual(tree.check("see-tomeru"), .learned)
        XCTAssertEqual(tree.check(ExperienceTree.rootID("see")), .notGrowable)
    }

    func testSecretNeedsTwoOfTheSecondArts() {
        let entries = selfEntries(21, ["see"])
        let one = buildTree(entries, garden: Garden(learned: learned(["see-tomeru", "see-chigai", "see-toome"])))
        XCTAssertEqual(one.state(of: "see-manazashi"), .sensed)
        XCTAssertEqual(one.requirement(of: "see-manazashi")?.afterText, "「遠目」「隅々」「色を拾う」のうち二つ")
        let two = buildTree(entries, garden: Garden(learned: learned(["see-tomeru", "see-chigai", "see-toome", "see-tana"])))
        XCTAssertEqual(two.state(of: "see-manazashi"), .ready)
        XCTAssertEqual(two.node("see-manazashi")?.kindLabel, "奥義")
        let notYet = buildTree(Array(entries.prefix(15)), garden: Garden(learned: learned(["see-tomeru", "see-chigai", "see-toome", "see-tana"])))
        XCTAssertEqual(notYet.state(of: "see-manazashi"), .sensed, "五段では、まだ届かない")
    }

    func testCrossArtsNeedBothElements() {
        let garden = Garden(learned: learned(["see-tomeru"]))
        let thinkOnce = buildTree(selfEntries(3, ["see"]) + [selfEntry("なぜ", ["think"])], garden: garden)
        XCTAssertEqual(thinkOnce.state(of: "cross-mitate"), .sensed, "見るの技の先に気配が出る")
        XCTAssertEqual(thinkOnce.requirement(of: "cross-mitate")?.rankText, "見る 二段・考える 二段")
        let both = buildTree(selfEntries(3, ["see"]) + selfEntries(3, ["think"]), garden: garden)
        XCTAssertEqual(both.state(of: "cross-mitate"), .ready)
        XCTAssertEqual(both.check("cross-mitate"), .available(charge: "see"))
        XCTAssertTrue(both.incoming(to: "cross-mitate").contains { $0.from == "think-naze" && $0.kind == .cross })
        XCTAssertTrue(both.incoming(to: "cross-mitate").contains { $0.from == "see-tomeru" && $0.kind == .branch })
        // 見るの芽を使いきっていれば、考えるの芽を使う
        let spent = buildTree(selfEntries(3, ["see"]) + selfEntries(3, ["think"]), garden: Garden(learned: learned(["see-tomeru", "see-chigai"])))
        XCTAssertEqual(spent.check("cross-mitate"), .available(charge: "think"))
    }

    func testPracticeAndChosenUsesDeepenAnArt() {
        // 遠目の稽古 (いちばん遠くを見る) を身につく前から重ねていても、身についたら数える
        let practice = (0..<7).map { livedEntry("rest-far", daysAgo: $0 + 1) }
        var garden = Garden(learned: learned(["see-tomeru", "see-toome"]))
        var tree = buildTree(Array(practice.prefix(3)), garden: garden)
        XCTAssertEqual(tree.life(of: "see-toome")?.uses, 3)
        XCTAssertEqual(tree.mastery(of: "see-toome"), .ha)
        tree = buildTree(practice, garden: garden)
        XCTAssertEqual(tree.mastery(of: "see-toome"), .ri)
        XCTAssertNil(tree.mastery(of: "see-chigai"), "身についていない技は深まらない")

        // 自分で記した体験に、使った技を結ぶ
        let own = selfEntry("遠くの鉄塔が見えた", ["see"])
        garden.uses = [SkillUse(entryID: own.id, skills: ["see-tomeru"])]
        tree = buildTree([own], garden: garden)
        XCTAssertEqual(tree.life(of: "see-tomeru")?.uses, 1)
        XCTAssertEqual(tree.skills(usedIn: own.id).map(\.id), ["see-tomeru"])
    }

    func testFlashesComeFromHowYouLive() {
        func found(_ entries: [HistoryEntry], garden: Garden = .empty) -> Set<String> {
            Set(buildTree(entries, garden: garden).nodes.filter { $0.kind == .flash }.map(\.id))
        }
        XCTAssertEqual(found([selfEntry("温かいお茶", ["taste", "smell", "touch"])]), ["flash-gokan"])
        XCTAssertEqual(found([selfEntry("考えながら書いた", ["think", "word", "people"])]), [], "五感が二つ無ければ閃かない")
        XCTAssertEqual(found([selfEntry("朝焼け", ["see"], at: tokyoDate("2026-10-07", hour: 5))]), ["flash-yoake"])
        XCTAssertEqual(found([selfEntry("虫の声", ["hear"], at: tokyoDate("2026-10-07", hour: 21))]), ["flash-yorumimi"])
        XCTAssertEqual(found([selfEntry("夜景", ["see"], at: tokyoDate("2026-10-07", hour: 21))]), [])
        let day = [8, 13, 20].map { selfEntry("一日\($0)", ["move"], at: tokyoDate("2026-10-06", hour: $0)) }
        XCTAssertEqual(found(day), ["flash-meguri"])
        let week = (1...7).map { selfEntry("日々\($0)", ["word"], at: tokyoDate("2026-10-0\($0)", hour: 12)) }
        XCTAssertEqual(found(week), ["flash-nanoka"])
        XCTAssertEqual(found(selfEntries(10, ["think"])), ["flash-jibun"])
        XCTAssertEqual(found(Array(selfEntries(10, ["think"]).prefix(9))), [])
        let everything = TaikenContent.shared.elements.map { selfEntry($0.label, [$0.id], at: tokyoDate("2026-10-07", hour: 12)) }
        XCTAssertTrue(found(everything).contains("flash-tone"))
        XCTAssertEqual(found([], garden: Garden(ties: [Tie(between: "see-tomeru", and: "hear-sumasu", createdAt: referenceDate)])), ["flash-hibiki"])
        let practice = (0..<7).map { livedEntry("rest-far", daysAgo: $0 + 1) }
        XCTAssertTrue(found(practice, garden: Garden(learned: learned(["see-tomeru", "see-toome"]))).contains("flash-kiwami"))

        let tree = buildTree([selfEntry("温かいお茶", ["taste", "smell", "touch"])])
        let flash = tree.node("flash-gokan")
        XCTAssertEqual(flash?.found, "ひとつの体験で、ふたつの感覚を含む三つの要素に触れたとき")
        XCTAssertEqual(tree.state(of: "flash-gokan"), .learned)
        XCTAssertEqual(tree.glyph(of: flash!), "閃")
        XCTAssertEqual(tree.hiddenFlashes, 8)
        XCTAssertEqual(tree.check("flash-gokan"), .notGrowable, "閃きは芽を使わない")
        XCTAssertEqual(tree.path(to: "flash-gokan").map(\.id), [ExperienceTree.rootID("touch"), "flash-gokan"])
        XCTAssertNil(tree.depths["flash-gokan"], "閃きは要素の枝の外")
    }

    func testRememberedFlashStaysAfterRecordsAreGone() {
        let garden = Garden(learned: [LearnedSkill(id: "flash-yoake", element: nil, learnedAt: referenceDate)])
        let tree = buildTree([], garden: garden)
        XCTAssertEqual(tree.state(of: "flash-yoake"), .learned)
        XCTAssertEqual(tree.learnedAt("flash-yoake"), referenceDate)
        XCTAssertEqual(tree.progress(of: "see").sprouts, 0, "閃きは芽を使わない")
    }

    func testWovenArtsFromThisAndTheLastVersion() {
        // 3.0 で編んだ体験 (ライブラリの体験から伸ばしていた) は、根から伸びる自分の技になる
        let old = PersonalNode(id: "w-aaaa", kind: .woven, title: "湯気の形", invitation: "湯気の形を見てみませんか？", elements: ["see", "taste"], growsFrom: "rest-warm-cup", createdAt: referenceDate)
        let new = PersonalNode(id: "w-bbbb", kind: .woven, title: "遠くの鉄塔", invitation: "", perspective: "鉄塔の数で、どこまで来たか分かる。", elements: ["see"], growsFrom: "see-tomeru", createdAt: referenceDate)
        let found = PersonalNode(id: "f-cccc", kind: .found, title: "AIの体験", invitation: "してみませんか？", elements: ["see"], createdAt: referenceDate)
        let garden = Garden(nodes: [old, new, found], learned: learned(["see-tomeru"]))
        let tree = buildTree([selfEntry("空", ["see"])], garden: garden)
        let woven = tree.node("w-aaaa")
        XCTAssertEqual(woven?.kind, .woven)
        XCTAssertEqual(woven?.ability, "湯気の形を見てみませんか？", "見方が無ければ誘いかけを使う")
        XCTAssertEqual(woven?.practiceText, "湯気の形を見てみませんか？")
        XCTAssertEqual(woven?.after, [], "知らない元から伸びていたら、根から")
        XCTAssertEqual(tree.parents["w-aaaa"], ExperienceTree.rootID("see"))
        XCTAssertEqual(tree.node("w-bbbb")?.after, ["see-tomeru"])
        XCTAssertEqual(tree.parents["w-bbbb"], "see-tomeru")
        XCTAssertNil(tree.node("w-bbbb")?.practiceText)
        XCTAssertNil(tree.node("f-cccc"), "3.0 で見つけた体験は、技の樹には出さない")
        XCTAssertEqual(tree.state(of: "w-aaaa"), .ready)
        XCTAssertNotNil(tree.node("w-aaaa")?.ownPractice())
        XCTAssertEqual(tree.node("w-aaaa")?.ownPractice()?.nodeID, "w-aaaa")
    }

    func testTiesAreBetweenSkillsAndNotBranches() {
        let garden = Garden(learned: learned(["see-tomeru", "hear-sumasu"]))
        var withTie = garden
        withTie.ties = [Tie(between: "see-tomeru", and: "hear-sumasu", note: "どちらも、じっと", createdAt: referenceDate)]
        let tree = buildTree([selfEntry("a", ["see", "hear"])], garden: withTie)
        XCTAssertEqual(tree.ties(of: "hear-sumasu").first?.note, "どちらも、じっと")
        XCTAssertTrue(tree.outgoing(from: "see-tomeru").allSatisfy { $0.kind != .tie })
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

    func testContextCarriesWhatWasLivedAndThePracticeOfYourSkills() {
        let entries = [livedEntry("rest-far", daysAgo: 2), livedEntry("root-hear", daysAgo: 1), selfEntry("自分の言葉", ["see"])]
        let tree = buildTree(entries, garden: Garden(learned: learned(["see-tomeru"])))
        let context = tree.context(entries: entries)
        XCTAssertEqual(context.lived.map(\.id), ["root-hear", "rest-far"], "ライブラリの体験だけ、最近のものから")
        XCTAssertEqual(Array(context.buds.prefix(2)), ["root-see", "work-desk-map"], "身についた技の稽古が先")
        // まだ何も身についておらず、段も無ければ、根の体験
        let fresh = buildTree().context(entries: [])
        XCTAssertEqual(fresh.buds, TaikenContent.shared.elements.map(\.root))
    }

    func testPracticeOwnersHideTheFog() {
        let tree = buildTree([selfEntry("空", ["see"])], garden: Garden(learned: learned(["see-tomeru"])))
        XCTAssertEqual(tree.skills(practicing: "root-see").first?.id, "see-tomeru", "身についた技が先")
        XCTAssertEqual(tree.learnedSkills(touching: ["see", "word"]).map(\.id), ["see-tomeru"])
        XCTAssertEqual(tree.suggestedSkills(for: "窓の外をじっと眺めた", elements: ["see"]).map(\.id), ["see-tomeru"])
        XCTAssertTrue(tree.suggestedSkills(for: "音がした", elements: ["see"]).isEmpty)
    }

    func testGrowthBetweenTwoTrees() {
        let before = buildTree(selfEntries(2, ["see"]), garden: Garden(learned: learned(["see-tomeru"])))
        let entry = selfEntry("温かいお茶と夕焼け", ["see", "taste", "touch"])
        let after = buildTree(selfEntries(2, ["see"]) + [entry], garden: Garden(learned: learned(["see-tomeru"])))
        let report = GrowthReport.between(before, after, gained: entry.elements)
        XCTAssertEqual(report.gains.map(\.id), ["see", "taste", "touch"])
        XCTAssertEqual(report.rankUps.map(\.element.id), ["see", "taste", "touch"])
        XCTAssertEqual(report.rankUps.first?.to, 2)
        XCTAssertEqual(report.flashes.map(\.id), ["flash-gokan"])
        XCTAssertTrue(report.hasMoment)
        XCTAssertEqual(Set(report.sproutElements.map(\.id)), ["see", "taste", "touch"])

        let since = GrowthReport.since(nothing: after)
        XCTAssertEqual(since.rankUps.first(where: { $0.element.id == "see" })?.to, 2)
        XCTAssertTrue(GrowthReport.empty.isEmpty)
    }

    /// 記録を消して段が下がり、同じ段へ戻っても、その段の芽はもう使っているので新しくは出ない
    func testRegainingARankAfterDeletingARecordBringsNoNewSprout() {
        let garden = Garden(learned: learned(["see-tomeru", "see-chigai"]))
        let three = selfEntries(3, ["see"])
        XCTAssertEqual(buildTree(three, garden: garden).progress(of: "see").sprouts, 0, "二段の芽は二つとも使った")

        let afterDeletion = Array(three.dropLast())
        let before = buildTree(afterDeletion, garden: garden)
        XCTAssertEqual(before.progress(of: "see").rank, 1)
        XCTAssertEqual(before.state(of: "see-chigai"), .learned, "身についた技は、記録を消しても残る")

        let entry = selfEntry("また遠くを眺めた", ["see"])
        let after = buildTree(afterDeletion + [entry], garden: garden)
        let report = GrowthReport.between(before, after, gained: entry.elements)
        XCTAssertEqual(report.rankUps.map(\.to), [2])
        XCTAssertEqual(report.rankUps.first?.sprouts, 0)

        let fresh = GrowthReport.between(buildTree(selfEntries(2, ["hear"])), buildTree(selfEntries(3, ["hear"])), gained: ["hear"])
        XCTAssertEqual(fresh.rankUps.first?.sprouts, 1)
    }
}

final class TreeLayoutTests: XCTestCase {
    func testLayoutIsDeterministicAndRadial() {
        let entries = [selfEntry("温かいお茶", ["taste", "smell", "touch"])]
        let tree = buildTree(entries)
        let first = TreeLayout.make(tree: tree)
        XCTAssertEqual(first, TreeLayout.make(tree: buildTree(entries)), "同じ樹は、いつも同じ配置")
        XCTAssertEqual(first.positions.count, tree.nodes.count)
        XCTAssertEqual(first.sectors.map(\.element), TaikenContent.shared.elements.map(\.id))
        let total = first.sectors.reduce(0) { $0 + ($1.end - $1.start) }
        XCTAssertEqual(total, 2 * Double.pi, accuracy: 1e-9)
        XCTAssertEqual(first.sectors[0].center, -Double.pi / 2, accuracy: 1e-9, "見るは真上")

        let center = TreeLayout.Point(x: 0, y: 0)
        let outer = (tree.depths.values.max() ?? 0) + 1
        for node in tree.nodes {
            let r = first.position(of: node.id)?.distance(to: center) ?? 0
            let depth = node.kind == .flash ? outer : tree.depths[node.id] ?? 0
            XCTAssertEqual(r, TreeLayout.rootRadius + Double(depth) * TreeLayout.ringStep, accuracy: 0.03, node.id)
        }
        // 閃きは、その要素の扇の中
        let flash = try? XCTUnwrap(first.position(of: "flash-gokan"))
        let angle = atan2(flash?.y ?? 0, flash?.x ?? 0)
        let sector = first.sectors.first { $0.element == "touch" }!
        let normalized = angle < sector.start ? angle + 2 * Double.pi : angle
        XCTAssertTrue(normalized >= sector.start && normalized <= sector.end + 0.2)
    }

    func testNodesDoNotOverlap() {
        let layout = TreeLayout.make(tree: buildTree())
        let points = Array(layout.positions.values)
        var closest = Double.infinity
        for i in 0..<points.count {
            for j in (i + 1)..<points.count {
                closest = min(closest, points[i].distance(to: points[j]))
            }
        }
        XCTAssertGreaterThan(closest, 0.04, "技どうしが重ならない")
    }

    func testSignatureChangesOnlyWithShape() {
        let a = buildTree()
        let b = buildTree([selfEntry("空", ["see"])], garden: Garden(learned: learned(["see-tomeru"])))
        XCTAssertEqual(TreeLayout.signature(of: a), TreeLayout.signature(of: b), "伸ばしただけでは配置は変わらない")
        let woven = PersonalNode(id: "w-bbbb", kind: .woven, title: "新しい技", invitation: "", perspective: "できる。", elements: ["word"], createdAt: referenceDate)
        XCTAssertNotEqual(TreeLayout.signature(of: a), TreeLayout.signature(of: buildTree(garden: Garden(nodes: [woven]))))
        XCTAssertNotEqual(TreeLayout.signature(of: a), TreeLayout.signature(of: buildTree([selfEntry("お茶", ["taste", "smell", "touch"])])), "閃くと、樹に節が増える")
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

    func testSuggestsElementsForYourOwnWords() {
        XCTAssertEqual(classifier.suggest(for: "帰り道、金木犀の香りがした").first, "smell")
        XCTAssertEqual(classifier.suggest(for: "味噌汁がおいしかった").first, "taste")
        XCTAssertEqual(classifier.suggest(for: "  "), [])
        XCTAssertEqual(classifier.suggest(for: "ふむ"), [], "手がかりが無ければ、自分で選んでもらう")
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
            nodes: [PersonalNode(id: "w-cccc", kind: .woven, title: "影を踏む", invitation: "", perspective: "影の位置で時刻が分かる。", elements: ["move"], createdAt: referenceDate)],
            ties: [Tie(between: "w-cccc", and: "move-hakobi", createdAt: referenceDate)],
            learned: [LearnedSkill(id: "move-hakobi", element: "move", learnedAt: referenceDate)],
            uses: [SkillUse(entryID: UUID(), skills: ["move-hakobi"])],
            seen: true
        )
        try store.save(garden)
        XCTAssertEqual(FileGardenStore(url: store.url).load(), garden)
        store.delete()
        XCTAssertEqual(store.load(), .empty)
    }

    func testReadsTheGardenOfVersion3() throws {
        let json = """
        {"version":1,"nodes":[{"id":"w-aaaa","kind":"woven","title":"湯気の形","invitation":"湯気を見てみませんか？","perspective":"","elements":["see"],"tags":[],"growsFrom":"rest-warm-cup","createdAt":"2026-10-07T09:00:00Z"}],"ties":[]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let garden = try decoder.decode(Garden.self, from: Data(json.utf8))
        XCTAssertEqual(garden.version, 1)
        XCTAssertEqual(garden.nodes.first?.title, "湯気の形")
        XCTAssertTrue(garden.learned.isEmpty)
        XCTAssertFalse(garden.seen)
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
    }
}

@MainActor
final class TreeSourceTests: XCTestCase {
    private func make(_ entries: [HistoryEntry] = [], garden: Garden = .empty) -> (TreeSource, InMemoryHistoryRepository, InMemoryGardenStore) {
        let history = InMemoryHistoryRepository(entries)
        let store = InMemoryGardenStore(garden)
        return (TreeSource(history: history, store: store, calendar: tokyoCalendar, now: { referenceDate }), history, store)
    }

    func testLearningUsesASproutAndCanFail() async throws {
        let (source, _, store) = make([selfEntry("空", ["see"])])
        XCTAssertThrowsError(try source.learn("see-toome")) { error in
            XCTAssertEqual((error as? TreeSource.LearnError)?.errorDescription, "まだ届きません。見る 三段、「目を留める」が身についていること")
        }
        try source.learn("see-tomeru")
        XCTAssertEqual(store.load().learned.first, LearnedSkill(id: "see-tomeru", element: "see", learnedAt: referenceDate))
        XCTAssertEqual(store.load().version, Garden.currentVersion)
        XCTAssertEqual(source.tree().progress(of: "see").sprouts, 0)
        XCTAssertThrowsError(try source.learn("see-chigai")) { error in
            XCTAssertEqual(error as? TreeSource.LearnError, .noSprout("見る"))
        }
        XCTAssertThrowsError(try source.learn("see-tomeru")) { error in
            XCTAssertEqual(error as? TreeSource.LearnError, .unavailable)
        }
    }

    func testLearningAnArtYouAlreadyPracticedCanBringAFlash() async throws {
        let practice = (0..<7).map { livedEntry("rest-far", daysAgo: $0 + 1) }
        let (source, _, _) = make(practice + selfEntries(6, ["see"]), garden: Garden(learned: learned(["see-tomeru"])))
        XCTAssertEqual(source.settle(), ["flash-nanoka"], "七つの別々の日に記していた")
        let flashes = try source.learn("see-toome")
        XCTAssertEqual(flashes, ["flash-kiwami"], "稽古を重ねていた技は、身についたとたんに離に届く")
        XCTAssertEqual(source.tree().mastery(of: "see-toome"), .ri)
    }

    func testSettleRemembersFlashes() async throws {
        let entry = selfEntry("朝焼け", ["see"], at: tokyoDate("2026-10-07", hour: 5))
        let (source, history, store) = make([entry])
        XCTAssertEqual(source.settle(), ["flash-yoake"])
        XCTAssertEqual(source.settle(), [], "二度は数えない")
        try history.delete(id: entry.id)
        XCTAssertEqual(source.tree().state(of: "flash-yoake"), .learned, "記録を消しても、閃きは消えない")
        XCTAssertNil(store.load().learned.first?.element)
    }

    func testLinksOnlyLearnedSkillsToARecord() async {
        let entry = selfEntry("じっと眺めた", ["see"])
        let (source, _, store) = make([entry], garden: Garden(learned: learned(["see-tomeru"])))
        source.link(entry: entry.id, skills: ["see-tomeru", "see-toome", "see-tomeru", ExperienceTree.rootID("see")])
        XCTAssertEqual(store.load().uses, [SkillUse(entryID: entry.id, skills: ["see-tomeru"])])
        source.link(entry: entry.id, skills: [])
        XCTAssertTrue(store.load().uses.isEmpty)
        source.link(entry: entry.id, skills: ["see-tomeru"])
        source.forget(entry: entry.id)
        XCTAssertTrue(store.load().uses.isEmpty)
    }

    func testWelcomeShowsWhatGrewBeforeOnce() async {
        let (source, _, _) = make([livedEntry("rest-far", daysAgo: 3), livedEntry("root-see", daysAgo: 2), livedEntry("morning-light", daysAgo: 1)])
        let welcome = source.welcome()
        XCTAssertEqual(welcome?.rankUps.first { $0.element.id == "see" }?.to, 2, "3.0 の記録から、見るは二段に")
        source.markSeen()
        XCTAssertNil(source.welcome())

        let (fresh, _, _) = make()
        XCTAssertNil(fresh.welcome(), "まだ何も無ければ見せない")
    }

    func testWeaveValidatesPlantsAndRefundsOnRemoval() async throws {
        let (source, _, store) = make([selfEntry("空", ["see"])])
        XCTAssertThrowsError(try source.weave(WeaveDraft(title: "", ability: "a", elements: ["see"]))) { error in
            XCTAssertEqual(error as? WeaveError, .invalid(.missingTitle))
        }
        XCTAssertThrowsError(try source.weave(WeaveDraft(title: "遠目", ability: "a", elements: ["see"]))) { error in
            XCTAssertEqual(error as? WeaveError, .invalid(.duplicateTitle), "技の樹にある名前は使えない")
        }
        XCTAssertThrowsError(try source.weave(WeaveDraft(title: "x", ability: "", elements: ["see"]))) { error in
            XCTAssertEqual(error as? WeaveError, .invalid(.missingAbility))
        }
        XCTAssertThrowsError(try source.weave(WeaveDraft(title: "x", ability: "a", elements: ["bogus"]))) { error in
            XCTAssertEqual(error as? WeaveError, .invalid(.missingElement))
        }
        XCTAssertThrowsError(try source.weave(WeaveDraft(title: "x", ability: "a", elements: ["see", "hear", "move"]))) { error in
            XCTAssertEqual(error as? WeaveError, .invalid(.tooManyElements))
        }
        let node = try source.weave(WeaveDraft(title: " 湯気の形 ", ability: "湯気の形で、温度が分かる。", practice: "湯気を見送ってみる", elements: ["see", "taste"], growsFrom: ExperienceTree.rootID("see")))
        XCTAssertEqual(node.title, "湯気の形")
        XCTAssertNil(node.growsFrom, "根から伸ばすときは、元を持たない")
        XCTAssertEqual(source.tree().state(of: node.id), .ready)
        try source.learn(node.id)
        XCTAssertEqual(source.tree().progress(of: "see").sprouts, 0)

        try source.revise(node.id, with: WeaveDraft(title: "湯気のかたち", ability: "湯気で温度が分かる。", elements: ["see"], growsFrom: node.id))
        XCTAssertEqual(source.garden.node(node.id)?.title, "湯気のかたち")
        XCTAssertNil(source.garden.node(node.id)?.growsFrom, "自分自身からは伸ばせない")

        try source.remove(node.id)
        XCTAssertNil(source.tree().node(node.id))
        XCTAssertTrue(store.load().learned.isEmpty)
        XCTAssertEqual(source.tree().progress(of: "see").sprouts, 1, "手放すと、芽は戻る")
    }

    func testTiesAndTheFlashOfResonance() async throws {
        let (source, _, store) = make([selfEntry("a", ["see", "hear"])], garden: Garden(learned: learned(["see-tomeru", "hear-sumasu"])))
        XCTAssertEqual(try source.tie("see-tomeru", "hear-sumasu", note: "どちらも、じっと"), ["flash-hibiki"])
        XCTAssertEqual(try source.tie("hear-sumasu", "see-tomeru"), [], "同じ糸は二本にしない")
        XCTAssertEqual(try source.tie("see-tomeru", "see-tomeru"), [])
        XCTAssertEqual(try source.tie("see-tomeru", ExperienceTree.rootID("see")), [], "根とは結ばない")
        XCTAssertEqual(try source.tie("see-tomeru", "unknown"), [])
        XCTAssertEqual(store.load().ties.count, 1)
        try source.untie(XCTUnwrap(store.load().ties.first).id)
        XCTAssertTrue(store.load().ties.isEmpty)
        XCTAssertEqual(source.tree().state(of: "flash-hibiki"), .learned, "一度閃いたものは残る")
    }

    func testPlacesWithoutPlantingAnything() async {
        let (source, _, store) = make()
        let library = source.place(Experience(title: "三つの音", perspective: "p", invitation: "i", reason: "", difficulty: .low, tags: []))
        XCTAssertEqual(library.nodeID, "commute-sounds")
        XCTAssertEqual(library.elements, ["hear", "move"])
        let ai = source.place(Experience(title: "湯気の向こう", perspective: "p", invitation: "湯気越しに部屋を眺めてみませんか？", reason: "", difficulty: .low, tags: [], nodeID: "nope-nope", growsFrom: "meal-first-bite"))
        XCTAssertNil(ai.nodeID)
        XCTAssertNil(ai.growsFrom)
        XCTAssertFalse(ai.elements.isEmpty)
        XCTAssertTrue(store.load().isEmpty, "4.0 では、AIの体験を樹に植えない")
    }

    func testLineageNamesTheSkillButNotTheFog() async {
        let (source, _, _) = make([selfEntry("空", ["see"])], garden: Garden(learned: learned(["see-tomeru"])))
        let rootSee = libraryExperience("root-see")
        XCTAssertEqual(source.lineage(of: rootSee).sentence, "身についた技「目を留める」の稽古")
        XCTAssertEqual(source.lineage(of: rootSee).nodeID, "see-tomeru")
        let ready = source.lineage(of: libraryExperience("daily-difference"))
        XCTAssertEqual(ready.sentence, "育てられる技「違いの目」の稽古")
        // 霧の中の技 (遠目) の名前は明かさない
        let fog = source.lineage(of: libraryExperience("hear-far"))
        XCTAssertNil(fog.skillTitle)
        XCTAssertEqual(fog.sentence, "「聴く」の稽古")
        XCTAssertEqual(fog.nodeID, ExperienceTree.rootID("hear"))
        let new = source.lineage(of: Experience(title: "まだ無い体験", perspective: "p", invitation: "空を見てみませんか？", reason: "", difficulty: .low, tags: []))
        XCTAssertTrue(new.isNew)
        XCTAssertEqual(new.elements.first?.id, "see")
        XCTAssertEqual(new.sentence, "新しい体験 — 記すと、触れた要素に経験が積もります")
    }

    private func libraryExperience(_ id: String) -> Experience {
        TaikenContent.shared.experience(id)!.asExperience()
    }
}

@MainActor
final class TreeFlowTests: XCTestCase {
    private func make(_ h: Harness, service: StubService = StubService(), garden: Garden = .empty) -> (HomeViewModel, TreeSource, InMemoryGardenStore) {
        let store = InMemoryGardenStore(garden)
        let trees = TreeSource(history: h.history, store: store, calendar: tokyoCalendar, now: { h.clock.now })
        let model = HomeViewModel(service: service, assembler: h.assembler, history: h.history, cache: h.cache, trees: trees)
        return (model, trees, store)
    }

    func testRecordingYourOwnExperienceGrowsTheTree() async {
        let h = Harness()
        let (model, trees, _) = make(h)
        await model.refresh()
        XCTAssertEqual(model.stage, .idle, "きっかけは、求められるまで作らない")
        XCTAssertTrue(h.history.storage.isEmpty)

        XCTAssertEqual(model.record(LivedDraft(text: "  ", elements: ["see"])), .empty, "言葉が無ければ記さない")
        XCTAssertEqual(model.record(LivedDraft(text: "夕焼け", elements: [])), .empty, "要素が無ければ記さない")

        let report = model.record(LivedDraft(text: "帰り道、夕焼けが長かった", elements: ["see", "pause"]))
        XCTAssertEqual(model.stage, .completed)
        XCTAssertEqual(model.completedEntry?.title, "帰り道、夕焼けが長かった")
        XCTAssertEqual(model.completedEntry?.isSelfRecorded, true)
        XCTAssertEqual(report.gains.map(\.id), ["see", "pause"])
        XCTAssertEqual(report.rankUps.map(\.to), [1, 1])
        XCTAssertEqual(Set(report.sproutElements.map(\.id)), ["see", "pause"])
        XCTAssertEqual(model.todayEntries.count, 1)
        XCTAssertNotNil(model.restingUntil, "記したあとは、しばらく通知を控える")
        XCTAssertEqual(trees.tree().progress(of: "see").rank, 1)

        model.dismissCompleted()
        XCTAssertEqual(model.stage, .idle)
    }

    func testDoingAPracticeDeepensTheSkill() async throws {
        let h = Harness(entries: selfEntries(6, ["see"]))
        let (model, trees, _) = make(h, garden: Garden(learned: learned(["see-tomeru", "see-toome"])))
        let entry = livedEntry("rest-far", daysAgo: 2)
        try h.history.add(entry)
        try h.history.add(livedEntry("rest-far", daysAgo: 3))
        model.begin(TaikenContent.shared.experience("rest-far")!.asExperience())
        XCTAssertEqual(model.stage, .active)
        XCTAssertEqual(model.activeEntry?.nodeID, "rest-far")
        XCTAssertEqual(model.activeLineage?.sentence, "身についた技「遠目」の稽古")
        model.finish(rating: .positive, note: "遠くの鉄塔", skills: ["see-tomeru"])
        XCTAssertEqual(model.completedGrowth.deepened.map(\.node.id), ["see-toome"], "三回目の稽古で、守から破へ")
        XCTAssertEqual(model.completedGrowth.deepened.first?.mastery, .ha)
        XCTAssertEqual(trees.tree().life(of: "see-tomeru")?.uses, 1, "自分で選んだ技にも数える")
    }

    func testAskingForAPromptIsTheOnlyWayToGetOne() async {
        let h = Harness()
        let service = StubService()
        let (model, _, _) = make(h, service: service)
        await model.refresh()
        XCTAssertEqual(service.experienceRequests.count, 0)
        await model.requestPrompt()
        XCTAssertEqual(model.stage, .proposal)
        XCTAssertEqual(service.experienceRequests.count, 1)
        model.notNow()
        XCTAssertEqual(model.stage, .idle, "断っても、ホームはふだんのまま")
        await model.refresh()
        XCTAssertEqual(service.experienceRequests.count, 1)
    }

    func testStartingAPracticeReplacesThePrompt() async {
        let h = Harness()
        let (model, _, _) = make(h)
        await model.requestPrompt()
        XCTAssertEqual(model.stage, .proposal)
        model.begin(TaikenContent.shared.experience("root-touch")!.asExperience())
        XCTAssertEqual(model.stage, .active)
        XCTAssertEqual(model.activeEntry?.nodeID, "root-touch")
        XCTAssertNil(model.proposal)
        XCTAssertNil(h.cache.load(), "置いていたきっかけは片づける")
        XCTAssertTrue(h.history.storage.allSatisfy { $0.status != .declined }, "稽古を選んだことは、きっかけを断ったことにしない")
    }

    func testWelcomeIsShownOnceForThoseWhoComeFromVersion3() async {
        let h = Harness(entries: [livedEntry("rest-far", daysAgo: 3), livedEntry("root-see", daysAgo: 2), livedEntry("morning-light", daysAgo: 1)])
        let (model, _, store) = make(h)
        await model.refresh()
        XCTAssertEqual(model.welcome?.rankUps.first?.to, 2)
        model.dismissWelcome()
        XCTAssertNil(model.welcome)
        XCTAssertTrue(store.load().seen)
        await model.refresh()
        XCTAssertNil(model.welcome)

        let fresh = Harness()
        let (newcomer, _, newcomerStore) = make(fresh)
        await newcomer.refresh()
        XCTAssertNil(newcomer.welcome)
        XCTAssertTrue(newcomerStore.load().seen, "はじめての人には見せず、見届けたことにする")
    }

    func testRequestCarriesTheTreeButNotYourOwnWords() async throws {
        var h = Harness(entries: [livedEntry("rest-far"), selfEntry("自分だけの言葉", ["see"])])
        let trees = TreeSource(history: h.history, store: InMemoryGardenStore(Garden(learned: learned(["see-tomeru"]))), calendar: tokyoCalendar, now: { referenceDate })
        h.assembler.treeContext = { trees.context() }
        let request = await h.assembler.experienceRequest()
        XCTAssertEqual(request.tree?.lived.map(\.id), ["rest-far"])
        XCTAssertEqual(request.tree?.buds.first, "root-see")
        XCTAssertEqual(request.recentExperiences.map(\.title), ["いちばん遠くを見る"], "自分で記した言葉は送らない")

        h = Harness(consent: ConsentSnapshot(useHistory: false), entries: [livedEntry("rest-far")])
        h.assembler.treeContext = { trees.context() }
        let withoutHistory = await h.assembler.experienceRequest()
        XCTAssertNil(withoutHistory.tree)
    }
}

@MainActor
final class TreeViewModelTests: XCTestCase {
    private func make(_ entries: [HistoryEntry], garden: Garden = .empty) -> (TreeViewModel, TreeSource) {
        let trees = TreeSource(history: InMemoryHistoryRepository(entries), store: InMemoryGardenStore(garden), calendar: tokyoCalendar, now: { referenceDate })
        return (TreeViewModel(source: trees, onStart: { _ in }), trees)
    }

    func testSummaryFollowsTheGrowth() async {
        let (empty, _) = make([])
        XCTAssertEqual(empty.summary, "まだ経験はありません。ホームから体験を記すと、触れた要素に経験が積もり、段が上がります。")
        XCTAssertTrue(empty.hasHiddenFlashes)
        let (sprouting, _) = make([selfEntry("空", ["see", "hear"])])
        XCTAssertEqual(sprouting.summary, "「見る」「聴く」に芽が出ています。どの技へ伸ばすかを、選べます。")
        let (grown, _) = make([selfEntry("空", ["see"])], garden: Garden(learned: learned(["see-tomeru"])))
        XCTAssertEqual(grown.summary, "最近身についたのは「目を留める」。年輪は一。")
    }

    func testSectionsAndSearchKeepTheFog() async {
        let (model, _) = make([selfEntry("空", ["see"])])
        XCTAssertEqual(model.sections.count, 10)
        XCTAssertEqual(model.sections.first?.progress.rank, 1)
        XCTAssertEqual(model.sections.first?.isSprouting, true)
        XCTAssertEqual(model.sections.first?.nodes.first?.id, "see-tomeru", "浅い技から")
        model.query = "遠目"
        XCTAssertTrue(model.sections.isEmpty, "霧の中の技は探せない")
        model.query = "目"
        XCTAssertTrue(model.sections.allSatisfy { $0.nodes.allSatisfy { model.state(of: $0.id) != .unknown } })
        XCTAssertEqual(model.displayTitle(of: model.node("see-toome")!), "まだ霧の中の技")
    }

    func testLearningFromTheTreeAndCaptions() async throws {
        var changes = 0
        let trees = TreeSource(history: InMemoryHistoryRepository(selfEntries(3, ["see"]) + [selfEntry("温かいお茶", ["taste", "smell", "touch"], at: tokyoDate("2026-10-01", hour: 12))]), store: InMemoryGardenStore(), calendar: tokyoCalendar, now: { referenceDate })
        let model = TreeViewModel(source: trees, onStart: { _ in }, onChange: { changes += 1 })
        let now = referenceDate.addingTimeInterval(3600)
        XCTAssertEqual(model.caption(of: ExperienceTree.rootID("see")), "見る 二段 · 次の段まで あと3 · 芽 2")
        XCTAssertEqual(model.caption(of: ExperienceTree.rootID("move")), "「動く」の根 · 記すと経験が積もります")
        XCTAssertEqual(model.caption(of: "see-tomeru"), "伸ばせます · 「見る」の芽を使います")
        XCTAssertEqual(model.caption(of: "hear-sumasu"), "気配 · 聴く 一段")
        XCTAssertEqual(model.caption(of: "see-toome"), "霧の中 · 隣の技が身につくと、名前が見えてきます")
        XCTAssertEqual(model.caption(of: "flash-gokan", now: now, calendar: tokyoCalendar), "閃き · 7日前")

        XCTAssertTrue(model.learn("see-tomeru"))
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(model.caption(of: "see-tomeru"), "身についた技 · 守")
        XCTAssertEqual(model.caption(of: "see-toome"), "気配 · 見る 三段、「目を留める」が身についていること")
        XCTAssertTrue(model.learn("see-chigai"))
        XCTAssertEqual(model.caption(of: "see-hikari"), "条件はそろいました · 「見る」の段が上がると、芽が出ます")
        XCTAssertFalse(model.learn("see-hikari"))
        XCTAssertEqual(model.errorMessage, "「見る」の芽がありません。「見る」の段が上がると、芽が出ます。")
        XCTAssertEqual(model.practices(of: "see-tomeru").map(\.id), ["root-see", "work-desk-map"])
        XCTAssertTrue(model.practices(of: "see-toome").isEmpty == false, "気配の技の稽古は見られる")
        XCTAssertTrue(model.practices(of: "see-manazashi").isEmpty, "霧の中の技の稽古は見せない")
        XCTAssertEqual(model.practices(of: ExperienceTree.rootID("see")).first?.id, "root-see")
        XCTAssertEqual(model.path(to: "see-toome").map(\.id), [ExperienceTree.rootID("see"), "see-tomeru", "see-toome"])
        XCTAssertEqual(model.depth(of: "see-toome"), 2)
    }

    func testTiesWeavesAndPracticeStarts() async throws {
        var started: [Experience] = []
        let trees = TreeSource(history: InMemoryHistoryRepository([selfEntry("空と音", ["see", "hear"])]), store: InMemoryGardenStore(Garden(learned: learned(["see-tomeru", "hear-sumasu"]))), calendar: tokyoCalendar, now: { referenceDate })
        let model = TreeViewModel(source: trees, onStart: { started.append($0) })
        XCTAssertEqual(model.tieCandidates(for: "see-tomeru").map(\.id), ["hear-sumasu"])
        model.tie("see-tomeru", "hear-sumasu", note: "じっと")
        XCTAssertEqual(model.freshFlashes.map(\.id), ["flash-hibiki"])
        model.dismissFlashes()
        XCTAssertTrue(model.freshFlashes.isEmpty)
        XCTAssertEqual(model.tied(to: "hear-sumasu").first?.note, "じっと")
        let link = try XCTUnwrap(model.tree.ties(of: "see-tomeru").first)
        model.untie(link)
        XCTAssertTrue(model.tied(to: "hear-sumasu").isEmpty)

        XCTAssertNil(model.weave(WeaveDraft(title: "", ability: "", elements: [])))
        XCTAssertEqual(model.errorMessage, "技に名前をつけてください。")
        let woven = try XCTUnwrap(model.weave(WeaveDraft(title: "湯気の形", ability: "湯気で温度が分かる。", practice: "湯気を見送ってみる", elements: ["see"], growsFrom: "see-tomeru")))
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.draft(for: woven).growsFrom, "see-tomeru")
        XCTAssertNotNil(model.layout.position(of: woven.id), "編んだ技も樹に置かれる")
        XCTAssertEqual(woven.kindLabel, "編んだ技")
        XCTAssertTrue(model.revise(woven.id, with: WeaveDraft(title: "湯気の形", ability: "湯気で温度が分かる。", practice: "湯気を見送る", elements: ["see"])))
        model.startOwnPractice(of: try XCTUnwrap(model.node(woven.id)))
        XCTAssertEqual(started.last?.nodeID, woven.id)
        XCTAssertEqual(started.last?.invitation, "湯気を見送る")
        model.start(practice: TaikenContent.shared.experience("root-see")!, for: try XCTUnwrap(model.node("see-tomeru")))
        XCTAssertEqual(started.last?.nodeID, "root-see")
        XCTAssertEqual(started.last?.reason, "技「目を留める」の稽古です。")
        model.remove(woven.id)
        XCTAssertNil(model.node(woven.id))
    }

    func testRelationsOfANode() async {
        let (model, _) = make([selfEntry("空", ["see"])], garden: Garden(learned: learned(["see-tomeru"])))
        let opens = model.opens(from: "see-tomeru").map(\.node.id)
        XCTAssertTrue(opens.contains("see-toome"))
        XCTAssertTrue(opens.contains("cross-mitate"))
        XCTAssertEqual(model.leadsHere(to: "see-toome").map(\.node.id), ["see-tomeru"])
        XCTAssertEqual(model.opens(from: ExperienceTree.rootID("see")).map(\.node.id).prefix(3), ["see-tomeru", "see-chigai", "see-hikari"])
        XCTAssertEqual(TreeViewModel.relativeDay(referenceDate.addingTimeInterval(-5 * 86_400), now: referenceDate, calendar: tokyoCalendar), "5日前")
    }
}

final class VaultExportTests: XCTestCase {
    func testWritesPagesForElementsVisibleSkillsAndDays() throws {
        let own = selfEntry("窓の外をじっと眺めた", ["see"], at: tokyoDate("2026-10-07", hour: 12))
        var garden = Garden(learned: learned(["see-tomeru"]))
        garden.uses = [SkillUse(entryID: own.id, skills: ["see-tomeru"])]
        garden.ties = [Tie(between: "see-tomeru", and: "see-chigai", note: "見ること", createdAt: referenceDate)]
        let entries = [own, livedEntry("root-see", note: "水滴が地図みたい")]
        let tree = buildTree(entries, garden: garden)
        let files = VaultExporter.files(tree: tree, entries: entries, exportedAt: referenceDate, calendar: tokyoCalendar)
        let byPath = Dictionary(uniqueKeysWithValues: files.map { ($0.path, $0.contents) })

        XCTAssertTrue(try XCTUnwrap(byPath["はじめに.md"]).contains("[[見る]] — 一段 · 経験 2"))
        XCTAssertEqual(files.filter { $0.path.hasPrefix("要素/") }.count, 10)
        let page = try XCTUnwrap(byPath["技/目を留める.md"])
        XCTAssertTrue(page.contains("state: learned"))
        XCTAssertTrue(page.contains("mastery: 守"))
        XCTAssertTrue(page.contains("> 流れていく景色の中から、ひとつを選んで見ていられる。"))
        XCTAssertTrue(page.contains("- 伸びる → [[遠目]]"), "隣の技は名前が見える")
        XCTAssertTrue(page.contains("[[違いの目]] — 見ること"))
        XCTAssertTrue(page.contains("窓の外をじっと眺めた"))
        XCTAssertTrue(page.contains("「水滴が地図みたい」"))
        XCTAssertNil(byPath["技/隅々.md"], "霧の中の技は書き出さない")
        let day = try XCTUnwrap(byPath["体験帳/2026-10-07.md"])
        XCTAssertTrue(day.contains("窓の外をじっと眺めた — [[見る]] · 技: [[目を留める]]"))
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
        let files = VaultExporter.files(tree: buildTree(), entries: [], exportedAt: referenceDate, calendar: tokyoCalendar)
        try VaultExporter.write(files, to: directory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("要素/見る.md").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("技/目を留める.md").path))
    }
}
