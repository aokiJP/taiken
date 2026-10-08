import Foundation
import Observation

/// Home (4.0): 真ん中は、自分の樹と「体験を記す」。
///
/// 体験は自分で生きて、自分で記す。記すと触れた要素に経験が積もり、段が上がると芽が出る。
/// AIや体験ライブラリの提案は「きっかけ」として、求められたときだけ差し出す (押しつけない)。
///
/// きっかけの流れ: きっかけをもらう → やってみる (体験中) → 記す (印・経験) → (しばらく通知を控える)
/// どの段階でも断れる。断っても、何も減らない。
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
        /// きっかけを用意している
        case loading
        /// きっかけ
        case proposal
        /// 体験中
        case active
        /// 記したばかり (印を押して、樹の伸びを見せるところ)
        case completed
        case failed(String)
        /// ふだん: 自分の樹と「体験を記す」
        case idle
    }

    public struct Notice: Equatable, Sendable {
        public enum Kind: Sendable { case degraded, offline, info, error }
        public let kind: Kind
        public let message: String
    }

    public private(set) var phase: Phase = .idle
    public private(set) var proposal: ExperienceResponse?
    /// 新しいきっかけが届くたびに変わる (表示の切り替えに使う)
    public private(set) var proposalID = UUID()
    /// きっかけが樹のどこにつながっているか
    public private(set) var proposalLineage: Lineage?
    public private(set) var activeEntry: HistoryEntry?
    /// 体験中の体験が樹のどこにつながっているか
    public private(set) var activeLineage: Lineage?
    /// 記したばかりの体験。閉じるか、アプリを閉じると消える
    public private(set) var completedEntry: HistoryEntry?
    /// 記したことで、樹がどう伸びたか (経験・段・芽・閃き・深まり)
    public private(set) var completedGrowth: GrowthReport = .empty
    /// 4.0 にしてはじめて開いたとき: これまでの体験から育っていたもの (一度だけ)
    public private(set) var welcome: GrowthReport?
    /// 「今はやらない」「記した」のあと、通知を控える時刻 (ホームの表示は変えない)
    public private(set) var restingUntil: Date?
    /// いま選んでいる気分 (その場かぎり)
    public private(set) var mood: Mood?
    public private(set) var todayEntries: [HistoryEntry] = []
    public private(set) var calendarAccess: PermissionState = .notDetermined
    public private(set) var notice: Notice?
    public private(set) var lastGeneratedAt: Date?
    public private(set) var timeOfDay: TimeOfDay
    /// 樹が変わるたびに増える (ホームの小さな樹と、樹のカードを描き直す合図)
    public private(set) var treeRevision = 0

    /// 「別の視点」で一度見た体験 (同じものを出さない)
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
    /// 技の樹 (無ければ樹のことは何もしない)
    public let trees: TreeSource?

    /// これより古いきっかけは、開き直したときに見せない (予定や時間帯に合わせたものなので)
    public var staleAfter: TimeInterval = 3 * 3600
    /// 「今はやらない」のあと、通知を控える長さ
    public var restAfterDecline: TimeInterval = 3 * 3600
    /// 体験を記したあと、通知を控える長さ
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
        trees: TreeSource? = nil,
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
        self.trees = trees
        self.diagnostics = diagnostics
        timeOfDay = TimeOfDay.at(assembler.currentDate, calendar: assembler.calendar)
    }

    public var isLoading: Bool { phase == .loading }

    public var stage: Stage {
        if activeEntry != nil { return .active }
        if completedEntry != nil { return .completed }
        if proposal != nil { return .proposal }
        if phase == .loading { return .loading }
        if case .failed(let message) = phase { return .failed(message) }
        return .idle
    }

    /// 今日すでに体験に触れたか (朝の便りを送らない判断に使う)
    public var engagedToday: Bool {
        if activeEntry != nil || hasTodayRecords { return true }
        return lastGeneratedAt.map { assembler.calendar.isDate($0, inSameDayAs: assembler.currentDate) } ?? false
    }

    // MARK: - ライフサイクル

    /// 画面表示・アプリ復帰・通知タップのたびに呼ぶ。きっかけは勝手には作らない (求められたときだけ)
    public func refresh() async {
        updateClock()
        calendarAccess = assembler.calendarAccess
        reloadHistory()
        let now = assembler.currentDate

        restingUntil = cache.loadRestingUntil()
        if let until = restingUntil, until <= now { endRest() }

        // 通知から用意されたきっかけ・さっき受け取ったきっかけ (今日の、新しいものだけ)
        if let cached = cache.load(), assembler.calendar.isDate(cached.generatedAt, inSameDayAs: now),
           now.timeIntervalSince(cached.generatedAt) <= staleAfter {
            if lastGeneratedAt.map({ cached.generatedAt > $0 }) ?? true {
                proposal = cached.response
                proposalID = UUID()
                lastGeneratedAt = cached.generatedAt
                phase = .ready
                notice = Self.notice(for: cached.response)
            }
        } else if proposal != nil, let generated = lastGeneratedAt, now.timeIntervalSince(generated) > staleAfter {
            // 古いきっかけは、黙って下げる (断ったことにはしない)
            proposal = nil
            proposalLineage = nil
            lastGeneratedAt = nil
            cache.clear()
            phase = .idle
        }

        if let trees {
            trees.settle()
            if welcome == nil, !trees.garden.seen {
                if let report = trees.welcome() {
                    welcome = report
                } else {
                    trees.markSeen()
                }
            }
        }
        refreshLineages()
        presence.sync(active: activeEntry)
        publishWidget()
    }

    /// 時間帯を今の時刻に合わせる (画面の時計から呼ぶ)
    public func updateClock() {
        let newTime = TimeOfDay.at(assembler.currentDate, calendar: assembler.calendar)
        if newTime != timeOfDay { timeOfDay = newTime }
    }

    public func requestCalendarAccess() async {
        calendarAccess = await assembler.requestCalendarAccess()
    }

    // MARK: - 体験を記す (自分で見つけた体験)

    /// 自分で見つけた体験を記す。触れた要素に経験が積もり、樹がどう伸びたかを返す
    @discardableResult
    public func record(_ draft: LivedDraft) -> GrowthReport {
        guard draft.isReady else { return .empty }
        let before = trees?.tree()
        let entry = HistoryEntry.lived(draft, at: assembler.currentDate)
        var saved = false
        persist {
            try history.add(entry)
            saved = true
        }
        guard saved else { return .empty }
        trees?.link(entry: entry.id, skills: draft.skills)
        trees?.settle()
        completedEntry = entry
        completedGrowth = growth(since: before, gained: entry.resolvedElements())
        welcome = nil
        trees?.markSeen()
        rest(for: restAfterCompletion)
        reloadHistory()
        refreshLineages()
        publishWidget()
        return completedGrowth
    }

    /// 記したところを閉じる (きっかけがあれば、そこへ戻る)
    public func dismissCompleted() {
        completedEntry = nil
        completedGrowth = .empty
    }

    /// 「これまでの体験から」を見届けた
    public func dismissWelcome() {
        welcome = nil
        trees?.markSeen()
    }

    // MARK: - きっかけ (求められたときだけ)

    /// きっかけをもらう
    public func requestPrompt() async {
        completedEntry = nil
        completedGrowth = .empty
        await generate()
    }

    /// きっかけを作れなかった知らせを閉じる (ふだんのホームに戻る)
    public func dismissFailure() {
        guard case .failed = phase else { return }
        phase = proposal == nil ? .idle : .ready
    }

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
            let message = (error as? LocalizedError)?.errorDescription ?? "きっかけを作れませんでした。"
            diagnostics.record("home.generate_failed", ["error": String(describing: error)])
            // 繋がらなくても止めない。端末内のAIまたは体験ライブラリに切り替える
            if let local = try? await fallbackService.generateExperience(request) {
                apply(local, at: generatedAt)
                notice = Notice(kind: .offline, message: "\(message) いまは端末内で選んでいます。")
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
        completedGrowth = .empty
        cache.save(CachedProposal(generatedAt: date, response: response))
        refreshLineages()
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
                return Notice(kind: .degraded, message: "AIのきっかけをうまく作れなかったため、体験ライブラリから選んでいます。")
            default:
                return Notice(kind: .degraded, message: "今はAIに繋がりにくいため、体験ライブラリから選んでいます。")
            }
        }
    }

    // MARK: - きっかけへの返事 (やってみる / 別の視点 / 今はやらない)

    public func tryIt() {
        guard let proposal else { return }
        let experience = place(proposal.experience)
        persist {
            activeEntry = try history.record(experience, theme: Self.theme(of: proposal), status: .active, at: assembler.currentDate)
        }
        clearProposal()
        reloadHistory()
        refreshLineages()
        if let activeEntry, presenceEnabled() { presence.begin(activeEntry) }
        publishWidget()
    }

    public func showAnother() async {
        guard let proposal else { return }
        persist { try history.record(proposal.experience, theme: Self.theme(of: proposal), status: .skipped, at: assembler.currentDate) }
        excludedTitles = Array((excludedTitles + [proposal.experience.title]).suffix(10))
        await generate()
    }

    /// 気分を選んで、その気分に合うきっかけをもらう。同じ気分をもう一度選ぶと解除する
    public func choose(mood newValue: Mood?) async {
        guard activeEntry == nil else { return }
        mood = newValue == mood ? nil : newValue
        // 気分が変わっただけで、今のきっかけを断ったわけではない (履歴には残さない)
        if let proposal { excludedTitles = Array((excludedTitles + [proposal.experience.title]).suffix(10)) }
        completedEntry = nil
        completedGrowth = .empty
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

    /// 体験中の体験を記す。使った技を選べる (稽古から始めた体験は、選ばなくてもその技に数える)
    public func finish(rating: Rating, note: String? = nil, skills: [String] = []) {
        guard let entry = activeEntry else { return }
        let before = trees?.tree()
        persist { try history.finish(id: entry.id, rating: rating, note: note, at: assembler.currentDate) }
        trees?.link(entry: entry.id, skills: skills)
        trees?.settle()
        let finished = history.entry(id: entry.id) ?? entry
        completedEntry = finished
        completedGrowth = growth(since: before, gained: finished.status == .completed ? finished.resolvedElements() : [])
        welcome = nil
        trees?.markSeen()
        activeEntry = nil
        excludedTitles = []
        mood = nil
        rest(for: restAfterCompletion)
        presence.end()
        reloadHistory()
        refreshLineages()
        publishWidget()
    }

    /// 体験をやめる (評価はしない。体験帳には残らない)
    public func abandonActive() {
        guard var entry = activeEntry else { return }
        entry.status = .declined
        entry.finishedAt = assembler.currentDate
        persist { try history.update(entry) }
        activeEntry = nil
        presence.end()
        reloadHistory()
        refreshLineages()
        publishWidget()
    }

    /// AIとの会話で出てきた体験を「やってみる」
    public func adopt(_ experience: Experience) {
        start(place(experience))
    }

    /// 樹の稽古から、体験をいま始める
    public func begin(_ experience: Experience) {
        start(place(experience))
    }

    private func start(_ experience: Experience) {
        if var current = activeEntry {
            current.status = .skipped
            persist { try history.update(current) }
        }
        persist { activeEntry = try history.record(experience, theme: nil, status: .active, at: assembler.currentDate) }
        clearProposal()
        completedEntry = nil
        completedGrowth = .empty
        reloadHistory()
        refreshLineages()
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

    /// 樹の画面で技を伸ばした・編んだ・結んだあと (ホームの小さな樹を描き直す)
    public func treeDidChange() {
        refreshLineages()
    }

    public func resetAfterDataDeletion() {
        clearProposal()
        activeEntry = nil
        completedEntry = nil
        completedGrowth = .empty
        welcome = nil
        excludedTitles = []
        mood = nil
        notice = nil
        phase = .idle
        endRest()
        presence.end()
        reloadHistory()
        refreshLineages()
        publishWidget()
    }

    // MARK: - 内部

    /// やってみる体験を樹の上に置く (樹が無ければ、要素だけ推し量って付ける)
    private func place(_ experience: Experience) -> Experience {
        if let trees { return trees.place(experience) }
        let elements = ElementClassifier.elements(of: experience)
        return experience.placed(nodeID: experience.nodeID, elements: elements, growsFrom: experience.growsFrom)
    }

    /// 記す前の樹と、いまの樹の差
    private func growth(since before: ExperienceTree?, gained elements: [String]) -> GrowthReport {
        guard let trees, let before else { return .empty }
        return GrowthReport.between(before, trees.tree(), gained: elements)
    }

    private func refreshLineages() {
        treeRevision += 1
        guard let trees else {
            proposalLineage = nil
            activeLineage = nil
            return
        }
        let tree = trees.tree()
        proposalLineage = proposal.map { trees.lineage(of: $0.experience, in: tree) }
        activeLineage = activeEntry.map { trees.lineage(of: $0.experience, in: tree) }
    }

    private func clearProposal() {
        proposal = nil
        proposalLineage = nil
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
            let elements = entry.resolvedElements()
            snapshot = WidgetSnapshot(
                kind: .active, title: entry.title, invitation: entry.invitation, reflectionQuestion: entry.reflectionQuestion,
                startedAt: entry.createdAt, sealCharacter: entry.sealCharacter,
                elementLabel: elements.first.flatMap { TaikenContent.shared.element($0)?.label }, updatedAt: now
            )
        } else if let experience = proposal?.experience {
            let elements = ElementClassifier.elements(of: experience)
            snapshot = WidgetSnapshot(
                kind: .proposal, title: experience.title, invitation: experience.invitation,
                reflectionQuestion: experience.reflectionQuestion, sealCharacter: ElementClassifier.glyph(for: elements),
                elementLabel: elements.first.flatMap { TaikenContent.shared.element($0)?.label }, updatedAt: now
            )
        } else if completedEntry != nil {
            snapshot = WidgetSnapshot(kind: .resting, updatedAt: now)
        } else {
            snapshot = WidgetSnapshot(kind: .empty, updatedAt: now)
        }
        widgets.publish(snapshot)
    }

    private static func theme(of response: ExperienceResponse) -> String? {
        response.detectedActions.first?.label
    }
}
