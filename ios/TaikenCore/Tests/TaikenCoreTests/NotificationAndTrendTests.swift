import Foundation
import XCTest
@testable import TaikenCore

final class NotificationPolicyTests: XCTestCase {
    private let calendar = tokyoCalendar
    private let enabled = NotificationPreferences(enabled: true)

    private func decide(_ response: ExperienceResponse, prefs: NotificationPreferences? = nil, auth: NotificationAuthorization = .authorized, deliveries: [Date] = [], active: Bool = false, at date: Date = referenceDate) -> NotificationPolicy.Decision {
        NotificationPolicy.decide(response: response, preferences: prefs ?? enabled, authorization: auth, deliveries: deliveries, hasActiveExperience: active, now: date, calendar: calendar)
    }

    func testDeliversOnlyWhenEverythingAllows() {
        XCTAssertEqual(decide(sampleResponse(notify: true)), .deliver(NotificationContent(title: "通知", body: "本文")))
        XCTAssertEqual(decide(sampleResponse(notify: false)), .skip(.notSuggested))
        XCTAssertEqual(decide(sampleResponse(source: .fallback, notify: true)), .skip(.fallbackResult))
        XCTAssertEqual(decide(sampleResponse(notify: true), prefs: NotificationPreferences(enabled: false)), .skip(.disabled))
        XCTAssertEqual(decide(sampleResponse(notify: true), auth: .denied), .skip(.notAuthorized))
        XCTAssertEqual(decide(sampleResponse(notify: true), active: true), .skip(.busyWithExperience))
    }

    func testQuietHoursWrapAroundMidnight() {
        XCTAssertTrue(NotificationPolicy.isQuiet(hour: 23, start: 22, end: 8))
        XCTAssertTrue(NotificationPolicy.isQuiet(hour: 3, start: 22, end: 8))
        XCTAssertFalse(NotificationPolicy.isQuiet(hour: 8, start: 22, end: 8))
        XCTAssertTrue(NotificationPolicy.isQuiet(hour: 13, start: 12, end: 14))
        XCTAssertFalse(NotificationPolicy.isQuiet(hour: 10, start: 9, end: 9))
        let lateNight = referenceDate.addingTimeInterval(5 * 3600) // 23:00 JST
        XCTAssertEqual(decide(sampleResponse(notify: true), at: lateNight), .skip(.quietHours))
    }

    func testDailyLimitAndMinimumInterval() {
        let twoEarlier = [referenceDate.addingTimeInterval(-8 * 3600), referenceDate.addingTimeInterval(-5 * 3600)]
        XCTAssertEqual(decide(sampleResponse(notify: true), deliveries: twoEarlier), .skip(.dailyLimit))
        XCTAssertEqual(decide(sampleResponse(notify: true), deliveries: [referenceDate.addingTimeInterval(-3600)]), .skip(.tooSoon))
        // 昨日の通知は今日の上限に数えない
        let yesterday = [referenceDate.addingTimeInterval(-30 * 3600), referenceDate.addingTimeInterval(-26 * 3600)]
        XCTAssertEqual(decide(sampleResponse(notify: true), deliveries: yesterday), .deliver(NotificationContent(title: "通知", body: "本文")))
    }

    func testNextCheckSkipsQuietHours() {
        XCTAssertNil(NotificationPolicy.nextCheck(after: referenceDate, preferences: NotificationPreferences(enabled: false), calendar: calendar))
        // 18:00 + 2h = 20:00 は静かな時間帯ではない
        XCTAssertEqual(NotificationPolicy.nextCheck(after: referenceDate, preferences: enabled, calendar: calendar), referenceDate.addingTimeInterval(2 * 3600))
        // 21:00 + 2h = 23:00 は静かな時間帯 → 翌朝8:00
        let next = NotificationPolicy.nextCheck(after: referenceDate.addingTimeInterval(3 * 3600), preferences: enabled, calendar: calendar)
        XCTAssertEqual(next, referenceDate.addingTimeInterval(14 * 3600))
        // 02:00 + 2h = 04:00 → 同じ日の8:00
        let early = referenceDate.addingTimeInterval(8 * 3600) // 翌02:00
        XCTAssertEqual(NotificationPolicy.nextCheck(after: early, preferences: enabled, calendar: calendar), referenceDate.addingTimeInterval(14 * 3600))
    }

