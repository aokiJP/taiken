import Foundation

// Backendとの契約 (contracts/openapi.json と一致させる)。
// UIはこの型だけを使い、AIの自由文をロジックに使わない。
// 未知の列挙値は安全側 (推測・low など) に倒し、後から増えたフィールドが無くても読めるようにする。

// MARK: - 列挙

/// その情報が事実か推測か。未知の値は推測として扱う (推測を事実にしない)。
public enum Basis: String, Codable, Sendable, CaseIterable {
    case calendar, stated, inferred

    public init(from decoder: any Decoder) throws {
        self = Basis(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .inferred
    }

    public var isFact: Bool { self != .inferred }
}

public enum Difficulty: String, Codable, Sendable {
    case low, medium, high

    public init(from decoder: any Decoder) throws {
        self = Difficulty(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .low
    }
}

public enum ResultSource: String, Codable, Sendable {
    /// Backend経由でAIが生成
    case ai
    /// Backendのモック生成 (開発用)
    case mock
    /// AIが使えずBackendが代替生成
    case fallback
    /// 端末内の体験ライブラリから選んだ (未設定・オフライン時)
    case local
    /// 端末内のAI (Apple Intelligence) が生成。Backendは返さない
    case onDevice = "on_device"

    public init(from decoder: any Decoder) throws {
        self = ResultSource(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .ai
    }

    /// AIが状況を見て作った提案か (ライブラリや代替生成ではない)
    public var isGenerative: Bool {
        switch self {
        case .ai, .mock, .onDevice: true
        case .fallback, .local: false
        }
    }
}

/// ユーザーが自分で選んだ、いまの気分。提案の手がかりにする (自己申告なので事実として扱う)
public enum Mood: String, Codable, Sendable, CaseIterable, Identifiable {
    case tired, bored, focus, refresh

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .tired: "疲れぎみ"
        case .bored: "ひま"
        case .focus: "集中したい"
        case .refresh: "気分転換"
        }
    }
}

/// 七十二候。日付から決まる情報なので、許可なしで送ってよい (current_time 以上のことは分からない)
public struct SeasonContext: Codable, Hashable, Sendable {
    /// 二十四節気 (例: 寒露)
    public let solarTerm: String
    /// 七十二候 (例: 鴻雁来)
    public let microSeason: String
    /// 意味 (例: 雁が北から渡ってくる頃)
    public let meaning: String

    public init(solarTerm: String, microSeason: String, meaning: String) {
        self.solarTerm = solarTerm
        self.microSeason = microSeason
        self.meaning = meaning
    }
}

public enum FallbackReason: String, Codable, Sendable {
    case budgetExceeded = "budget_exceeded"
    case upstreamError = "upstream_error"
    case invalidOutput = "invalid_output"
    case unsafeOutput = "unsafe_output"
    case circuitOpen = "circuit_open"
    case busy
    case unknown

    public init(from decoder: any Decoder) throws {
        self = FallbackReason(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .unknown
    }
}

public enum Rating: String, Codable, Sendable, CaseIterable {
    case positive, neutral, negative

    public var emoji: String {
        switch self {
        case .positive: "👍"
        case .neutral: "😐"
        case .negative: "👎"
        }
    }

    public var label: String {
        switch self {
        case .positive: "響いた"
        case .neutral: "ふつう"
        case .negative: "合わなかった"
        }
    }

    /// 傾向計算での値
    var value: Double {
        switch self {
        case .positive: 1
        case .neutral: 0
        case .negative: -1
        }
    }
}

public enum Reaction: String, Codable, Sendable {
    case accepted, alternative, declined, completed
}

// MARK: - 共通の部品

public struct SituationNote: Codable, Hashable, Sendable {
    public let text: String
    public let basis: Basis

    public init(text: String, basis: Basis) {
        self.text = text
        self.basis = basis
    }
}

public struct Experience: Codable, Hashable, Sendable {
    public let title: String
    public let perspective: String
    public let invitation: String
    public let reason: String
    public let difficulty: Difficulty
    public let tags: [String]
    /// 体験のあとに思い返すための問い。古いBackendの応答には無い
    public let reflectionQuestion: String?

    public init(
        title: String, perspective: String, invitation: String, reason: String,
        difficulty: Difficulty, tags: [String], reflectionQuestion: String? = nil
    ) {
        self.title = title
        self.perspective = perspective
        self.invitation = invitation
        self.reason = reason
        self.difficulty = difficulty
        self.tags = tags
        self.reflectionQuestion = reflectionQuestion
    }

