import Foundation

/// 端末内の情報から、Backendへ送る最小限のコンテキストを組み立てる純粋な関数群 (指示書 §8, §19)。
/// 「送る必要がないものは送らない」をここで一括して守る。
public struct ContextBuilder: Sendable {
    public var calendar: Calendar
    public var timeZone: TimeZone
    public var localeIdentifier: String
    public var maxEvents = 8
    public var maxChatEvents = 3
    public var maxHistory = 8
    public var maxChatTurns = 12

    public init(calendar: Calendar = .current, timeZone: TimeZone = .current, localeIdentifier: String = Locale.current.identifier(.bcp47)) {
        self.calendar = calendar
        self.timeZone = timeZone
        self.localeIdentifier = localeIdentifier
    }

    /// 今日の0時〜明後日の0時 (今日と明日の予定)
    public func calendarWindow(now: Date) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 2, to: start) ?? now.addingTimeInterval(48 * 3600)
        return (start, end)
    }

    public func calendarItems(_ events: [CalendarEventSnapshot], now: Date, consent: ConsentSnapshot, limit: Int? = nil) -> [CalendarItem] {
        guard consent.useCalendar else { return [] }
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
        return events
            .filter { $0.end > now } // 終わった予定は送らない
            .sorted { $0.start < $1.start }
            .prefix(limit ?? maxEvents)
            .map { event in
                let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines)
                return CalendarItem(
                    title: consent.sendEventTitles && title?.isEmpty == false ? title : nil,
                    start: APICoding.timestamp(event.start, timeZone: timeZone),
                    end: APICoding.timestamp(event.end, timeZone: timeZone),
                    isAllDay: event.isAllDay,
                    day: event.start >= tomorrow ? .tomorrow : .today
                )
            }
    }

    public func experienceRequest(
        now: Date,
        events: [CalendarEventSnapshot],
        consent: ConsentSnapshot,
        recentMessages: [String],
        history: [ExperienceRef],
        feedback: [FeedbackSignal],
        excludeTitles: [String],
        area: Area? = nil,
        mood: Mood? = nil,
        tree: TreeContext? = nil
    ) -> ExperienceRequest {
        ExperienceRequest(
            currentTime: APICoding.timestamp(now, timeZone: timeZone),
            timeZone: timeZone.identifier,
            locale: localeIdentifier,
            calendarContext: calendarItems(events, now: now, consent: consent),
            recentUserMessages: consent.useChatContext ? recentMessages : [],
            recentExperiences: consent.useHistory ? Array(history.prefix(maxHistory)) : [],
            userFeedback: consent.useHistory ? feedback : [],
            excludeTitles: excludeTitles,
            area: consent.useLocation ? area : nil,
            allowWebSearch: consent.allowWebSearch,
            // ユーザーがその場で選んだ気分は、提案のための明示的な入力なので許可の対象外
            mood: mood,
            // 体験の樹は体験帳から計算するので、体験帳を使う許可があるときだけ
            tree: consent.useHistory ? tree.flatMap { $0.isEmpty ? nil : $0 } : nil
        )
    }

    public func chatRequest(
        now: Date,
        turns: [ChatTurn],
        events: [CalendarEventSnapshot],
        consent: ConsentSnapshot,
        currentExperience: ExperienceRef?
    ) -> ChatRequest {
        ChatRequest(
            currentTime: APICoding.timestamp(now, timeZone: timeZone),
            timeZone: timeZone.identifier,
            locale: localeIdentifier,
            messages: Array(turns.suffix(maxChatTurns)),
            calendarContext: calendarItems(events, now: now, consent: consent, limit: maxChatEvents),
            currentExperience: consent.useHistory ? currentExperience : nil
        )
    }
}

/// 最近の会話のうち、体験生成に使ってよい短い発言だけを一時的に覚える。
/// 端末にも保存しない (保存する必要がないものは保存しない)。
@MainActor
public final class ConversationMemory {
    private var items: [(date: Date, text: String)] = []
    private let lifetime: TimeInterval
    private let capacity: Int

