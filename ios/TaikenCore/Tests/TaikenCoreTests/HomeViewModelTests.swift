import Foundation
import XCTest
@testable import TaikenCore

@MainActor
final class HomeViewModelTests: XCTestCase {
    private func make(_ h: Harness, service: StubService = StubService()) -> HomeViewModel {
        HomeViewModel(service: service, assembler: h.assembler, history: h.history, cache: h.cache)
    }

    func testGeneratesOnFirstRefreshAndCaches() async {
        let h = Harness()
        let model = make(h)
        await model.refresh()
        XCTAssertEqual(model.phase, .ready)
        XCTAssertEqual(model.proposal?.experience.title, "つまずきの観察")
        XCTAssertNil(model.notice)
        XCTAssertEqual(h.cache.load()?.generatedAt, referenceDate)
        XCTAssertEqual(model.calendarAccess, .granted)
    }

    func testDoesNotCallAIAgainWhileFresh() async {
        let h = Harness()
        let service = StubService()
        let model = make(h, service: service)
        await model.refresh()
        h.clock.advance(10 * 60)
        await model.refresh()
        XCTAssertEqual(service.experienceRequests.count, 1)
        h.clock.advance(31 * 60)
        await model.refresh()
        XCTAssertEqual(service.experienceRequests.count, 2)
    }

    /// 通知から開いたときなど、保存された当日の提案をそのまま表示する
    func testShowsCachedProposalFromSameDayWithoutCallingAI() async {
        let h = Harness()
        h.cache.save(CachedProposal(generatedAt: referenceDate.addingTimeInterval(-60), response: sampleResponse(title: "通知の体験")))
        let service = StubService()
        let model = make(h, service: service)
        await model.refresh()
        XCTAssertEqual(model.proposal?.experience.title, "通知の体験")
        XCTAssertEqual(service.experienceRequests.count, 0)
    }

    func testIgnoresCacheFromAnotherDay() async {
        let h = Harness()
        h.cache.save(CachedProposal(generatedAt: referenceDate.addingTimeInterval(-86_400), response: sampleResponse(title: "昨日の体験")))
        let model = make(h)
        await model.refresh()
        XCTAssertEqual(model.proposal?.experience.title, "つまずきの観察")
    }

    func testFallsBackToLocalWhenOffline() async {
        let h = Harness()
        let model = make(h, service: StubService(experience: [.failure(AppError.offline)]))
        await model.generate()
        XCTAssertEqual(model.proposal?.source, .local)
        XCTAssertEqual(model.notice?.kind, .offline)
        XCTAssertTrue(model.notice?.message.contains("ネットワーク") == true)
    }

    func testNoticeExplainsServerFallback() async {
        var r = sampleResponse(source: .fallback)
        r = ExperienceResponse(situation: r.situation, detectedActions: [], possibleObligations: [], experienceOpportunities: [], isObligation: false, confidence: 0.5, experience: r.experience, shouldNotify: false, notification: nil, source: .fallback, fallbackReason: .budgetExceeded)
        XCTAssertTrue(HomeViewModel.notice(for: r)?.message.contains("上限") == true)
        XCTAssertEqual(HomeViewModel.notice(for: sampleResponse(source: .local))?.kind, .info)
        XCTAssertNil(HomeViewModel.notice(for: sampleResponse(source: .ai)))
    }

    func testShowAnotherExcludesPreviousAndRecordsSkip() async {
        let h = Harness()
        let service = StubService(experience: [.success(sampleResponse(title: "A")), .success(sampleResponse(title: "B"))])
        let model = make(h, service: service)
        await model.generate()
        await model.showAnother()
        XCTAssertEqual(model.proposal?.experience.title, "B")
        XCTAssertEqual(service.experienceRequests.last?.excludeTitles, ["A"])
        XCTAssertEqual(h.history.storage.map(\.status), [.skipped])
    }

    func testTryAndFinishRecordsRatingAndNote() async {
        let h = Harness()
        let model = make(h)
        await model.generate()
        model.tryIt()
        XCTAssertNotNil(model.activeEntry)
        XCTAssertNil(model.proposal)
        XCTAssertNil(h.cache.load())
        XCTAssertEqual(model.todayEntries.count, 1)

        // 体験中は開き直してもAIを呼ばない
        await model.refresh()
        XCTAssertNil(model.proposal)

        h.clock.advance(1800)
        model.finish(rating: .positive, note: "  意外と楽しかった  ")
        XCTAssertNil(model.activeEntry)
        let entry = h.history.storage[0]
        XCTAssertEqual(entry.status, .completed)
        XCTAssertEqual(entry.rating, .positive)
        XCTAssertEqual(entry.note, "意外と楽しかった")
        XCTAssertEqual(entry.finishedAt, referenceDate.addingTimeInterval(1800))
    }

    func testNotNowRecordsDecline() async {
        let h = Harness()
        let model = make(h)
        await model.generate()
        model.notNow()
        XCTAssertNil(model.proposal)
        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(h.history.storage.first?.reaction, .declined)
    }

