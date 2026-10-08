import Foundation
import XCTest
@testable import TaikenCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// contracts/ (Backendのテストと同じファイル) を読む
enum Fixtures {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // TaikenCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // TaikenCore
        .deletingLastPathComponent() // ios
        .deletingLastPathComponent() // repo root
        .appendingPathComponent("contracts")

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent("\(name).json"))
    }

    static func object(_ name: String) throws -> NSDictionary {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data(name)) as? NSDictionary)
    }
}

func jsonObject(_ data: Data) throws -> NSDictionary {
    try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? NSDictionary)
}

/// 2026-10-08 18:00 JST
let referenceDate = Date(timeIntervalSince1970: 1_791_450_000)
let tokyo = TimeZone(identifier: "Asia/Tokyo")!

var tokyoCalendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = tokyo
    return c
}

func makeBuilder() -> ContextBuilder {
    ContextBuilder(calendar: tokyoCalendar, timeZone: tokyo, localeIdentifier: "ja-JP")
}

/// テスト中に進められる時計
final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ date: Date = referenceDate) { value = date }
    var now: Date { lock.withLock { value } }
    func advance(_ seconds: TimeInterval) { lock.withLock { value = value.addingTimeInterval(seconds) } }
    func set(_ date: Date) { lock.withLock { value = date } }
}

func sampleResponse(title: String = "つまずきの観察", source: ResultSource = .ai, notify: Bool = false, tags: [String] = ["short"]) -> ExperienceResponse {
    ExperienceResponse(
        situation: Situation(summary: "s", observations: []),
        detectedActions: [DetectedAction(label: "数学の課題", basis: .calendar)],
        possibleObligations: [],
        experienceOpportunities: [],
        isObligation: true,
        confidence: 0.8,
        experience: Experience(title: title, perspective: "p", invitation: "\(title)してみませんか？", reason: "r", difficulty: .low, tags: tags),
        shouldNotify: notify,
        notification: notify ? NotificationContent(title: "通知", body: "本文") : nil,
        source: source
    )
}

/// 決めた応答を返す/失敗するサービス
final class StubService: ExperienceService, @unchecked Sendable {
    private let lock = NSLock()
    private var experienceResults: [Result<ExperienceResponse, Error>]
    private var chatResults: [Result<ChatResponse, Error>]
    private(set) var experienceRequests: [ExperienceRequest] = []
    private(set) var chatRequests: [ChatRequest] = []
    var local = false

    init(experience: [Result<ExperienceResponse, Error>] = [.success(sampleResponse())], chat: [Result<ChatResponse, Error>] = []) {
        experienceResults = experience
        chatResults = chat
    }

    var isLocal: Bool { local }

    func generateExperience(_ request: ExperienceRequest) async throws -> ExperienceResponse {
        try lock.withLock {
            experienceRequests.append(request)
            let result = experienceResults.count > 1 ? experienceResults.removeFirst() : experienceResults[0]
            return try result.get()
        }
    }

    func chat(_ request: ChatRequest) async throws -> ChatResponse {
        try lock.withLock {
            chatRequests.append(request)
            let result = chatResults.count > 1 ? chatResults.removeFirst() : chatResults[0]
            return try result.get()
        }
    }

    func status() async throws -> ServiceStatus {
        ServiceStatus(status: "ok", version: "test", provider: "mock", features: .init(webSearch: false), budget: .init(requestsRemaining: 1, tokensRemaining: 1, webSearchesRemaining: 0, resetsAt: "x"))
    }
}

/// HTTP の代わりに決めた応答を返す
final class StubTransport: HTTPTransport, @unchecked Sendable {
    typealias Responder = @Sendable (URLRequest) throws -> (Int, Data, [String: String])
    private let lock = NSLock()
    private var responders: [Responder]
    private(set) var requests: [URLRequest] = []

    init(_ responders: Responder...) {
        self.responders = responders
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let responder: Responder = lock.withLock {
            requests.append(request)
            return responders.count > 1 ? responders.removeFirst() : responders[0]
        }
        let (status, data, headers) = try responder(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        return (data, response)
    }
}

@MainActor
struct Harness {
    let clock: TestClock
    let history: InMemoryHistoryRepository
    let memory: ConversationMemory
    let assembler: ContextAssembler
    let cache: InMemoryProposalCache
    let location: FixedLocationProvider
    var consent: ConsentSnapshot

    init(consent: ConsentSnapshot = ConsentSnapshot(), calendar: FixedCalendarProvider? = nil, area: Area? = nil, entries: [HistoryEntry] = []) {
        let clock = TestClock()
        self.clock = clock
        history = InMemoryHistoryRepository(entries)
        memory = ConversationMemory()
        cache = InMemoryProposalCache()
        location = FixedLocationProvider(area: area)
        self.consent = consent
        let current = consent
        assembler = ContextAssembler(
            calendarProvider: calendar ?? FixedCalendarProvider.sample(now: referenceDate),
            locationProvider: location,
            history: history,
            memory: memory,
            builder: makeBuilder(),
            consent: { current },
            now: { clock.now }
        )
    }
}

/// "2026-10-08" の東京の時刻
func tokyoDate(_ day: String, hour: Int = 0, minute: Int = 0) -> Date {
    let parts = day.split(separator: "-").compactMap { Int($0) }
    return tokyoCalendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: hour, minute: minute))!
}

/// 1970-01-01 からの日数 ("2026-10-08" → 20734)
func dayNumber(_ day: String) -> Int {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(secondsFromGMT: 0)!
    let parts = day.split(separator: "-").compactMap { Int($0) }
    let date = utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
    return LibrarySelector.dayNumber(of: date, calendar: utc)
}

func experienceRequest(
    at date: Date = referenceDate,
    calendar items: [CalendarItem] = [],
    messages: [String] = [],
    mood: Mood? = nil,
    exclude: [String] = [],
    recent: [ExperienceRef] = []
) -> ExperienceRequest {
    ExperienceRequest(
        currentTime: APICoding.timestamp(date, timeZone: tokyo), timeZone: "Asia/Tokyo", locale: "ja-JP",
        calendarContext: items, recentUserMessages: messages, recentExperiences: recent, userFeedback: [],
        excludeTitles: exclude, area: nil, allowWebSearch: false, mood: mood,
        season: MicroSeason.at(date, calendar: tokyoCalendar).context
    )
}

func calendarItem(_ title: String?, at date: Date, day: CalendarItem.Day = .today) -> CalendarItem {
    CalendarItem(
        title: title, start: APICoding.timestamp(date, timeZone: tokyo),
        end: APICoding.timestamp(date.addingTimeInterval(3600), timeZone: tokyo), isAllDay: false, day: day
    )
}
