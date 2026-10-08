import Foundation
import XCTest
@testable import TaikenCore

/// Home の一日の流れ: (求められたら) きっかけ → 体験中 → 記す (印) → しばらく通知を控える
@MainActor
final class ExperienceFlowTests: XCTestCase {
    private struct Rig {
        let model: HomeViewModel
        let presence: RecordingPresence
        let widgets: RecordingWidgetPublisher
        let service: StubService
    }

    private func make(_ h: Harness, service: StubService = StubService(), presenceEnabled: Bool = true) -> Rig {
        let presence = RecordingPresence()
        let widgets = RecordingWidgetPublisher()
        let model = HomeViewModel(
            service: service, assembler: h.assembler, history: h.history, cache: h.cache,
            presence: presence, widgets: widgets, presenceEnabled: { presenceEnabled }
        )
        return Rig(model: model, presence: presence, widgets: widgets, service: service)
    }

    func testTheWholeLoopOfADay() async {
        let h = Harness()
        let rig = make(h)

        await rig.model.refresh()
        XCTAssertEqual(rig.model.stage, .idle, "ホームの真ん中は、ふだんは自分の樹と「記す」")
        XCTAssertEqual(rig.service.experienceRequests.count, 0, "きっかけは、求められるまで作らない")
        XCTAssertEqual(rig.widgets.snapshots.last?.kind, .empty)

        await rig.model.requestPrompt()
        XCTAssertEqual(rig.model.stage, .proposal)
        XCTAssertEqual(rig.widgets.snapshots.last?.kind, .proposal)
        XCTAssertNotNil(rig.widgets.snapshots.last?.sealCharacter)

        rig.model.tryIt()
        XCTAssertEqual(rig.model.stage, .active)
        XCTAssertEqual(rig.presence.events.last, "begin:つまずきの観察")
        XCTAssertEqual(rig.widgets.snapshots.last?.kind, .active)
        XCTAssertEqual(rig.widgets.snapshots.last?.startedAt, referenceDate)

        h.clock.advance(1800)
        rig.model.finish(rating: .positive, note: "三回止まった")
        XCTAssertEqual(rig.model.stage, .completed)
        XCTAssertEqual(rig.model.completedEntry?.rating, .positive)
        XCTAssertEqual(rig.model.completedEntry?.note, "三回止まった")
        XCTAssertEqual(rig.presence.events.last, "end")
        XCTAssertEqual(rig.model.restingUntil, referenceDate.addingTimeInterval(1800 + 3600), "しばらく通知を控える")
        XCTAssertEqual(rig.widgets.snapshots.last?.kind, .resting)
        XCTAssertEqual(rig.model.todayEntries.count, 1)
        rig.model.dismissCompleted()
        XCTAssertEqual(rig.model.stage, .idle)

        // 閉じて開き直しても、きっかけは勝手に作らない
        let reopened = make(h, service: rig.service)
        await reopened.model.refresh()
        XCTAssertEqual(reopened.model.stage, .idle)
        XCTAssertEqual(reopened.model.restingUntil, referenceDate.addingTimeInterval(5400))
        h.clock.advance(3700)
        await reopened.model.refresh()
        XCTAssertNil(reopened.model.restingUntil)
        XCTAssertEqual(reopened.model.stage, .idle)
        XCTAssertEqual(rig.service.experienceRequests.count, 1)
    }

    func testNotNowKeepsHomeAsItIsAndQuietsNotifications() async {
        let h = Harness()
        let rig = make(h)
        await rig.model.generate()
        rig.model.notNow()
        XCTAssertEqual(rig.model.stage, .idle)
        XCTAssertEqual(h.cache.loadRestingUntil(), referenceDate.addingTimeInterval(3 * 3600), "通知はしばらく控える")

        await rig.model.refresh()
        XCTAssertEqual(rig.service.experienceRequests.count, 1, "断ったあとに、きっかけを作り直さない")

        await rig.model.requestPrompt()
        XCTAssertEqual(rig.model.stage, .proposal)
    }

    func testChoosingAMoodAsksAgainWithoutCountingAsRejection() async {
        let h = Harness()
        let service = StubService(experience: [.success(sampleResponse(title: "A")), .success(sampleResponse(title: "B")), .success(sampleResponse(title: "C"))])
        let rig = make(h, service: service)
        await rig.model.generate()

        await rig.model.choose(mood: .tired)
        XCTAssertEqual(rig.model.mood, .tired)
        XCTAssertEqual(service.experienceRequests.last?.mood, .tired)
        XCTAssertEqual(service.experienceRequests.last?.excludeTitles, ["A"])
        XCTAssertEqual(rig.model.proposal?.experience.title, "B")
        XCTAssertTrue(h.history.storage.isEmpty, "気分を変えただけでは「断った」ことにしない")

        // 同じ気分をもう一度選ぶと解除
        await rig.model.choose(mood: .tired)
        XCTAssertNil(rig.model.mood)
        XCTAssertNil(service.experienceRequests.last?.mood)
    }