    func testPreferencesAreNormalized() {
        let p = NotificationPreferences(enabled: true, quietStartHour: 30, quietEndHour: -1, maxPerDay: 99, minimumIntervalHours: 0).normalized
        XCTAssertEqual(p, NotificationPreferences(enabled: true, quietStartHour: 23, quietEndHour: 0, maxPerDay: 5, minimumIntervalHours: 1))
    }
}

@MainActor
final class BackgroundCoordinatorTests: XCTestCase {
    private func make(_ h: Harness, service: StubService, scheduler: RecordingNotificationScheduler = RecordingNotificationScheduler(), ledger: InMemoryNotificationLedger = InMemoryNotificationLedger(), prefs: NotificationPreferences = NotificationPreferences(enabled: true)) -> BackgroundCoordinator {
        BackgroundCoordinator(service: service, assembler: h.assembler, history: h.history, scheduler: scheduler, ledger: ledger, cache: h.cache, preferences: { prefs })
    }

    func testDeliversAndCachesProposal() async {
        let h = Harness()
        let scheduler = RecordingNotificationScheduler()
        let ledger = InMemoryNotificationLedger()
        let coordinator = make(h, service: StubService(experience: [.success(sampleResponse(title: "夕方の体験", notify: true))]), scheduler: scheduler, ledger: ledger)
        let outcome = await coordinator.refresh()
        XCTAssertEqual(outcome, .delivered("通知"))
        XCTAssertEqual(scheduler.delivered.count, 1)
        XCTAssertEqual(ledger.deliveries(since: .distantPast), [referenceDate])
        XCTAssertEqual(h.cache.load()?.response.experience.title, "夕方の体験")
    }

    func testSkipsBeforeCallingAIWhenNotAllowed() async {
        let h = Harness()
        let service = StubService()
        let disabled = make(h, service: service, prefs: NotificationPreferences(enabled: false))
        let r1 = await disabled.refresh()
        XCTAssertEqual(r1, .skipped(.disabled))
        let unauthorized = make(h, service: service, scheduler: RecordingNotificationScheduler(authorization: .denied))
        let r2 = await unauthorized.refresh()
        XCTAssertEqual(r2, .skipped(.notAuthorized))
        XCTAssertEqual(service.experienceRequests.count, 0)
    }

    func testLocalModeNeverNotifies() async {
        let h = Harness()
        let service = StubService()
        service.local = true
        let outcome = await make(h, service: service).refresh()
        XCTAssertEqual(outcome, .skipped(.notSuggested))
    }

    func testFailureIsReported() async {
        let h = Harness()
        let outcome = await make(h, service: StubService(experience: [.failure(AppError.offline)])).refresh()
        XCTAssertEqual(outcome, .failed)
    }

    func testDoesNotNotifyWhenAISaysNo() async {
        let h = Harness()
        let scheduler = RecordingNotificationScheduler()
        let outcome = await make(h, service: StubService(experience: [.success(sampleResponse(notify: false))]), scheduler: scheduler).refresh()
        XCTAssertEqual(outcome, .skipped(.notSuggested))
        XCTAssertTrue(scheduler.delivered.isEmpty)
        XCTAssertNil(h.cache.load())
    }

    func testNextCheckDate() async {
        let h = Harness()
        XCTAssertEqual(make(h, service: StubService()).nextCheckDate(), referenceDate.addingTimeInterval(7200))
    }
}

final class PreferenceTrendsTests: XCTestCase {
    private func entry(_ tags: [String], _ status: HistoryEntry.Status, _ rating: Rating? = nil, daysAgo: Double = 0) -> HistoryEntry {
        HistoryEntry(createdAt: referenceDate.addingTimeInterval(-daysAgo * 86_400), title: "t", theme: nil, invitation: "i", perspective: "p", tags: tags, status: status, rating: rating)
    }

    func testRecentPositiveAndNegativeTendencies() {
        let entries = [
            entry(["new_perspective", "short"], .completed, .positive),
            entry(["new_perspective"], .completed, .positive, daysAgo: 1),
            entry(["competitive"], .completed, .negative),
            entry(["competitive"], .declined, daysAgo: 2),
        ]
        let signals = PreferenceTrends.signals(from: entries, now: referenceDate)
        XCTAssertEqual(signals.first { $0.tag == "new_perspective" }?.rating, .positive)
        XCTAssertEqual(signals.first { $0.tag == "competitive" }?.rating, .negative)
        // 1件だけの材料では傾向にしない
        XCTAssertNil(signals.first { $0.tag == "short" })
        XCTAssertTrue(signals.allSatisfy { (0...1).contains($0.weight) })
    }

