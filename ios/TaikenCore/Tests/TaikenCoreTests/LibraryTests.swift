import Foundation
import XCTest
@testable import TaikenCore

final class ContentTests: XCTestCase {
    /// アプリに入っている内容が contracts/content.ja.json (Backend と共通の正) と同じ
    func testBundledContentMatchesContract() throws {
        let bundled = try Data(contentsOf: XCTUnwrap(TaikenContent.resourceURL))
        let canonical = try Fixtures.data("content.ja")
        XCTAssertEqual(bundled, canonical, "contracts/tools/sync.sh で contracts/content.ja.json をコピーしてください")
    }

    func testContentIsWellFormedAndSafe() {
        let content = TaikenContent.shared
        XCTAssertTrue(content.isWellFormed)
        XCTAssertEqual(content.version, 2)
        XCTAssertGreaterThanOrEqual(content.experiences.count, 90)
        XCTAssertEqual(Set(content.experiences.map(\.id)).count, content.experiences.count)
        XCTAssertEqual(Set(content.experiences.map(\.title)).count, content.experiences.count)

        let themes = Set(content.themes.map(\.id))
        let times = Set(TimeOfDay.allCases.map(\.rawValue))
        let elements = Set(content.elements.map(\.id))
        let ids = Set(content.experiences.map(\.id))
        for item in content.experiences {
            XCTAssertTrue(item.invitation.contains("ませんか？"), "\(item.id): 誘いかけの形にする")
            XCTAssertTrue(item.reflectionQuestion.hasSuffix("？"), item.id)
            XCTAssertLessThanOrEqual(item.reflectionQuestion.count, 30, item.id)
            XCTAssertTrue(item.tags.allSatisfy { ExperienceTag.labels[$0] != nil }, item.id)
            XCTAssertTrue((1...4).contains(item.tags.count), item.id)
            XCTAssertFalse(item.themes.isEmpty, item.id)
            XCTAssertTrue(Set(item.themes).isSubset(of: themes), item.id)
            XCTAssertTrue(item.moods.allSatisfy { Mood(rawValue: $0) != nil }, item.id)
            XCTAssertTrue(Set(item.times).isSubset(of: times), item.id)
            XCTAssertTrue(["low", "medium"].contains(item.effort), item.id)
            XCTAssertTrue((1...3).contains(item.elements.count), item.id)
            XCTAssertTrue(Set(item.elements).isSubset(of: elements), item.id)
            for link in item.opens {
                XCTAssertTrue(ids.contains(link.to), "\(item.id) → \(link.to)")
                XCTAssertNotEqual(link.to, item.id)
            }
            for word in ["季節", "節気", "七十二候"] {
                XCTAssertFalse((item.title + item.invitation + item.perspective).contains(word), "\(item.id): 季節の言葉は使わない")
            }
            let experience = Experience(title: item.title, perspective: item.perspective, invitation: item.invitation, reason: "", difficulty: .low, tags: item.tags, reflectionQuestion: item.reflectionQuestion)
            XCTAssertNil(SafetyCheck.issue(in: experience), "\(item.id) は安全確認に引っかからないこと")
        }
    }

    /// 10の要素それぞれに、ひと文字の印と根がある
    func testElementsHaveGlyphsAndRoots() {
        let content = TaikenContent.shared
        XCTAssertEqual(content.elements.map(\.glyph), ["見", "聴", "香", "味", "触", "動", "休", "考", "言", "人"])
        XCTAssertEqual(content.elements.map(\.label), ["見る", "聴く", "嗅ぐ", "味わう", "触れる", "動く", "休む", "考える", "言葉にする", "人と"])
        for element in content.elements {
            let root = content.experience(element.root)
            XCTAssertNotNil(root, element.id)
            XCTAssertEqual(root?.elements.first, element.id, "根の主な要素は、その要素")
            XCTAssertTrue(content.isRoot(element.root))
            XCTAssertFalse(element.keywords.isEmpty)
            XCTAssertEqual(element.glyph.count, 1)
        }
    }