    func testMoodAsksForANewPromptAfterDeclining() async {
        let h = Harness()
        let rig = make(h)
        await rig.model.generate()
        rig.model.notNow()
        await rig.model.choose(mood: .refresh)
        XCTAssertEqual(rig.model.stage, .proposal)
    }

    func testRequestsCarryTheTimeButNoSeason() async throws {
        let h = Harness()
        let rig = make(h)
        await rig.model.generate()
        XCTAssertEqual(rig.model.timeOfDay, .evening)
        let json = try jsonObject(APICoding.encoder().encode(XCTUnwrap(rig.service.experienceRequests.first)))
        XCTAssertNil(json["season"])
    }

    func testLockScreenPresenceFollowsTheSetting() async {
        let h = Harness()
        let rig = make(h, presenceEnabled: false)
        await rig.model.generate()
        rig.model.tryIt()
        XCTAssertFalse(rig.presence.events.contains { $0.hasPrefix("begin") })
        rig.model.presenceSettingChanged(enabled: true)
        XCTAssertEqual(rig.presence.events.last, "begin:つまずきの観察")
        rig.model.presenceSettingChanged(enabled: false)
        XCTAssertEqual(rig.presence.events.last, "end")
    }

    func testRefreshTidiesLeftoverPresence() async {
        let h = Harness()
        let rig = make(h)
        await rig.model.refresh()
        XCTAssertEqual(rig.presence.events.first, "sync:-")
    }

    func testAbandonEndsPresenceButDoesNotRest() async {
        let h = Harness()
        let rig = make(h)
        await rig.model.generate()
        rig.model.tryIt()
        rig.model.abandonActive()
        XCTAssertEqual(rig.model.stage, .idle)
        XCTAssertNil(rig.model.restingUntil)
        XCTAssertEqual(rig.presence.events.last, "end")
    }

    func testAdoptingFromChatStartsTheExperience() async {
        let h = Harness()
        let rig = make(h)
        await rig.model.generate()
        rig.model.notNow()
        rig.model.adopt(Experience(title: "一問だけの探偵", perspective: "p", invitation: "i", reason: "r", difficulty: .low, tags: ["question"], reflectionQuestion: "q？"))
        XCTAssertEqual(rig.model.stage, .active)
        XCTAssertEqual(rig.model.activeEntry?.reflectionQuestion, "q？")
        XCTAssertEqual(rig.presence.events.last, "begin:一問だけの探偵")
    }

    func testEngagementForTheMorningLetter() async {
        let h = Harness()
        let rig = make(h)
        XCTAssertFalse(rig.model.engagedToday)
        await rig.model.generate()
        XCTAssertTrue(rig.model.engagedToday)
        h.clock.advance(86_400)
        await rig.model.refresh()
        XCTAssertNil(rig.model.proposal, "前の日のきっかけは、黙って下げる")
        XCTAssertFalse(rig.model.engagedToday)
        rig.model.record(LivedDraft(text: "朝の光", elements: ["see"]))
        XCTAssertTrue(rig.model.engagedToday, "自分で記したことも、その日に触れたことになる")
        await rig.model.generate()
        rig.model.notNow()
        XCTAssertTrue(rig.model.engagedToday, "断ったことも、その日に触れたことになる")
    }

    func testDataDeletionClearsTheDay() async {
        let h = Harness()
        let rig = make(h)
        await rig.model.generate()
        rig.model.tryIt()
        rig.model.finish(rating: .neutral)
        rig.model.resetAfterDataDeletion()
        XCTAssertNil(rig.model.restingUntil)
        XCTAssertNil(rig.model.completedEntry)
        XCTAssertNil(h.cache.loadRestingUntil())
        XCTAssertEqual(rig.model.stage, .idle)
        XCTAssertEqual(rig.widgets.snapshots.last?.kind, .empty)
    }

    func testReflectionQuestionTravelsIntoTheJournal() async {
        let h = Harness()
        var response = sampleResponse()
        response = ExperienceResponse(
            situation: response.situation, detectedActions: response.detectedActions, possibleObligations: [], experienceOpportunities: [],
            isObligation: true, confidence: 0.8,
            experience: Experience(title: "つまずきの観察", perspective: "p", invitation: "i", reason: "r", difficulty: .low, tags: ["observation"], reflectionQuestion: "何が引っかかっていましたか？"),
            shouldNotify: false, notification: nil, source: .ai
        )
        let rig = make(h, service: StubService(experience: [.success(response)]))
        await rig.model.generate()
        rig.model.tryIt()
        XCTAssertEqual(rig.model.activeEntry?.reflectionQuestion, "何が引っかかっていましたか？")
        // ライブラリと同じ体験なので、樹が無くても要素 (考える) と印が付く
        XCTAssertEqual(rig.model.activeEntry?.elements, ["think"])
        XCTAssertEqual(rig.model.activeEntry?.sealCharacter, "考")
        rig.model.finish(rating: .positive)
        XCTAssertEqual(h.history.storage.first?.reflectionQuestion, "何が引っかかっていましたか？")
    }
}