    enum CodingKeys: String, CodingKey {
        case title, perspective, invitation, reason, difficulty, tags, reflectionQuestion
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title = try c.decode(String.self, forKey: .title)
        perspective = try c.decode(String.self, forKey: .perspective)
        invitation = try c.decode(String.self, forKey: .invitation)
        reason = try c.decodeIfPresent(String.self, forKey: .reason) ?? ""
        difficulty = try c.decodeIfPresent(Difficulty.self, forKey: .difficulty) ?? .low
        tags = try c.decodeIfPresent([String].self, forKey: .tags) ?? []
        let question = try c.decodeIfPresent(String.self, forKey: .reflectionQuestion)?.trimmingCharacters(in: .whitespacesAndNewlines)
        reflectionQuestion = question?.isEmpty == false ? question : nil
    }
}

public struct Reference: Codable, Hashable, Sendable {
    public let title: String
    public let url: String

    public init(title: String, url: String) {
        self.title = title
        self.url = url
    }

    /// http(s) のURLだけを開ける形で返す
    public var safeURL: URL? {
        guard let url = URL(string: url), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
        return url
    }
}

// MARK: - POST /v1/experience

public struct CalendarItem: Codable, Hashable, Sendable {
    public enum Day: String, Codable, Sendable { case today, tomorrow }

    /// ユーザーがタイトル送信を許可していないときは nil (JSONでは null)
    public let title: String?
    public let start: String
    public let end: String?
    public let isAllDay: Bool
    public let day: Day

    public init(title: String?, start: String, end: String?, isAllDay: Bool, day: Day) {
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.day = day
    }

    enum CodingKeys: String, CodingKey { case title, start, end, isAllDay, day }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .title) // null を明示的に送る
        try c.encode(start, forKey: .start)
        try c.encode(end, forKey: .end)
        try c.encode(isAllDay, forKey: .isAllDay)
        try c.encode(day, forKey: .day)
    }
}

public struct ExperienceRef: Codable, Hashable, Sendable {
    public let title: String
    public let theme: String?
    public let reaction: Reaction?
    public let rating: Rating?
    public let date: String?

    public init(title: String, theme: String?, reaction: Reaction?, rating: Rating?, date: String?) {
        self.title = title
        self.theme = theme
        self.reaction = reaction
        self.rating = rating
        self.date = date
    }
}

/// 最近の反応の傾向 (性格分類ではない)。weight は傾向の強さ 0〜1
public struct FeedbackSignal: Codable, Hashable, Sendable {
    public let tag: String
    public let rating: Rating
    public let weight: Double

    public init(tag: String, rating: Rating, weight: Double) {
        self.tag = tag
        self.rating = rating
        self.weight = weight
    }
}

/// おおよその地域 (市区町村レベル)。座標は送らない
public struct Area: Codable, Hashable, Sendable {
    public let locality: String?
    public let administrativeArea: String?
    public let countryCode: String?

    public init(locality: String?, administrativeArea: String?, countryCode: String?) {
        self.locality = locality
        self.administrativeArea = administrativeArea
        self.countryCode = countryCode
    }

    enum CodingKeys: String, CodingKey { case locality, administrativeArea, countryCode }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(locality, forKey: .locality)
        try c.encode(administrativeArea, forKey: .administrativeArea)
        try c.encode(countryCode, forKey: .countryCode)
    }

    public var displayName: String? { locality ?? administrativeArea }
}

public struct ExperienceRequest: Codable, Sendable, Equatable {
    public let currentTime: String
    public let timeZone: String
    public let locale: String
    public let calendarContext: [CalendarItem]
    public let recentUserMessages: [String]
    public let recentExperiences: [ExperienceRef]
    public let userFeedback: [FeedbackSignal]
    public let excludeTitles: [String]
    public let area: Area?
    public let allowWebSearch: Bool
    /// ユーザーがその場で選んだ気分 (選んでいなければキーごと送らない)
    public let mood: Mood?
    /// 七十二候 (日付から決まる)
    public let season: SeasonContext?