    func testMoodLabelsMatchApp() {
        let labels = Dictionary(uniqueKeysWithValues: TaikenContent.shared.moods.map { ($0.id, $0.label) })
        for mood in Mood.allCases {
            XCTAssertEqual(labels[mood.rawValue], mood.label)
        }
    }

    func testMinimalContentKeepsTheAppRunning() {
        XCTAssertTrue(TaikenContent.minimal.isWellFormed)
        let choice = LibrarySelector(content: .minimal).choose(LibrarySelector.Input(day: 1, timeOfDay: .night))
        XCTAssertEqual(choice.experience.id, "daily-difference", "時間帯が合わなくても、何かは選ぶ")
        XCTAssertEqual(TreeBuilder.build(content: .minimal, garden: .empty, entries: []).context(entries: []).buds, ["daily-difference"])
    }
}

final class LibrarySelectorTests: XCTestCase {
    private struct Case: Decodable {
        let name: String
        let date: String
        let timeOfDay: String
        let eventTitle: String?
        let messages: [String]
        let mood: String?
        let feedback: [FeedbackSignal]
        let recentTitles: [String]
        let excludeTitles: [String]
        let buds: [String]
        let expected: String
    }

    private struct CaseFile: Decodable {
        let cases: [Case]
    }

    /// contracts/selection_cases.json (Backend と共通) と同じ体験を選ぶ
    func testMatchesSharedSelectionCases() throws {
        let file = try APICoding.decoder().decode(CaseFile.self, from: Fixtures.data("selection_cases"))
        XCTAssertGreaterThanOrEqual(file.cases.count, 10)
        let selector = LibrarySelector()
        for item in file.cases {
            let input = LibrarySelector.Input(
                day: dayNumber(item.date),
                timeOfDay: try XCTUnwrap(TimeOfDay(rawValue: item.timeOfDay)),
                eventTitle: item.eventTitle,
                messages: item.messages,
                mood: item.mood.flatMap(Mood.init(rawValue:)),
                feedback: item.feedback,
                recentTitles: Set(item.recentTitles),
                excludeTitles: Set(item.excludeTitles),
                buds: Set(item.buds)
            )
            XCTAssertEqual(selector.choose(input).experience.id, item.expected, item.name)
        }
    }

    func testHashAndDayNumberMatchReference() {
        XCTAssertEqual(LibrarySelector.fnv1a("a"), 0xE40C_292C)
        XCTAssertEqual(LibrarySelector.fnv1a(""), 0x811C_9DC5)
        XCTAssertEqual(dayNumber("2026-10-08"), 20_734)
        // 日付はその土地の暦で数える (東京の 0:30 は UTC ではまだ前日)
        XCTAssertEqual(LibrarySelector.dayNumber(of: tokyoDate("2026-10-09", hour: 0, minute: 30), calendar: tokyoCalendar), 20_735)
        XCTAssertEqual(LibrarySelector.dayNumber(of: tokyoDate("2026-10-08", hour: 23, minute: 30), calendar: tokyoCalendar), 20_734)
        let jitter = LibrarySelector.jitter(id: "rest-far", day: 20_734)
        XCTAssertTrue((0..<0.9).contains(jitter))
    }

    func testDetectsThemesAndMoodFromWords() {
        let selector = LibrarySelector()
        XCTAssertEqual(selector.detectThemes(["これから会議。ちょっと疲れた"]), ["work"])
        XCTAssertEqual(selector.detectMood(["これから会議。ちょっと疲れた"]), .tired)
        XCTAssertEqual(selector.detectMood(["暇だなあ"]), .bored)
        XCTAssertEqual(selector.detectThemes(["友達と食事会"]), ["meal", "people"])
        XCTAssertNil(selector.detectMood(["こんにちは"]))
    }

