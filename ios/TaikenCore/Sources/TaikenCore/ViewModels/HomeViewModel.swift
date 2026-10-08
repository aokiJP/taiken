import Foundation
import Observation

/// Home (指示書 §6, §21): 「今日何をするか」ではなく「今日、何を体験できるか」を中心に置く。
///
/// 一日の流れ:
/// 提案 → やってみる (体験中) → 振り返って記す (体験帳に印) → ひと休み → また提案
/// どの段階でも断れる。断ったあとはしばらく提案を控え、押しつけない。
@MainActor
@Observable
public final class HomeViewModel {
    public enum Phase: Equatable, Sendable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    /// 画面の中心に出すもの
    public enum Stage: Equatable, Sendable {
        case loading
        case proposal
        case active
        /// 記したばかり (印を押したところ)
        case completed
        /// 「今はやらない」「終えた」のあとのひと休み
        case resting(until: Date)
        case failed(String)
        case idle
    }

    public struct Notice: Equatable, Sendable {
        public enum Kind: Sendable { case degraded, offline, info, error }
        public let kind: Kind
        public let message: String
    }

    public private(set) var phase: Phase = .idle
    public private(set) var proposal: ExperienceResponse?
    /// 新しい提案が届くたびに変わる (表示の切り替えに使う)
    public private(set) var proposalID = UUID()
    public private(set) var activeEntry: HistoryEntry?
    /// 記したばかりの体験。アプリを閉じると消える (ひと休みは残る)
    public private(set) var completedEntry: HistoryEntry?
    public private(set) var restingUntil: Date?
    /// いま選んでいる気分 (その場かぎり)
    public private(set) var mood: Mood?
    public private(set) var todayEntries: [HistoryEntry] = []
    public private(set) var calendarAccess: PermissionState = .notDetermined
    public private(set) var notice: Notice?
    public private(set) var lastGeneratedAt: Date?
    public private(set) var season: MicroSeason
    public private(set) var timeOfDay: TimeOfDay

    /// 「別の提案」で一度見た体験 (同じものを出さない)
    private var excludedTitles: [String] = []
    private var hasTodayRecords = false

    private let service: any ExperienceService
    private let fallbackService: any ExperienceService
    private let assembler: ContextAssembler
    private let history: any HistoryRepository
    private let cache: any ProposalCaching
    private let presence: any ExperiencePresence
    private let widgets: (any WidgetPublishing)?
    private let presenceEnabled: @MainActor () -> Bool
    private let diagnostics: any Diagnostics

    /// これより古い提案は、開き直したときに作り直す
    public var staleAfter: TimeInterval = 30 * 60
    /// 「今はやらない」のあと、提案を控える長さ
    public var restAfterDecline: TimeInterval = 3 * 3600
    /// 体験を記したあと、次の提案を控える長さ
    public var restAfterCompletion: TimeInterval = 3600

    public init(
        service: any ExperienceService,
        fallbackService: any ExperienceService = LocalExperienceService(),
        assembler: ContextAssembler,
        history: any HistoryRepository,
        cache: any ProposalCaching,
        presence: (any ExperiencePresence)? = nil,
        widgets: (any WidgetPublishing)? = nil,
        presenceEnabled: @escaping @MainActor () -> Bool = { true },
        diagnostics: any Diagnostics = NoopDiagnostics()
    ) {
        self.service = service
        self.fallbackService = fallbackService
        self.assembler = assembler
        self.history = history
        self.cache = cache
        self.presence = presence ?? NoPresence()
        self.widgets = widgets
        self.presenceEnabled = presenceEnabled
        self.diagnostics = diagnostics
        let now = assembler.currentDate
        season = MicroSeason.at(now, calendar: assembler.calendar)
        timeOfDay = TimeOfDay.at(now, calendar: assembler.calendar)
    }

    public var isLoading: Bool { phase == .loading }

    public var stage: Stage {
        if activeEntry != nil { return .active }
        if completedEntry != nil { return .completed }
        if proposal != nil { return .proposal }
        if phase == .loading { return .loading }
        if case .failed(let message) = phase { return .failed(message) }
        if let restingUntil, restingUntil > assembler.currentDate { return .resting(until: restingUntil) }
        return .idle
    }

    /// 今日すでに体験に触れたか (朝の便りを送らない判断に使う)
    public var engagedToday: Bool {
        if activeEntry != nil || hasTodayRecords { return true }
        return lastGeneratedAt.map { assembler.calendar.isDate($0, inSameDayAs: assembler.currentDate) } ?? false
    }

    // MARK: - ライフサイクル