    public init(
        currentTime: String, timeZone: String, locale: String, calendarContext: [CalendarItem],
        recentUserMessages: [String], recentExperiences: [ExperienceRef], userFeedback: [FeedbackSignal],
        excludeTitles: [String], area: Area?, allowWebSearch: Bool, mood: Mood? = nil, season: SeasonContext? = nil
    ) {
        self.currentTime = currentTime
        self.timeZone = timeZone
        self.locale = locale
        self.calendarContext = calendarContext
        self.recentUserMessages = recentUserMessages
        self.recentExperiences = recentExperiences
        self.userFeedback = userFeedback
        self.excludeTitles = excludeTitles
        self.area = area
        self.allowWebSearch = allowWebSearch
        self.mood = mood
        self.season = season
    }

    public func excluding(_ titles: [String]) -> ExperienceRequest {
        ExperienceRequest(
            currentTime: currentTime, timeZone: timeZone, locale: locale, calendarContext: calendarContext,
            recentUserMessages: recentUserMessages, recentExperiences: recentExperiences, userFeedback: userFeedback,
            excludeTitles: titles, area: area, allowWebSearch: allowWebSearch, mood: mood, season: season
        )
    }
}

public struct Situation: Codable, Hashable, Sendable {
    public let summary: String
    public let observations: [SituationNote]

    public init(summary: String, observations: [SituationNote]) {
        self.summary = summary
        self.observations = observations
    }
}

public struct DetectedAction: Codable, Hashable, Sendable {
    public let label: String
    public let basis: Basis

    public init(label: String, basis: Basis) {
        self.label = label
        self.basis = basis
    }
}

public struct PossibleObligation: Codable, Hashable, Sendable {
    public let label: String
    public let likelihood: Double

    public init(label: String, likelihood: Double) {
        self.label = label
        self.likelihood = likelihood
    }
}

public struct NotificationContent: Codable, Hashable, Sendable {
    public let title: String
    public let body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

public struct ExperienceResponse: Codable, Hashable, Sendable {
    public let situation: Situation
    public let detectedActions: [DetectedAction]
    public let possibleObligations: [PossibleObligation]
    public let experienceOpportunities: [String]
    public let isObligation: Bool
    public let confidence: Double
    public let experience: Experience
    public let shouldNotify: Bool
    public let notification: NotificationContent?
    public let references: [Reference]
    public let source: ResultSource
    public let fallbackReason: FallbackReason?

    public init(
        situation: Situation, detectedActions: [DetectedAction], possibleObligations: [PossibleObligation],
        experienceOpportunities: [String], isObligation: Bool, confidence: Double, experience: Experience,
        shouldNotify: Bool, notification: NotificationContent?, references: [Reference] = [],
        source: ResultSource, fallbackReason: FallbackReason? = nil
    ) {
        self.situation = situation
        self.detectedActions = detectedActions
        self.possibleObligations = possibleObligations
        self.experienceOpportunities = experienceOpportunities
        self.isObligation = isObligation
        self.confidence = confidence
        self.experience = experience
        self.shouldNotify = shouldNotify
        self.notification = notification
        self.references = references
        self.source = source
        self.fallbackReason = fallbackReason
    }

    enum CodingKeys: String, CodingKey {
        case situation, detectedActions, possibleObligations, experienceOpportunities, isObligation, confidence
        case experience, shouldNotify, notification, references, source, fallbackReason
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        situation = try c.decode(Situation.self, forKey: .situation)
        detectedActions = try c.decodeIfPresent([DetectedAction].self, forKey: .detectedActions) ?? []
        possibleObligations = try c.decodeIfPresent([PossibleObligation].self, forKey: .possibleObligations) ?? []
        experienceOpportunities = try c.decodeIfPresent([String].self, forKey: .experienceOpportunities) ?? []
        isObligation = try c.decodeIfPresent(Bool.self, forKey: .isObligation) ?? false
        confidence = min(1, max(0, try c.decodeIfPresent(Double.self, forKey: .confidence) ?? 0.5))
        experience = try c.decode(Experience.self, forKey: .experience)
        notification = try c.decodeIfPresent(NotificationContent.self, forKey: .notification)
        shouldNotify = (try c.decodeIfPresent(Bool.self, forKey: .shouldNotify) ?? false) && notification != nil
        references = try c.decodeIfPresent([Reference].self, forKey: .references) ?? []
        source = try c.decodeIfPresent(ResultSource.self, forKey: .source) ?? .ai
        fallbackReason = try c.decodeIfPresent(FallbackReason.self, forKey: .fallbackReason)
    }
}

// MARK: - POST /v1/chat

public struct ChatTurn: Codable, Hashable, Sendable {
    public enum Role: String, Codable, Sendable { case user, assistant }
    public let role: Role
    public let text: String