    func testExcludedOnlyWhenSomethingElseExists() {
        let selector = LibrarySelector()
        let base = LibrarySelector.Input(day: 20_734, timeOfDay: .evening)
        let first = selector.choose(base).experience
        var excluded = base
        excluded.excludeTitles = [first.title]
        XCTAssertNotEqual(selector.choose(excluded).experience.id, first.id)
        // 同じ日・同じ状況なら同じ体験 (開き直すたびに変わらない)
        XCTAssertEqual(selector.choose(base).experience.id, first.id)
    }

    /// 手がかりの無い日は、樹の芽から選ぶ。予定や気分に合う体験は、芽より前に出る
    func testBudsLeadOnlyWhenNothingElseDoes() {
        let selector = LibrarySelector()
        // 場面を選ばない芽 (食事の場面だけの芽は、食事の予定が無ければ後ろに回る)
        let buds: Set<String> = ["hear-far", "hear-music-one", "hear-silence", "root-touch", "taste-water"]
        var picked = Set<String>()
        for day in 20_700..<20_760 {
            let quiet = selector.choose(LibrarySelector.Input(day: day, timeOfDay: .daytime, buds: buds))
            XCTAssertTrue(quiet.isBud, "手がかりが無ければ芽から: \(quiet.experience.id)")
            picked.insert(quiet.experience.id)
            let withEvent = selector.choose(LibrarySelector.Input(day: day, timeOfDay: .daytime, eventTitle: "数学の課題", buds: buds))
            XCTAssertTrue(withEvent.experience.themes.contains("study"), "予定に合う体験が先: \(withEvent.experience.id)")
            let withMood = selector.choose(LibrarySelector.Input(day: day, timeOfDay: .daytime, mood: .bored, buds: buds))
            XCTAssertTrue(withMood.experience.moods.contains("bored"), "気分に合う体験が先: \(withMood.experience.id)")
        }
        XCTAssertGreaterThan(picked.count, 2, "芽の中でも、日によって顔ぶれが変わる")

        // 特定の場面向けの芽は、その場面が無ければ後ろに回る
        let mealBuds: Set<String> = ["meal-texture", "taste-last-bite", "taste-water"]
        let quiet = selector.choose(LibrarySelector.Input(day: 20_734, timeOfDay: .daytime, buds: mealBuds))
        XCTAssertEqual(quiet.experience.id, "taste-water")
        let atMeal = selector.choose(LibrarySelector.Input(day: 20_734, timeOfDay: .daytime, eventTitle: "ランチ", buds: mealBuds))
        XCTAssertTrue(["meal-texture", "taste-last-bite"].contains(atMeal.experience.id), atMeal.experience.id)
    }

    func testRespectsTimeOfDay() {
        let selector = LibrarySelector()
        for day in 20_700..<20_760 {
            let night = selector.choose(LibrarySelector.Input(day: day, timeOfDay: .lateNight)).experience
            XCTAssertTrue(night.times.isEmpty || night.times.contains("lateNight"), night.id)
        }
    }
}

final class LocalExperienceServiceTests: XCTestCase {
    private let service = LocalExperienceService()

    func testUsesTheCalendarAndExplainsHonestly() async throws {
        let request = experienceRequest(calendar: [calendarItem("数学の課題", at: referenceDate.addingTimeInterval(3600))])
        let response = try await service.generateExperience(request)
        XCTAssertEqual(response.source, .local)
        let picked = try XCTUnwrap(TaikenContent.shared.experiences.first { $0.title == response.experience.title })
        XCTAssertTrue(picked.themes.contains("study"))
        XCTAssertTrue(response.experience.reason.contains("数学の課題"))
        XCTAssertNotNil(response.experience.reflectionQuestion)
        XCTAssertEqual(response.situation.observations.first?.basis, .calendar)
        XCTAssertEqual(response.situation.observations.first?.text, "19:00から「数学の課題」の予定がある")
        XCTAssertEqual(response.situation.summary, "「数学の課題」が控えている夕方。")
        XCTAssertTrue(response.isObligation)
        XCTAssertFalse(response.shouldNotify)
    }