    public init(lifetime: TimeInterval = 6 * 3600, capacity: Int = 5) {
        self.lifetime = lifetime
        self.capacity = capacity
    }

    public func add(_ text: String, at date: Date) {
        items.append((date, text))
        items = Array(items.suffix(capacity))
    }

    public func recent(now: Date) -> [String] {
        items.removeAll { now.timeIntervalSince($0.date) > lifetime }
        return items.map(\.text)
    }

    public func clear() { items.removeAll() }
}

/// 端末の各機能から現在の状況を集めて、送信用のリクエストを作る。
@MainActor
public final class ContextAssembler {
    private let calendarProvider: any CalendarProviding
    private let locationProvider: any LocationProviding
    private let history: any HistoryRepository
    private let memory: ConversationMemory
    private let builder: ContextBuilder
    private let consent: @MainActor () -> ConsentSnapshot
    private let now: @Sendable () -> Date
    /// 体験の樹のいま (アプリ側で TreeSource をつなぐ。無ければ送らない)
    public var treeContext: @MainActor () -> TreeContext? = { nil }

    public init(
        calendarProvider: any CalendarProviding,
        locationProvider: any LocationProviding,
        history: any HistoryRepository,
        memory: ConversationMemory,
        builder: ContextBuilder = ContextBuilder(),
        consent: @escaping @MainActor () -> ConsentSnapshot,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.calendarProvider = calendarProvider
        self.locationProvider = locationProvider
        self.history = history
        self.memory = memory
        self.builder = builder
        self.consent = consent
        self.now = now
    }

    public var currentDate: Date { now() }
    public var calendarAccess: PermissionState { calendarProvider.access() }
    public var timeZone: TimeZone { builder.timeZone }
    public var calendar: Calendar { builder.calendar }

    public func requestCalendarAccess() async -> PermissionState {
        await calendarProvider.requestAccess()
    }

    private func events(at date: Date, consent: ConsentSnapshot) -> [CalendarEventSnapshot] {
        guard consent.useCalendar, calendarProvider.access() == .granted else { return [] }
        let window = builder.calendarWindow(now: date)
        return calendarProvider.events(from: window.start, to: window.end)
    }

    public func experienceRequest(excluding titles: [String] = [], mood: Mood? = nil) async -> ExperienceRequest {
        let date = now()
        let permissions = consent()
        let area = permissions.useLocation ? await locationProvider.currentArea() : nil
        // 自分で見つけて記した体験は、自分の言葉なので送らない (ひとことと同じ扱い)
        let entries = permissions.useHistory ? history.entries(since: nil, limit: 60).filter { !$0.isSelfRecorded }.prefix(40).map { $0 } : []
        return builder.experienceRequest(
            now: date,
            events: events(at: date, consent: permissions),
            consent: permissions,
            recentMessages: memory.recent(now: date),
            history: entries.prefix(builder.maxHistory).map { $0.reference(timeZone: builder.timeZone) },
            feedback: PreferenceTrends.signals(from: entries, now: date),
            excludeTitles: titles,
            area: area,
            mood: mood,
            tree: permissions.useHistory ? treeContext() : nil
        )
    }

    public func chatRequest(turns: [ChatTurn]) -> ChatRequest {
        let date = now()
        let permissions = consent()
        let active = history.activeEntry().map {
            ExperienceRef(title: $0.title, theme: $0.theme, reaction: .accepted, rating: nil, date: nil)
        }
        return builder.chatRequest(
            now: date,
            turns: turns,
            events: events(at: date, consent: permissions),
            consent: permissions,
            currentExperience: active
        )
    }

    /// 会話の発言を、体験生成の参考として一時的に覚える (許可されている場合のみ)
    public func rememberUtterance(_ text: String) {
        if consent().useChatContext { memory.add(text, at: now()) }
    }
}