    public init(role: Role, text: String) {
        self.role = role
        self.text = text
    }
}

public struct ChatRequest: Codable, Sendable, Equatable {
    public let currentTime: String
    public let timeZone: String
    public let locale: String
    public let messages: [ChatTurn]
    public let calendarContext: [CalendarItem]
    public let currentExperience: ExperienceRef?

    public init(currentTime: String, timeZone: String, locale: String, messages: [ChatTurn], calendarContext: [CalendarItem], currentExperience: ExperienceRef?) {
        self.currentTime = currentTime
        self.timeZone = timeZone
        self.locale = locale
        self.messages = messages
        self.calendarContext = calendarContext
        self.currentExperience = currentExperience
    }
}

public struct ChatResponse: Codable, Hashable, Sendable {
    public let reply: String
    public let observations: [SituationNote]
    public let suggestExperience: Bool
    public let experience: Experience?
    public let needsCare: Bool
    public let source: ResultSource
    public let fallbackReason: FallbackReason?

    public init(
        reply: String, observations: [SituationNote], suggestExperience: Bool, experience: Experience?,
        needsCare: Bool = false, source: ResultSource, fallbackReason: FallbackReason? = nil
    ) {
        self.reply = reply
        self.observations = observations
        self.suggestExperience = suggestExperience
        self.experience = experience
        self.needsCare = needsCare
        self.source = source
        self.fallbackReason = fallbackReason
    }

    enum CodingKeys: String, CodingKey {
        case reply, observations, suggestExperience, experience, needsCare, source, fallbackReason
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reply = try c.decode(String.self, forKey: .reply)
        observations = try c.decodeIfPresent([SituationNote].self, forKey: .observations) ?? []
        needsCare = try c.decodeIfPresent(Bool.self, forKey: .needsCare) ?? false
        let experience = try c.decodeIfPresent(Experience.self, forKey: .experience)
        // 苦痛のサインがあるときは、サーバーが付けていても体験を表示しない
        self.experience = needsCare ? nil : experience
        suggestExperience = (try c.decodeIfPresent(Bool.self, forKey: .suggestExperience) ?? false) && self.experience != nil
        source = try c.decodeIfPresent(ResultSource.self, forKey: .source) ?? .ai
        fallbackReason = try c.decodeIfPresent(FallbackReason.self, forKey: .fallbackReason)
    }
}

// MARK: - GET /v1/status

public struct ServiceStatus: Codable, Hashable, Sendable {
    public struct Features: Codable, Hashable, Sendable {
        public let webSearch: Bool
        public init(webSearch: Bool) { self.webSearch = webSearch }
    }

    public struct Budget: Codable, Hashable, Sendable {
        public let requestsRemaining: Int
        public let tokensRemaining: Int
        public let webSearchesRemaining: Int
        public let resetsAt: String

        public init(requestsRemaining: Int, tokensRemaining: Int, webSearchesRemaining: Int, resetsAt: String) {
            self.requestsRemaining = requestsRemaining
            self.tokensRemaining = tokensRemaining
            self.webSearchesRemaining = webSearchesRemaining
            self.resetsAt = resetsAt
        }
    }

    public let status: String
    public let version: String
    public let provider: String
    public let features: Features
    public let budget: Budget

    public init(status: String, version: String, provider: String, features: Features, budget: Budget) {
        self.status = status
        self.version = version
        self.provider = provider
        self.features = features
        self.budget = budget
    }
}

// MARK: - エラー

public struct APIErrorBody: Codable, Sendable {
    public struct Detail: Codable, Sendable {
        public let code: String
        public let message: String
        public let retryAfterSeconds: Int?
        public let requestId: String?
    }

    public let error: Detail
}

// MARK: - JSON

public enum APICoding {
    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }

    /// 端末のタイムゾーン付き ISO 8601 (例: 2026-10-08T18:10:00+09:00)
    public static func timestamp(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = timeZone
        return f.string(from: date)
    }

    public static func dayString(_ date: Date, timeZone: TimeZone = .current) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        f.timeZone = timeZone
        return f.string(from: date)
    }
}