    func testChosenMoodShapesTheChoiceAndIsStatedAsFact() async throws {
        let response = try await service.generateExperience(experienceRequest(mood: .tired))
        let picked = try XCTUnwrap(TaikenContent.shared.experiences.first { $0.title == response.experience.title })
        XCTAssertTrue(picked.moods.contains("tired"))
        XCTAssertEqual(picked.effort, "low")
        XCTAssertTrue(response.experience.reason.hasPrefix("「疲れぎみ」とのことなので"))
        XCTAssertTrue(response.situation.observations.contains { $0.basis == .stated && $0.text.contains("疲れぎみ") })
    }

    func testPlainEveningWithoutAnything() async throws {
        let response = try await service.generateExperience(experienceRequest())
        XCTAssertEqual(response.experience.nodeID, "hear-far")
        XCTAssertEqual(response.experience.reason, "特別な予定がなくても、いつもの時間の中に体験は見つけられます。")
        XCTAssertEqual(response.situation.summary, "目立った予定は見当たらない夕方。")
        XCTAssertEqual(response.confidence, 0.4)
        XCTAssertEqual(response.experience.elements, ["hear"])
        XCTAssertNil(response.experience.growsFrom)
    }

    /// 技の稽古から選んだら、そう正直に書く (どの技かは、霧を明かさないよう端末の樹がカードに添える)
    func testGrowsFromTheLivedExperience() async throws {
        let tree = TreeContext(
            lived: [TreeContext.LivedNode(id: "meal-first-bite", title: "ひと口目の観察", elements: ["taste"])],
            buds: ["meal-texture", "taste-last-bite", "taste-water", "meal-screen-down"]
        )
        let response = try await service.generateExperience(experienceRequest(at: tokyoDate("2026-10-08", hour: 13), tree: tree))
        let id = try XCTUnwrap(response.experience.nodeID)
        XCTAssertTrue(tree.buds.contains(id), id)
        XCTAssertEqual(response.experience.growsFrom, "meal-first-bite")
        XCTAssertEqual(response.experience.reason, "あなたの技の樹にある、技の稽古になる体験です。")
        XCTAssertTrue(response.situation.observations.contains { $0.text == "体験帳に「ひと口目の観察」が記されている" })
    }

    /// はじめての人には、根 (いちばん小さなかたち) から
    func testNewcomersStartFromARoot() async throws {
        let roots = TaikenContent.shared.elements.map(\.root)
        let response = try await service.generateExperience(experienceRequest(at: tokyoDate("2026-10-08", hour: 13), tree: TreeContext(lived: [], buds: roots)))
        let id = try XCTUnwrap(response.experience.nodeID)
        XCTAssertTrue(TaikenContent.shared.isRoot(id), id)
        XCTAssertTrue(response.experience.reason.hasSuffix("の、いちばん小さなかたちの体験です。"), response.experience.reason)
    }

    func testAnotherProposalIsDifferent() async throws {
        let first = try await service.generateExperience(experienceRequest())
        let second = try await service.generateExperience(experienceRequest(exclude: [first.experience.title]))
        XCTAssertNotEqual(first.experience.title, second.experience.title)
    }

    func testDoesNotGuessHiddenTitles() async throws {
        let response = try await service.generateExperience(experienceRequest(calendar: [calendarItem(nil, at: referenceDate.addingTimeInterval(1800))]))
        XCTAssertEqual(response.situation.observations.first?.text, "18:30から内容不明の予定がある")
        XCTAssertEqual(response.situation.summary, "予定が控えている夕方。")
    }