    func testOldReactionsFadeOut() {
        let old = [entry(["social"], .completed, .negative, daysAgo: 120), entry(["social"], .completed, .negative, daysAgo: 121)]
        XCTAssertTrue(PreferenceTrends.signals(from: old, now: referenceDate).isEmpty)
        let recentFlip = old + [entry(["social"], .completed, .positive), entry(["social"], .completed, .positive)]
        XCTAssertEqual(PreferenceTrends.signals(from: recentFlip, now: referenceDate).first?.rating, .positive)
    }

    func testMixedReactionsAreNotSentButShownAsMixed() {
        let mixed = [entry(["question"], .completed, .positive), entry(["question"], .completed, .negative)]
        XCTAssertTrue(PreferenceTrends.signals(from: mixed, now: referenceDate).isEmpty)
        let summary = PreferenceTrends.summaries(from: mixed, now: referenceDate).first
        XCTAssertEqual(summary?.direction, .mixed)
        XCTAssertEqual(summary?.label, "問い")
        XCTAssertTrue(summary?.sentence.contains("半々") == true)
    }

    func testLabels() {
        XCTAssertEqual(ExperienceTag.label("new_perspective"), "新しい視点")
        XCTAssertEqual(ExperienceTag.label("unknown_tag"), "unknown_tag")
    }
}

@MainActor
final class HistoryViewModelTests: XCTestCase {
    func testGroupsChosenEntriesByDayAndExports() async throws {
        let repo = InMemoryHistoryRepository([
            HistoryEntry(createdAt: referenceDate, title: "今日", theme: nil, invitation: "i", perspective: "p", tags: ["short"], status: .completed, rating: .positive, note: "メモ"),
            HistoryEntry(createdAt: referenceDate.addingTimeInterval(-86_400), title: "昨日", theme: nil, invitation: "i", perspective: "p", tags: ["short"], status: .completed, rating: .positive),
            HistoryEntry(createdAt: referenceDate, title: "断った", theme: nil, invitation: "i", perspective: "p", tags: [], status: .declined),
            HistoryEntry(createdAt: referenceDate.addingTimeInterval(-90 * 86_400), title: "古い", theme: nil, invitation: "i", perspective: "p", tags: [], status: .completed),
        ])
        let model = HistoryViewModel(history: repo, calendar: tokyoCalendar, now: { referenceDate })
        model.reload()
        XCTAssertEqual(model.sections.map { $0.entries.map(\.title) }, [["今日"], ["昨日"]])
        XCTAssertEqual(model.trends.first?.tag, "short")

        let exported = try JSONSerialization.jsonObject(with: model.exportJSON()) as? [String: Any]
        XCTAssertEqual((exported?["entries"] as? [Any])?.count, 4)

        model.delete(model.sections[0].entries[0])
        XCTAssertEqual(model.sections.map { $0.entries.map(\.title) }, [["昨日"]])
    }

    func testDeleteFailureShowsMessage() async {
        let repo = InMemoryHistoryRepository([HistoryEntry(createdAt: referenceDate, title: "a", theme: nil, invitation: "i", perspective: "p", tags: [], status: .completed)])
        repo.failWrites = true
        let model = HistoryViewModel(history: repo, calendar: tokyoCalendar, now: { referenceDate })
        model.reload()
        model.delete(model.sections[0].entries[0])
        XCTAssertNotNil(model.errorMessage)
    }
}

@MainActor
final class SettingsViewModelTests: XCTestCase {
    private func defaults() -> DefaultsStore {
        let suite = "SettingsViewModelTests-\(UUID().uuidString)"
        return DefaultsStore(UserDefaults(suiteName: suite)!)
    }