    /// 画面表示・アプリ復帰・通知タップのたびに呼ぶ。必要なときだけ提案を作る
    public func refresh() async {
        updateClock()
        calendarAccess = assembler.calendarAccess
        reloadHistory()
        let now = assembler.currentDate

        restingUntil = cache.loadRestingUntil()
        if let until = restingUntil, until <= now {
            endRest()
            completedEntry = nil
        }

        if let cached = cache.load(), assembler.calendar.isDate(cached.generatedAt, inSameDayAs: now) {
            if lastGeneratedAt.map({ cached.generatedAt > $0 }) ?? true {
                proposal = cached.response
                proposalID = UUID()
                lastGeneratedAt = cached.generatedAt
                phase = .ready
                notice = Self.notice(for: cached.response)
            }
        }
        presence.sync(active: activeEntry)
        publishWidget()

        guard activeEntry == nil, completedEntry == nil, restingUntil == nil else { return }
        let stale = lastGeneratedAt.map { now.timeIntervalSince($0) > staleAfter } ?? true
        if proposal == nil || stale { await generate() }
    }

    /// 季節と時間帯を今の時刻に合わせる (画面の時計から呼ぶ)
    public func updateClock() {
        let now = assembler.currentDate
        let newSeason = MicroSeason.at(now, calendar: assembler.calendar)
        let newTime = TimeOfDay.at(now, calendar: assembler.calendar)
        if newSeason != season { season = newSeason }
        if newTime != timeOfDay { timeOfDay = newTime }
    }

    public func requestCalendarAccess() async {
        calendarAccess = await assembler.requestCalendarAccess()
        if calendarAccess == .granted, activeEntry == nil, completedEntry == nil { await generate() }
    }

    // MARK: - 体験の生成

    public func generate() async {
        guard phase != .loading else { return }
        phase = .loading
        updateClock()
        let request = await assembler.experienceRequest(excluding: excludedTitles, mood: mood)
        let generatedAt = assembler.currentDate

        do {
            let response = try await service.generateExperience(request)
            apply(response, at: generatedAt)
            notice = Self.notice(for: response)
        } catch is CancellationError {
            phase = proposal == nil ? .idle : .ready
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? "提案を作れませんでした。"
            diagnostics.record("home.generate_failed", ["error": String(describing: error)])
            // 繋がらなくても体験は止めない。端末内のAIまたは体験ライブラリに切り替える
            if let local = try? await fallbackService.generateExperience(request) {
                apply(local, at: generatedAt)
                notice = Notice(kind: .offline, message: "\(message) いまは端末内で提案しています。")
            } else {
                phase = .failed(message)
            }
        }
        publishWidget()
    }

    private func apply(_ response: ExperienceResponse, at date: Date) {
        proposal = response
        proposalID = UUID()
        lastGeneratedAt = date
        phase = .ready
        completedEntry = nil
        endRest()
        cache.save(CachedProposal(generatedAt: date, response: response))
    }

    static func notice(for response: ExperienceResponse) -> Notice? {
        switch response.source {
        case .ai, .mock, .onDevice, .local:
            // 端末内のライブラリは正常な動作なので知らせない (カードに小さく出所を出す)
            return nil
        case .fallback:
            switch response.fallbackReason {
            case .budgetExceeded:
                return Notice(kind: .degraded, message: "今日のAI利用の上限に達したため、体験ライブラリから選んでいます。")
            case .invalidOutput, .unsafeOutput:
                return Notice(kind: .degraded, message: "AIの提案をうまく作れなかったため、体験ライブラリから選んでいます。")
            default:
                return Notice(kind: .degraded, message: "今はAIに繋がりにくいため、体験ライブラリから選んでいます。")
            }
        }
    }

    // MARK: - ユーザーの選択 (指示書 §11 原則4: やってみる / 別の案 / 今はやらない)

    public func tryIt() {
        guard let proposal else { return }
        persist {
            activeEntry = try history.record(proposal.experience, theme: Self.theme(of: proposal), status: .active, at: assembler.currentDate)
        }
        clearProposal()
        reloadHistory()
        if let activeEntry, presenceEnabled() { presence.begin(activeEntry) }
        publishWidget()
    }

    public func showAnother() async {
        guard let proposal else { return }
        persist { try history.record(proposal.experience, theme: Self.theme(of: proposal), status: .skipped, at: assembler.currentDate) }
        excludedTitles = Array((excludedTitles + [proposal.experience.title]).suffix(10))
        await generate()
    }

