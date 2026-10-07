import Foundation
import XCTest
@testable import TaikenCore

final class ContextBuilderTests: XCTestCase {
    private let builder = makeBuilder()
    private let now = referenceDate
    private let allowAll = ConsentSnapshot(useCalendar: true, sendEventTitles: true, useChatContext: true, useHistory: true, useLocation: true, allowWebSearch: true)

    private func event(_ title: String?, startOffsetHours: Double, hours: Double = 1) -> CalendarEventSnapshot {
        let start = now.addingTimeInterval(startOffsetHours * 3600)
        return CalendarEventSnapshot(title: title, start: start, end: start.addingTimeInterval(hours * 3600), isAllDay: false)
    }

    func testTimestampHasLocalOffset() {
        XCTAssertEqual(APICoding.timestamp(now, timeZone: tokyo), "2026-10-08T18:00:00+09:00")
        XCTAssertEqual(APICoding.dayString(now, timeZone: tokyo), "2026-10-08")
    }

    func testDropsFinishedEventsAndSorts() {
        let items = builder.calendarItems([event("後", startOffsetHours: 3), event("終わった", startOffsetHours: -3), event("先", startOffsetHours: 1)], now: now, consent: allowAll)
        XCTAssertEqual(items.map(\.title), ["先", "後"])
    }

    func testMarksTomorrow() {
        XCTAssertEqual(builder.calendarItems([event("明日", startOffsetHours: 16)], now: now, consent: allowAll).first?.day, .tomorrow)
    }

    func testOmitsTitlesWhenNotAllowedAndEncodesNull() throws {
        var consent = allowAll
        consent.sendEventTitles = false
        let items = builder.calendarItems([event("通院", startOffsetHours: 1), event("  ", startOffsetHours: 2)], now: now, consent: consent)
        XCTAssertEqual(items.map(\.title), [nil, nil])
        let json = String(decoding: try APICoding.encoder().encode(items[0]), as: UTF8.self)
        XCTAssertTrue(json.contains("\"title\":null"), json)
    }

    func testSendsNoCalendarWhenDisabled() {
        var consent = allowAll
        consent.useCalendar = false
        XCTAssertTrue(builder.calendarItems([event("a", startOffsetHours: 1)], now: now, consent: consent).isEmpty)
    }

    func testCapsEventCount() {
        let many = (1...30).map { event("e\($0)", startOffsetHours: Double($0) * 0.5) }
        XCTAssertEqual(builder.calendarItems(many, now: now, consent: allowAll).count, builder.maxEvents)
    }

    func testRespectsEachConsent() {
        let request = builder.experienceRequest(
            now: now, events: [], consent: ConsentSnapshot(useChatContext: false, useHistory: false, useLocation: false, allowWebSearch: false),
            recentMessages: ["疲れた"],
            history: [ExperienceRef(title: "x", theme: nil, reaction: .accepted, rating: .positive, date: nil)],
            feedback: [FeedbackSignal(tag: "short", rating: .positive, weight: 1)],
            excludeTitles: [],
            area: Area(locality: "堺市", administrativeArea: nil, countryCode: "JP")
        )
        XCTAssertTrue(request.recentUserMessages.isEmpty)
        XCTAssertTrue(request.recentExperiences.isEmpty)
        XCTAssertTrue(request.userFeedback.isEmpty)
        XCTAssertNil(request.area)
        XCTAssertFalse(request.allowWebSearch)
    }

    func testChatRequestKeepsRecentTurnsOnly() {
        let turns = (0..<30).map { ChatTurn(role: $0 % 2 == 0 ? .user : .assistant, text: "\($0)") }
        let request = builder.chatRequest(now: now, turns: turns, events: [event("a", startOffsetHours: 1), event("b", startOffsetHours: 2), event("c", startOffsetHours: 3), event("d", startOffsetHours: 4)], consent: allowAll, currentExperience: nil)
        XCTAssertEqual(request.messages.count, builder.maxChatTurns)
        XCTAssertEqual(request.messages.last?.text, "29")
        XCTAssertEqual(request.calendarContext.count, builder.maxChatEvents)
    }
}

@MainActor
final class ContextAssemblerTests: XCTestCase {
    func testAssemblesFromAllSourcesWhenAllowed() async {
        let h = Harness(
            consent: ConsentSnapshot(useLocation: true, allowWebSearch: true),
            area: Area(locality: "堺市", administrativeArea: "大阪府", countryCode: "JP"),
            entries: [HistoryEntry(createdAt: referenceDate.addingTimeInterval(-3600), title: "前の体験", theme: nil, invitation: "i", perspective: "p", tags: ["short"], status: .completed, rating: .positive)]
        )
        h.assembler.rememberUtterance("今日は疲れた")
        let request = await h.assembler.experienceRequest(excluding: ["除外"])
        XCTAssertEqual(request.calendarContext.first?.title, "数学の課題")
        XCTAssertEqual(request.recentUserMessages, ["今日は疲れた"])
        XCTAssertEqual(request.recentExperiences.first?.title, "前の体験")
        XCTAssertEqual(request.area?.locality, "堺市")
        XCTAssertTrue(request.allowWebSearch)
        XCTAssertEqual(request.excludeTitles, ["除外"])
        XCTAssertEqual(request.currentTime, "2026-10-08T18:00:00+09:00")
    }

    func testDoesNotAskForLocationWhenNotAllowed() async {
        let h = Harness(consent: ConsentSnapshot(useChatContext: false, useLocation: false), area: Area(locality: "堺市", administrativeArea: nil, countryCode: nil))
        h.assembler.rememberUtterance("覚えないで")
        let request = await h.assembler.experienceRequest()
        XCTAssertNil(request.area)
        XCTAssertEqual(h.location.requests, 0)
        XCTAssertTrue(request.recentUserMessages.isEmpty)
    }

    func testSkipsCalendarWithoutPermission() async {
        let h = Harness(calendar: FixedCalendarProvider(events: FixedCalendarProvider.sample(now: referenceDate).snapshots, state: .denied))
        let request = await h.assembler.experienceRequest()
        XCTAssertTrue(request.calendarContext.isEmpty)
    }

    func testChatRequestIncludesActiveExperience() async throws {
        let h = Harness()
        try h.history.record(Experience(title: "体験中のもの", perspective: "p", invitation: "i", reason: "r", difficulty: .low, tags: []), theme: nil, status: .active, at: referenceDate)
        let request = h.assembler.chatRequest(turns: [ChatTurn(role: .user, text: "hi")])
        XCTAssertEqual(request.currentExperience?.title, "体験中のもの")
    }

    func testConversationMemoryExpires() async {
        let memory = ConversationMemory(lifetime: 60, capacity: 2)
        memory.add("a", at: referenceDate)
        memory.add("b", at: referenceDate)
        memory.add("c", at: referenceDate.addingTimeInterval(30))
        XCTAssertEqual(memory.recent(now: referenceDate.addingTimeInterval(30)), ["b", "c"])
        XCTAssertEqual(memory.recent(now: referenceDate.addingTimeInterval(61)), ["c"])
        memory.clear()
        XCTAssertEqual(memory.recent(now: referenceDate), [])
    }
}