    func testTiredWordsInConversationAreUsedGently() async throws {
        let response = try await service.generateExperience(experienceRequest(messages: ["今日は疲れた"]))
        XCTAssertTrue(response.situation.observations.contains { $0.basis == .inferred })
        let picked = try XCTUnwrap(TaikenContent.shared.experiences.first { $0.title == response.experience.title })
        XCTAssertEqual(picked.effort, "low")
    }

    func testStatusIsNotConfigured() async {
        do {
            _ = try await service.status()
            XCTFail("local has no server")
        } catch {
            XCTAssertEqual(error as? AppError, .notConfigured)
        }
        XCTAssertTrue(service.isLocal)
    }
}

final class LocalCompanionTests: XCTestCase {
    private func chat(_ text: String, calendar: [CalendarItem] = []) async throws -> ChatResponse {
        try await LocalExperienceService().chat(ChatRequest(
            currentTime: APICoding.timestamp(referenceDate, timeZone: tokyo), timeZone: "Asia/Tokyo", locale: "ja-JP",
            messages: [ChatTurn(role: .assistant, text: "こんばんは"), ChatTurn(role: .user, text: text)],
            calendarContext: calendar, currentExperience: nil
        ))
    }

    func testCareSignalsGetSupportInsteadOfSuggestions() async throws {
        let response = try await chat("もう消えたい")
        XCTAssertTrue(response.needsCare)
        XCTAssertNil(response.experience)
        XCTAssertFalse(response.suggestExperience)
        XCTAssertEqual(response.reply, CareMessage.reply)
    }

    func testTirednessAloneIsJustListenedTo() async throws {
        let response = try await chat("疲れた")
        XCTAssertFalse(response.suggestExperience)
        XCTAssertTrue(LocalCompanion.tiredReplies.contains(response.reply))
        XCTAssertEqual(response.observations.first?.basis, .stated)
    }

    func testAskingForSomethingGetsOneSuggestion() async throws {
        let response = try await chat("暇だな、何かある？")
        XCTAssertTrue(response.suggestExperience)
        XCTAssertNotNil(response.experience?.reflectionQuestion)
        XCTAssertTrue(LocalCompanion.ideaReplies.contains(response.reply))
        XCTAssertEqual(response.source, .local)
    }

    func testTopicWordsPickAMatchingExperience() async throws {
        let response = try await chat("これから勉強する")
        let title = try XCTUnwrap(response.experience?.title)
        let picked = try XCTUnwrap(TaikenContent.shared.experiences.first { $0.title == title })
        XCTAssertTrue(picked.themes.contains("study"))
    }

    func testOrdinaryTalkGetsAQuestionBack() async throws {
        let response = try await chat("今日は晴れてた")
        XCTAssertFalse(response.suggestExperience)
        XCTAssertTrue(LocalCompanion.listeningReplies.contains(response.reply))
    }
}

final class SafetyCheckTests: XCTestCase {
    private let base = Experience(title: "t", perspective: "p", invitation: "i", reason: "r", difficulty: .low, tags: [])

    private func with(invitation: String? = nil, question: String? = nil) -> Experience {
        Experience(title: base.title, perspective: base.perspective, invitation: invitation ?? base.invitation, reason: "", difficulty: .low, tags: [], reflectionQuestion: question)
    }

    func testDetectsRiskyProposalsLikeTheBackend() {
        XCTAssertEqual(SafetyCheck.issue(in: with(invitation: "今夜は徹夜でやってみませんか？")), "睡眠を削る")
        XCTAssertEqual(SafetyCheck.issue(in: with(invitation: "朝食を抜いてみませんか？")), "食事を抜く")
        XCTAssertEqual(SafetyCheck.issue(in: with(invitation: "運転しながら観察してみませんか？")), "移動中の危険行為")
        XCTAssertEqual(SafetyCheck.issue(in: with(question: "限界まで走れましたか？")), "心身への過度な負担")
        XCTAssertNil(SafetyCheck.issue(in: base))
    }