    func testSavesOnlyAfterSuccessfulConnectionTest() async {
        let store = InMemoryConnectionStore()
        var changes: [BackendEndpoint?] = []
        let failing = SettingsViewModel(connectionStore: store, scheduler: RecordingNotificationScheduler(), defaults: defaults(), makeService: { _ in FailingStatusService() }, onEndpointChange: { changes.append($0) })
        failing.baseURLText = "https://taiken.example"
        failing.tokenText = "tok"
        await failing.saveAndTestConnection()
        XCTAssertNil(store.load())
        if case .failed = failing.connectionState {} else { XCTFail("should fail") }

        let model = SettingsViewModel(connectionStore: store, scheduler: RecordingNotificationScheduler(), defaults: defaults(), makeService: { _ in StubService() }, onEndpointChange: { changes.append($0) })
        model.baseURLText = " https://taiken.example "
        model.tokenText = "tok"
        await model.saveAndTestConnection()
        XCTAssertEqual(store.load(), BackendEndpoint(baseURL: URL(string: "https://taiken.example")!, token: "tok"))
        XCTAssertTrue(model.hasSavedToken)
        XCTAssertEqual(model.tokenText, "")
        XCTAssertEqual(changes.count, 1)

        // トークン欄が空なら保存済みのトークンを使い続ける
        model.baseURLText = "https://other.example"
        await model.saveAndTestConnection()
        XCTAssertEqual(store.load()?.token, "tok")

        model.disconnect()
        XCTAssertNil(store.load())
        XCTAssertFalse(model.isConfigured)
        XCTAssertNil(changes.last!)
    }

    func testRejectsInsecureRemoteURL() async {
        let model = SettingsViewModel(connectionStore: InMemoryConnectionStore(), scheduler: RecordingNotificationScheduler(), defaults: defaults(), makeService: { _ in StubService() }, onEndpointChange: { _ in })
        model.baseURLText = "http://example.com"
        await model.saveAndTestConnection()
        XCTAssertNotNil(model.validationMessage)
        XCTAssertEqual(model.connectionState, .idle)
    }

    func testEnablingNotificationsRequestsPermission() async {
        let store = defaults()
        var changed: [NotificationPreferences] = []
        let granted = SettingsViewModel(connectionStore: InMemoryConnectionStore(), scheduler: RecordingNotificationScheduler(authorization: .notDetermined), defaults: store, makeService: { _ in StubService() }, onEndpointChange: { _ in }, onNotificationPreferencesChange: { changed.append($0) })
        await granted.setNotificationsEnabled(true)
        XCTAssertTrue(granted.notificationPreferences.enabled)
        XCTAssertTrue(store.notificationPreferences().enabled)
        XCTAssertEqual(changed.count, 1)

        let denied = SettingsViewModel(connectionStore: InMemoryConnectionStore(), scheduler: RecordingNotificationScheduler(authorization: .notDetermined, grantOnRequest: false), defaults: defaults(), makeService: { _ in StubService() }, onEndpointChange: { _ in })
        await denied.setNotificationsEnabled(true)
        XCTAssertFalse(denied.notificationPreferences.enabled)
        XCTAssertNotNil(denied.notificationMessage)
    }

    func testStoresRoundTrip() async {
        let store = defaults()
        XCTAssertEqual(store.consent(), ConsentSnapshot())
        store.defaults.set(true, forKey: ConsentKey.allowWebSearch)
        XCTAssertTrue(store.consent().allowWebSearch)
        XCTAssertEqual(store.installID(), store.installID())

        let cache = UserDefaultsProposalCache(defaults: store.defaults)
        cache.save(CachedProposal(generatedAt: referenceDate, response: sampleResponse()))
        XCTAssertEqual(cache.load()?.response, sampleResponse())

        let ledger = UserDefaultsNotificationLedger(defaults: store.defaults)
        ledger.recordDelivery(at: referenceDate.addingTimeInterval(-3 * 86_400))
        ledger.recordDelivery(at: referenceDate)
        XCTAssertEqual(ledger.deliveries(since: .distantPast), [referenceDate])

        store.removeAll()
        XCTAssertNil(cache.load())
        XCTAssertTrue(ledger.deliveries(since: .distantPast).isEmpty)
        XCTAssertTrue(store.consent().allowWebSearch) // 許可の設定は残す
    }
}

struct FailingStatusService: ExperienceService {
    func generateExperience(_ request: ExperienceRequest) async throws -> ExperienceResponse { throw AppError.offline }
    func chat(_ request: ChatRequest) async throws -> ChatResponse { throw AppError.offline }
    func status() async throws -> ServiceStatus { throw AppError.unauthorized }
}
