import Foundation
import Observation

/// Home (指示書 §6, §21): 「今日何をするか」ではなく「今日、何を体験できるか」を中心に置く。
@MainActor
@Observable
public final class HomeViewModel {
    public enum Phase: Equatable, Sendable {
        case idle
        case loading
        case ready
        case failed(String)
    }

    public struct Notice: Equatable, Sendable {
        public enum Kind: Sendable { case degraded, offline, info, error }
        public let kind: Kind
        public let message: String
    }

    public private(set) var phase: Phase = .idle
    public private(set) var proposal: ExperienceResponse?
    public private(set) var activeEntry: HistoryEntry?
    public private(set) var todayEntries: [HistoryEntry] = []
    public private(set) var calendarAccess: PermissionState = .notDetermined
    public private(set) var notice: Notice?
    public private(set) var lastGeneratedAt: Date?

    /// 「別の提案」で一度見た体験 (同じものを出さない)
    private var excludedTitles: [String] = []

    private let service: any ExperienceService
    private let fallbackService: any ExperienceService
    private let assembler: ContextAssembler
    private let history: any HistoryRepository
    private let cache: any ProposalCaching
    private let diagnostics: any Diagnostics
    /// これより古い提案は、開き直したときに作り直す
    public var staleAfter: TimeInterval = 30 * 60

    public init(
        service: any ExperienceService,
        fallbackService: any ExperienceService = LocalExperienceService(),
        assembler: ContextAssembler,
        history: any HistoryRepository,
        cache: any ProposalCaching,
        diagnostics: any Diagnostics = NoopDiagnostics()
    ) {
        self.service = service
        self.fallbackService = fallbackService
        self.assembler = assembler
        self.history = history
        self.cache = cache
        self.diagnostics = diagnostics
    }

    public var isLoading: Bool { phase == .loading }

    // MARK: - ライフサイクル

    /// 画面表示・アプリ復帰・通知タップのたびに呼ぶ。必要なときだけAIを呼ぶ
    public func refresh() async {
        calendarAccess = assembler.calendarAccess
        reloadHistory()
        let now = assembler.currentDate

        if let cached = cache.load(), assembler.calendar.isDate(cached.generatedAt, inSameDayAs: now) {
            if lastGeneratedAt.map({ cached.generatedAt > $0 }) ?? true {
                proposal = cached.response
                lastGeneratedAt = cached.generatedAt
                phase = .ready
                notice = Self.notice(for: cached.response)
            }
        }
        guard activeEntry == nil else { return }
        let stale = lastGeneratedAt.map { now.timeIntervalSince($0) > staleAfter } ?? true
        if proposal == nil || stale { await generate() }
    }

    public func requestCalendarAccess() async {
        calendarAccess = await assembler.requestCalendarAccess()
        if calendarAccess == .granted, activeEntry == nil { await generate() }
    }

    // MARK: - 体験の生成

    public func generate() async {
        guard phase != .loading else { return }
        phase = .loading
        let request = await assembler.experienceRequest(excluding: excludedTitles)
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
            // オフラインでも最低限のUIを出すため、端末内の簡易提案に切り替える
            if let local = try? await fallbackService.generateExperience(request) {
                apply(local, at: generatedAt)
                notice = Notice(kind: .offline, message: "\(message) 端末内の簡易提案を表示しています。")
            } else {
                phase = .failed(message)
            }
        }
    }

    private func apply(_ response: ExperienceResponse, at date: Date) {
        proposal = response
        lastGeneratedAt = date
        phase = .ready
        cache.save(CachedProposal(generatedAt: date, response: response))
    }

    static func notice(for response: ExperienceResponse) -> Notice? {
        switch response.source {
        case .ai, .mock:
            return nil
        case .local:
            return Notice(kind: .info, message: "接続先が未設定のため、端末内の簡易提案です。設定から接続できます。")
        case .fallback:
            switch response.fallbackReason {
            case .budgetExceeded:
                return Notice(kind: .degraded, message: "今日のAI利用の上限に達したため、簡易的な提案です。")
            case .invalidOutput, .unsafeOutput:
                return Notice(kind: .degraded, message: "AIの提案をうまく作れなかったため、簡易的な提案です。")
            default:
                return Notice(kind: .degraded, message: "今はAIに繋がりにくいため、簡易的な提案です。")
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
    }

    public func showAnother() async {
        guard let proposal else { return }
        persist { try history.record(proposal.experience, theme: Self.theme(of: proposal), status: .skipped, at: assembler.currentDate) }
        excludedTitles = Array((excludedTitles + [proposal.experience.title]).suffix(10))
        await generate()
    }

    public func notNow() {
        guard let proposal else { return }
        persist { try history.record(proposal.experience, theme: Self.theme(of: proposal), status: .declined, at: assembler.currentDate) }
        clearProposal()
        phase = .idle
    }

    public func finish(rating: Rating, note: String? = nil) {
        guard let activeEntry else { return }
        persist { try history.finish(id: activeEntry.id, rating: rating, note: note, at: assembler.currentDate) }
        self.activeEntry = nil
        excludedTitles = []
        reloadHistory()
    }

    /// 体験をやめる (評価はしない)
    public func abandonActive() {
        guard var entry = activeEntry else { return }
        entry.status = .declined
        entry.finishedAt = assembler.currentDate
        persist { try history.update(entry) }
        activeEntry = nil
        reloadHistory()
    }

    /// AIチャットで提案された体験を「やってみる」
    public func adopt(_ experience: Experience) {
        if var current = activeEntry {
            current.status = .skipped
            persist { try history.update(current) }
        }
        persist { activeEntry = try history.record(experience, theme: nil, status: .active, at: assembler.currentDate) }
        clearProposal()
        reloadHistory()
    }

    public func resetAfterDataDeletion() {
        clearProposal()
        activeEntry = nil
        excludedTitles = []
        notice = nil
        phase = .idle
        reloadHistory()
    }

    // MARK: - 内部

    private func clearProposal() {
        proposal = nil
        lastGeneratedAt = nil
        cache.clear()
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
        todayEntries = history.entries(since: start, limit: nil).filter(\.wasChosen)
    }

    private static func theme(of response: ExperienceResponse) -> String? {
        response.detectedActions.first?.label
    }
}