    func testDetectsCareSignalsButNotEverydayWords() {
        XCTAssertTrue(SafetyCheck.needsCare(["もう消えたい"]))
        XCTAssertTrue(SafetyCheck.needsCare(["リスカしそう"]))
        // Backend と同じく大文字小文字を区別しない
        XCTAssertTrue(SafetyCheck.needsCare(["ODしそう"]))
        XCTAssertTrue(SafetyCheck.needsCare(["odしそう"]))
        XCTAssertFalse(SafetyCheck.needsCare(["今日は疲れた", "宿題が面倒"]))
    }
}

final class SafeguardedServiceTests: XCTestCase {
    private let unsafe = ExperienceResponse(
        situation: Situation(summary: "s", observations: []), detectedActions: [], possibleObligations: [],
        experienceOpportunities: [], isObligation: false, confidence: 0.8,
        experience: Experience(title: "夜ふかし", perspective: "p", invitation: "今夜は徹夜で読んでみませんか？", reason: "r", difficulty: .low, tags: []),
        shouldNotify: false, notification: nil, source: .onDevice
    )

    func testPassesSafeResultsThrough() async throws {
        let guarded = SafeguardedExperienceService(primary: StubService(experience: [.success(sampleResponse(source: .onDevice))]))
        let response = try await guarded.generateExperience(experienceRequest())
        XCTAssertEqual(response.source, .onDevice)
    }

    func testFallsBackOnFailureAndOnUnsafeOutput() async throws {
        let failing = SafeguardedExperienceService(primary: StubService(experience: [.failure(AppError.invalidResponse)]))
        let fromFailure = try await failing.generateExperience(experienceRequest())
        XCTAssertEqual(fromFailure.source, .local)

        let risky = SafeguardedExperienceService(primary: StubService(experience: [.success(unsafe)]))
        let fromUnsafe = try await risky.generateExperience(experienceRequest())
        XCTAssertEqual(fromUnsafe.source, .local)
        XCTAssertNil(SafetyCheck.issue(in: fromUnsafe.experience))
    }

    func testCareConversationsNeverReachTheModel() async throws {
        let primary = StubService(chat: [.success(ChatResponse(reply: "x", observations: [], suggestExperience: false, experience: nil, source: .onDevice))])
        let guarded = SafeguardedExperienceService(primary: primary)
        let response = try await guarded.chat(ChatRequest(
            currentTime: APICoding.timestamp(referenceDate, timeZone: tokyo), timeZone: "Asia/Tokyo", locale: "ja-JP",
            messages: [ChatTurn(role: .user, text: "死にたい")], calendarContext: [], currentExperience: nil
        ))
        XCTAssertTrue(response.needsCare)
        XCTAssertTrue(primary.chatRequests.isEmpty)
    }

    func testDropsUnsafeChatSuggestions() async throws {
        let reply = ChatResponse(reply: "どうでしょう", observations: [], suggestExperience: true, experience: unsafe.experience, source: .onDevice)
        let guarded = SafeguardedExperienceService(primary: StubService(chat: [.success(reply)]))
        let response = try await guarded.chat(ChatRequest(
            currentTime: APICoding.timestamp(referenceDate, timeZone: tokyo), timeZone: "Asia/Tokyo", locale: "ja-JP",
            messages: [ChatTurn(role: .user, text: "ひま")], calendarContext: [], currentExperience: nil
        ))
        XCTAssertEqual(response.reply, "どうでしょう")
        XCTAssertNil(response.experience)
        XCTAssertFalse(response.suggestExperience)
    }

    func testCancellationIsNotSwallowed() async {
        let guarded = SafeguardedExperienceService(primary: StubService(experience: [.failure(CancellationError())]))
        do {
            _ = try await guarded.generateExperience(experienceRequest())
            XCTFail("should rethrow")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }
}