    func testAbandonActive() async {
        let h = Harness()
        let model = make(h)
        await model.generate()
        model.tryIt()
        model.abandonActive()
        XCTAssertNil(model.activeEntry)
        XCTAssertEqual(h.history.storage.first?.status, .declined)
        XCTAssertTrue(model.todayEntries.isEmpty)
    }

    func testAdoptFromChatReplacesActive() async {
        let h = Harness()
        let model = make(h)
        await model.generate()
        model.tryIt()
        model.adopt(Experience(title: "チャットの体験", perspective: "p", invitation: "i", reason: "r", difficulty: .low, tags: []))
        XCTAssertEqual(model.activeEntry?.title, "チャットの体験")
        XCTAssertEqual(h.history.storage.filter { $0.status == .active }.count, 1)
    }

    func testStorageFailureShowsNotice() async {
        let h = Harness()
        let model = make(h)
        await model.generate()
        h.history.failWrites = true
        model.tryIt()
        XCTAssertEqual(model.notice?.kind, .error)
    }

    func testResetAfterDataDeletion() async {
        let h = Harness()
        let model = make(h)
        await model.generate()
        model.resetAfterDataDeletion()
        XCTAssertNil(model.proposal)
        XCTAssertNil(h.cache.load())
        XCTAssertEqual(model.phase, .idle)
    }
}

@MainActor
final class ChatViewModelTests: XCTestCase {
    private func reply(_ text: String = "返事", suggestion: Experience? = nil, care: Bool = false) -> ChatResponse {
        ChatResponse(reply: text, observations: [], suggestExperience: suggestion != nil, experience: suggestion, needsCare: care, source: .ai)
    }

    private let suggestion = Experience(title: "一問だけの探偵", perspective: "p", invitation: "i", reason: "r", difficulty: .low, tags: [])

    func testSendsConversationAndRemembersUtterance() async {
        let h = Harness()
        let service = StubService(chat: [.success(reply())])
        let model = ChatViewModel(service: service, assembler: h.assembler, history: h.history) { _ in }
        model.draft = "  今から宿題する  "
        XCTAssertTrue(model.canSend)
        await model.send()
        XCTAssertEqual(model.messages.map(\.text), [ChatViewModel.greeting, "今から宿題する", "返事"])
        XCTAssertEqual(service.chatRequests.first?.messages.map(\.role), [.assistant, .user])
        XCTAssertEqual(h.memory.recent(now: referenceDate), ["今から宿題する"])
        XCTAssertEqual(model.draft, "")
    }

    func testAdoptAndDismissSuggestion() async {
        let h = Harness()
        var adopted: [String] = []
        let model = ChatViewModel(service: StubService(chat: [.success(reply(suggestion: suggestion))]), assembler: h.assembler, history: h.history) { adopted.append($0.title) }
        model.draft = "宿題"
        await model.send()
        let message = model.messages.last!
        XCTAssertEqual(message.suggestion?.title, "一問だけの探偵")
        model.adopt(message)
        model.adopt(message) // 二度押しは無視
        XCTAssertEqual(adopted, ["一問だけの探偵"])
        XCTAssertTrue(model.messages.first { $0.id == message.id }!.suggestionHandled)

        model.draft = "もう一回"
        await model.send()
        model.dismissSuggestion(model.messages.last!)
        XCTAssertEqual(h.history.storage.first?.status, .declined)
    }

    func testCareResponseShowsResources() async {
        let h = Harness()
        let model = ChatViewModel(service: StubService(chat: [.success(reply("話してくれてありがとう", care: true))]), assembler: h.assembler, history: h.history) { _ in }
        model.draft = "つらい"
        await model.send()
        XCTAssertTrue(model.showsCareResources)
        XCTAssertNil(model.messages.last?.suggestion)
    }

    func testFailureMarksMessageAndRetryWorks() async {
        let h = Harness()
        let service = StubService(chat: [.failure(AppError.offline), .success(reply("届きました"))])
        let model = ChatViewModel(service: service, assembler: h.assembler, history: h.history) { _ in }
        model.draft = "暇"
        await model.send()
        XCTAssertTrue(model.messages.last!.failed)
        XCTAssertNotNil(model.errorMessage)

        await model.retry(model.messages.last!)
        XCTAssertEqual(model.messages.map(\.text), [ChatViewModel.greeting, "暇", "届きました"])
        XCTAssertNil(model.errorMessage)
        // 失敗した発言を二重に送っていない
        XCTAssertEqual(service.chatRequests.last?.messages.filter { $0.text == "暇" }.count, 1)
    }

    func testReset() async {
        let h = Harness()
        let model = ChatViewModel(service: StubService(chat: [.success(reply())]), assembler: h.assembler, history: h.history) { _ in }
        model.draft = "a"
        await model.send()
        model.reset()
        XCTAssertEqual(model.messages.count, 1)
    }
}