    /// 気分を選んで、その気分に合う提案をもらう。同じ気分をもう一度選ぶと解除する
    public func choose(mood newValue: Mood?) async {
        guard activeEntry == nil else { return }
        mood = newValue == mood ? nil : newValue
        // 気分が変わっただけで、今の提案を断ったわけではない (履歴には残さない)
        if let proposal { excludedTitles = Array((excludedTitles + [proposal.experience.title]).suffix(10)) }
        completedEntry = nil
        endRest()
        await generate()
    }

    public func notNow() {
        guard let proposal else { return }
        persist { try history.record(proposal.experience, theme: Self.theme(of: proposal), status: .declined, at: assembler.currentDate) }
        clearProposal()
        phase = .idle
        rest(for: restAfterDecline)
        reloadHistory()
        publishWidget()
    }

    public func finish(rating: Rating, note: String? = nil) {
        guard let entry = activeEntry else { return }
        persist { try history.finish(id: entry.id, rating: rating, note: note, at: assembler.currentDate) }
        completedEntry = history.entry(id: entry.id) ?? entry
        activeEntry = nil
        excludedTitles = []
        mood = nil
        rest(for: restAfterCompletion)
        presence.end()
        reloadHistory()
        publishWidget()
    }

    /// 体験をやめる (評価はしない)
    public func abandonActive() {
        guard var entry = activeEntry else { return }
        entry.status = .declined
        entry.finishedAt = assembler.currentDate
        persist { try history.update(entry) }
        activeEntry = nil
        presence.end()
        reloadHistory()
        publishWidget()
    }

    /// ひと休みをやめて、すぐに提案をもらう
    public func wakeUp() async {
        completedEntry = nil
        endRest()
        await generate()
    }

    /// AIチャットで提案された体験を「やってみる」
    public func adopt(_ experience: Experience) {
        if var current = activeEntry {
            current.status = .skipped
            persist { try history.update(current) }
        }
        persist { activeEntry = try history.record(experience, theme: nil, status: .active, at: assembler.currentDate) }
        clearProposal()
        completedEntry = nil
        endRest()
        reloadHistory()
        if let activeEntry, presenceEnabled() { presence.begin(activeEntry) }
        publishWidget()
    }

    /// ロック画面に置く設定が変わった
    public func presenceSettingChanged(enabled: Bool) {
        if enabled, let activeEntry {
            presence.begin(activeEntry)
        } else if !enabled {
            presence.end()
        }
    }

    public func resetAfterDataDeletion() {
        clearProposal()
        activeEntry = nil
        completedEntry = nil
        excludedTitles = []
        mood = nil
        notice = nil
        phase = .idle
        endRest()
        presence.end()
        reloadHistory()
        publishWidget()
    }

    // MARK: - 内部

    private func clearProposal() {
        proposal = nil
        lastGeneratedAt = nil
        cache.clear()
    }

    private func rest(for duration: TimeInterval) {
        let until = assembler.currentDate.addingTimeInterval(duration)
        restingUntil = until
        cache.saveRestingUntil(until)
    }

    private func endRest() {
        restingUntil = nil
        cache.saveRestingUntil(nil)
    }

    private func persist(_ work: () throws -> Void) {
        do {
            try work()
        } catch {
            diagnostics.record("home.persist_failed")
            notice = Notice(kind: .error, message: AppError.storage.errorDescription ?? "")
        }
    }

    private func reloadHistory() {
        activeEntry = history.activeEntry()
        let start = assembler.calendar.startOfDay(for: assembler.currentDate)
        let today = history.entries(since: start, limit: nil)
        todayEntries = today.filter(\.wasChosen)
        hasTodayRecords = !today.isEmpty
    }

    private func publishWidget() {
        guard let widgets else { return }
        let now = assembler.currentDate
        let snapshot: WidgetSnapshot
        if let entry = activeEntry {
            snapshot = WidgetSnapshot(
                kind: .active, title: entry.title, invitation: entry.invitation, reflectionQuestion: entry.reflectionQuestion,
                startedAt: entry.createdAt, sealCharacter: entry.sealCharacter, season: season, updatedAt: now
            )
        } else if let experience = proposal?.experience {
            snapshot = WidgetSnapshot(
                kind: .proposal, title: experience.title, invitation: experience.invitation,
                reflectionQuestion: experience.reflectionQuestion,
                sealCharacter: ExperienceTag.sealCharacter(ExperienceTag.primary(of: experience.tags)),
                season: season, updatedAt: now
            )
        } else if restingUntil != nil || completedEntry != nil {
            snapshot = WidgetSnapshot(kind: .resting, season: season, updatedAt: now)
        } else {
            snapshot = WidgetSnapshot(kind: .empty, season: season, updatedAt: now)
        }
        widgets.publish(snapshot)
    }

    private static func theme(of response: ExperienceResponse) -> String? {
        response.detectedActions.first?.label
    }
}
