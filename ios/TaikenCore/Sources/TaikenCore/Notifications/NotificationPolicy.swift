import Foundation

/// 指示書 §12: 「価値がある AND 今が適切 AND 負担をかけない」ときだけ通知する。
/// サーバー (AI + 決定的ルール) の判断に加えて、端末側でユーザーの設定を最終的に適用する。
public enum NotificationPolicy {
    public enum SkipReason: String, Sendable, Equatable {
        case disabled
        case notAuthorized
        case quietHours
        case dailyLimit
        case tooSoon
        case busyWithExperience
        /// 「今はやらない」のあとのひと休み中
        case resting
        case notSuggested
        case fallbackResult
    }

    public enum Decision: Sendable, Equatable {
        case deliver(NotificationContent)
        case skip(SkipReason)
    }

    public static func isQuiet(hour: Int, start: Int, end: Int) -> Bool {
        if start == end { return false }
        return start < end ? (hour >= start && hour < end) : (hour >= start || hour < end)
    }

    /// AIを呼ぶ前の確認。ここで止まればAI利用も通信も発生しない (必要時接続)
    public static func precheck(
        preferences: NotificationPreferences,
        authorization: NotificationAuthorization,
        deliveries: [Date],
        hasActiveExperience: Bool,
        isResting: Bool = false,
        now: Date,
        calendar: Calendar
    ) -> SkipReason? {
        let p = preferences.normalized
        guard p.enabled else { return .disabled }
        guard authorization == .authorized else { return .notAuthorized }
        if isQuiet(hour: calendar.component(.hour, from: now), start: p.quietStartHour, end: p.quietEndHour) { return .quietHours }
        let startOfDay = calendar.startOfDay(for: now)
        if deliveries.filter({ $0 >= startOfDay }).count >= p.maxPerDay { return .dailyLimit }
        if let last = deliveries.max(), now.timeIntervalSince(last) < TimeInterval(p.minimumIntervalHours) * 3600 { return .tooSoon }
        if hasActiveExperience { return .busyWithExperience }
        if isResting { return .resting }
        return nil
    }

    public static func decide(
        response: ExperienceResponse,
        preferences: NotificationPreferences,
        authorization: NotificationAuthorization,
        deliveries: [Date],
        hasActiveExperience: Bool,
        isResting: Bool = false,
        now: Date,
        calendar: Calendar
    ) -> Decision {
        if let reason = precheck(preferences: preferences, authorization: authorization, deliveries: deliveries, hasActiveExperience: hasActiveExperience, isResting: isResting, now: now, calendar: calendar) {
            return .skip(reason)
        }
        guard response.source == .ai || response.source == .mock else { return .skip(.fallbackResult) }
        guard response.shouldNotify, let content = response.notification else { return .skip(.notSuggested) }
        return .deliver(content)
    }

    /// 次にバックグラウンドで確認してよい最も早い時刻。通知がオフなら nil
    public static func nextCheck(after now: Date, preferences: NotificationPreferences, calendar: Calendar, interval: TimeInterval = 2 * 3600) -> Date? {
        let p = preferences.normalized
        guard p.enabled else { return nil }
        let candidate = now.addingTimeInterval(interval)
        let hour = calendar.component(.hour, from: candidate)
        guard isQuiet(hour: hour, start: p.quietStartHour, end: p.quietEndHour) else { return candidate }
        // 静かな時間帯に入るなら、その終わりまで待つ
        var components = calendar.dateComponents([.year, .month, .day], from: candidate)
        components.hour = p.quietEndHour
        components.minute = 0
        guard let sameDay = calendar.date(from: components) else { return candidate }
        return sameDay > candidate ? sameDay : calendar.date(byAdding: .day, value: 1, to: sameDay)
    }
}

/// バックグラウンド更新で「通知する価値のある体験があるか」を確かめ、必要なときだけ通知する。
@MainActor
public final class BackgroundCoordinator {
    public enum Outcome: Sendable, Equatable {
        case delivered(String)
        case skipped(NotificationPolicy.SkipReason)
        case failed
    }

    private let service: any ExperienceService
    private let assembler: ContextAssembler
    private let history: any HistoryRepository
    private let scheduler: any NotificationScheduling
    private let ledger: any NotificationLedger
    private let cache: any ProposalCaching
    private let preferences: @MainActor () -> NotificationPreferences
    private let diagnostics: any Diagnostics

    public init(
        service: any ExperienceService,
        assembler: ContextAssembler,
        history: any HistoryRepository,
        scheduler: any NotificationScheduling,
        ledger: any NotificationLedger,
        cache: any ProposalCaching,
        preferences: @escaping @MainActor () -> NotificationPreferences,
        diagnostics: any Diagnostics = NoopDiagnostics()
    ) {
        self.service = service
        self.assembler = assembler
        self.history = history
        self.scheduler = scheduler
        self.ledger = ledger
        self.cache = cache
        self.preferences = preferences
        self.diagnostics = diagnostics
    }

    public func refresh() async -> Outcome {
        let now = assembler.currentDate
        let calendar = assembler.calendar
        let prefs = preferences()
        let authorization = await scheduler.authorization()
        let deliveries = ledger.deliveries(since: now.addingTimeInterval(-2 * 86_400))
        let hasActive = history.activeEntry() != nil
        let resting = cache.loadRestingUntil().map { $0 > now } ?? false

        if let reason = NotificationPolicy.precheck(preferences: prefs, authorization: authorization, deliveries: deliveries, hasActiveExperience: hasActive, isResting: resting, now: now, calendar: calendar) {
            diagnostics.record("background.skipped", ["reason": reason.rawValue])
            return .skipped(reason)
        }
        // 端末内モードではAIの判断が無いので通知しない
        if service.isLocal { return .skipped(.notSuggested) }

        let response: ExperienceResponse
        do {
            response = try await service.generateExperience(await assembler.experienceRequest())
        } catch {
            diagnostics.record("background.failed", ["error": String(describing: type(of: error))])
            return .failed
        }

        let decision = NotificationPolicy.decide(response: response, preferences: prefs, authorization: authorization, deliveries: deliveries, hasActiveExperience: hasActive, isResting: resting, now: now, calendar: calendar)
        switch decision {
        case .skip(let reason):
            diagnostics.record("background.skipped", ["reason": reason.rawValue])
            return .skipped(reason)
        case .deliver(let content):
            // 通知を開いたときに同じ提案が表示されるよう、先に保存しておく
            cache.save(CachedProposal(generatedAt: now, response: response))
            do {
                try await scheduler.deliver(content, identifier: "experience-\(Int(now.timeIntervalSince1970))")
                ledger.recordDelivery(at: now)
                diagnostics.record("background.delivered")
                return .delivered(content.title)
            } catch {
                diagnostics.record("background.deliver_failed")
                return .failed
            }
        }
    }

    public func nextCheckDate() -> Date? {
        NotificationPolicy.nextCheck(after: assembler.currentDate, preferences: preferences(), calendar: assembler.calendar)
    }
}
