import Foundation
import Observation
import SwiftData
import SwiftUI
import TaikenCore

/// ビルド設定 (xcconfig → Info.plist) から読む値。秘密情報はここに置かない。
struct AppConfiguration {
    /// 開発用の既定の接続先。ユーザーが設定画面で接続先を保存すると、そちらが優先される
    let developmentBackendURL: URL?

    static func fromBundle(_ bundle: Bundle = .main) -> AppConfiguration {
        let raw = (bundle.object(forInfoDictionaryKey: "DevelopmentBackendURL") as? String)?.trimmingCharacters(in: .whitespaces)
        let url = raw.flatMap { $0.isEmpty || $0.hasPrefix("$(") ? nil : URL(string: $0) }
        return AppConfiguration(developmentBackendURL: url)
    }
}

/// 提案をつくるしくみ。画面に正直に表示する
enum ProposalEngine: Equatable, Sendable {
    /// 自分のサーバー (Backend) のAI
    case server
    /// 端末内のAI (Apple Intelligence)
    case onDevice
    /// 端末内の体験ライブラリ
    case library

    var label: String {
        switch self {
        case .server: "自分のサーバーのAI"
        case .onDevice: "Apple Intelligence（端末内）"
        case .library: "体験ライブラリ（端末内）"
        }
    }

    var detail: String {
        switch self {
        case .server: "予定や気分を、自分で用意したサーバー経由でAIに渡して提案をつくります。"
        case .onDevice: "この iPhone の中のAIが提案をつくります。予定や会話は端末の外に出ません。"
        case .library: "七十二候の季節の体験を含む体験ライブラリから、予定・気分・時間帯に合うものを選びます。何も外へ送りません。"
        }
    }

    /// 会話画面に添える説明 (AIでないときは正直に)
    var chatNote: String? {
        switch self {
        case .server: nil
        case .onDevice: "Apple Intelligence が端末内で応えています"
        case .library: "端末内のかんたんな応答です"
        }
    }
}

/// 接続先の変更に合わせて画面の表示を変えるための小さな状態
@MainActor
@Observable
final class EngineState {
    var engine: ProposalEngine
    init(_ engine: ProposalEngine) { self.engine = engine }
}

/// 画面の切り替え (通知から開いたときにシートを閉じる、など)
@MainActor
@Observable
final class AppRouter {
    enum Sheet: String, Identifiable {
        case chat, settings
        var id: String { rawValue }
    }

    enum Destination: Hashable {
        case journal
    }

    var sheet: Sheet?
    /// 体験帳 → 記録の詳細 と重ねていくので、型を混ぜられる NavigationPath を使う
    var path = NavigationPath()

    func openJournal() {
        sheet = nil
        path = NavigationPath()
        path.append(Destination.journal)
    }

    /// 通知・ウィジェットから開いたとき: ホームに戻す
    func returnHome() {
        sheet = nil
        path = NavigationPath()
    }
}

/// 依存関係の組み立て (composition root)。UIはここで作られた ViewModel だけを見る。
@MainActor
final class AppDependencies {
    let defaults: DefaultsStore
    let container: ModelContainer
    let router = AppRouter()
    let engineState: EngineState
    let diagnostics: any Diagnostics
    let locationProvider: any LocationProviding
    let home: HomeViewModel
    let chat: ChatViewModel
    let history: HistoryViewModel
    let settings: SettingsViewModel

    private let repository: any HistoryRepository
    private let memory = ConversationMemory()
    private let assembler: ContextAssembler
    private let service: RoutingExperienceService
    private let background: BackgroundCoordinator
    private let letters: any LetterScheduling

    init(
        configuration: AppConfiguration,
        defaults: DefaultsStore = DefaultsStore(),
        inMemory: Bool = false,
        calendarProvider: (any CalendarProviding)? = nil,
        locationProvider: (any LocationProviding)? = nil,
        connectionStore: (any ConnectionStore)? = nil,
        scheduler: (any NotificationScheduling)? = nil,
        letters: (any LetterScheduling)? = nil,
        presence: (any ExperiencePresence)? = nil,
        widgets: (any WidgetPublishing)? = nil,
        useOnDeviceAI: Bool = true,
        diagnostics: any Diagnostics = OSLogDiagnostics()
    ) {
        self.defaults = defaults
        self.diagnostics = diagnostics
        container = PersistenceFactory.makeContainer(inMemory: inMemory) { error in
            diagnostics.record("persistence.fallback_to_memory", ["error": String(describing: type(of: error))])
        }
        repository = SwiftDataHistoryRepository(context: container.mainContext)

        // 端末内の提案: Apple Intelligence が使えればそれを、使えなければ体験ライブラリを使う。
        // 端末内のAIの出力にも、サーバーと同じ安全確認をかける (SafeguardedExperienceService)
        let library = LocalExperienceService()
        var localService: any ExperienceService = library
        var onDeviceAvailable = false
        #if canImport(FoundationModels)
        if useOnDeviceAI {
            if #available(iOS 26.0, *) {
                if AppleIntelligenceExperienceService.isAvailable {
                    localService = SafeguardedExperienceService(primary: AppleIntelligenceExperienceService(), fallback: library, diagnostics: diagnostics)
                    onDeviceAvailable = true
                }
            }
        }
        #endif
        let local = localService
        let localEngine: ProposalEngine = onDeviceAvailable ? .onDevice : .library

        let installID = defaults.installID()
        let store = connectionStore ?? KeychainConnectionStore(defaults: defaults.defaults, developmentDefault: configuration.developmentBackendURL)
        let makeService: @Sendable (BackendEndpoint) -> any ExperienceService = { endpoint in
            BackendClient(endpoint: endpoint, installID: installID, diagnostics: diagnostics)
        }
        let saved = store.load()
        service = RoutingExperienceService(saved.map(makeService) ?? local)
        let engineState = EngineState(saved == nil ? localEngine : .server)
        self.engineState = engineState

        let calendar = calendarProvider ?? EventKitCalendarProvider()
        let location = locationProvider ?? CoarseLocationProvider()
        self.locationProvider = location
        let cache = UserDefaultsProposalCache(defaults: defaults.defaults)
        let notificationScheduler = scheduler ?? UserNotificationScheduler()
        let letterScheduler = letters ?? UserNotificationLetterScheduler()
        self.letters = letterScheduler

        let assembler = ContextAssembler(
            calendarProvider: calendar,
            locationProvider: location,
            history: repository,
            memory: memory,
            consent: { defaults.consent() }
        )
        self.assembler = assembler

        let presenceAdapter: any ExperiencePresence = presence ?? Self.makePresence()
        let home = HomeViewModel(
            service: service,
            fallbackService: local,
            assembler: assembler,
            history: repository,
            cache: cache,
            presence: presenceAdapter,
            widgets: widgets ?? AppGroupWidgetPublisher(store: AppGroup.widgetStore),
            presenceEnabled: { defaults.presenceEnabled },
            diagnostics: diagnostics
        )
        self.home = home
        chat = ChatViewModel(service: service, assembler: assembler, history: repository, diagnostics: diagnostics) { [weak home] experience in
            home?.adopt(experience)
        }
        history = HistoryViewModel(history: repository)
        background = BackgroundCoordinator(
            service: service,
            assembler: assembler,
            history: repository,
            scheduler: notificationScheduler,
            ledger: UserDefaultsNotificationLedger(defaults: defaults.defaults),
            cache: cache,
            preferences: { defaults.notificationPreferences() },
            diagnostics: diagnostics
        )

        let routing = service
        settings = SettingsViewModel(
            connectionStore: store,
            scheduler: notificationScheduler,
            defaults: defaults,
            makeService: makeService,
            onEndpointChange: { endpoint in
                routing.replace(with: endpoint.map(makeService) ?? local)
                engineState.engine = endpoint == nil ? localEngine : .server
            },
            onNotificationPreferencesChange: { preferences in
                BackgroundRefresh.schedule(at: NotificationPolicy.nextCheck(after: Date(), preferences: preferences, calendar: .current))
            },
            onDailyLetterChange: { [weak home] preferences in
                let plan = DailyLetter.plan(now: Date(), preferences: preferences, engagedToday: home?.engagedToday ?? false, calendar: .current)
                Task { await letterScheduler.replaceLetters(with: plan) }
            }
        )
    }

    private static func makePresence() -> any ExperiencePresence {
        #if canImport(ActivityKit)
        LiveActivityPresence()
        #else
        NoPresence()
        #endif
    }

    var isLocalMode: Bool { service.isLocal }

    /// 「AIに渡す内容を確かめる」用: 次に送るリクエストを、送らずに組み立てる
    func previewRequest() async -> ExperienceRequest {
        await assembler.experienceRequest(mood: home.mood)
    }

    // MARK: - バックグラウンド更新と通知

    func performBackgroundRefresh() async {
        let outcome = await background.refresh()
        diagnostics.record("background.outcome", ["value": String(describing: outcome)])
        scheduleBackgroundRefresh()
    }

    func scheduleBackgroundRefresh() {
        BackgroundRefresh.schedule(at: background.nextCheckDate())
    }

    /// 朝の便りを、今日の様子に合わせて予約し直す (今日すでに触れていれば今日の分は送らない)
    func rescheduleLetters() {
        let plan = DailyLetter.plan(now: Date(), preferences: defaults.dailyLetterPreferences(), engagedToday: home.engagedToday, calendar: .current)
        let scheduler = letters
        Task { await scheduler.replaceLetters(with: plan) }
    }

    /// 通知から開かれた: シートを閉じ、保存済みの提案を表示する。「やってみる」なら、そのまま体験を始める。
    /// 「あとで」はアプリを開かないボタンなので、何もしない (押しつけない)
    func handleNotification(action: String) async {
        guard action != NotificationAction.later, defaults.hasCompletedOnboarding else { return }
        router.returnHome()
        await home.refresh()
        if action == NotificationAction.accept, home.stage == .proposal {
            home.tryIt()
        }
        rescheduleLetters()
    }

    /// ウィジェット・ショートカットから開かれた (taiken://today, taiken://journal, taiken://talk)
    func open(_ url: URL) {
        guard url.scheme == DeepLink.scheme, defaults.hasCompletedOnboarding else { return }
        switch DeepLink(url: url) {
        case .journal:
            router.openJournal()
        case .talk:
            router.returnHome()
            router.sheet = .chat
        case .today, nil:
            router.returnHome()
            Task { await home.refresh() }
        }
    }

    /// はじめの案内を終えた
    func finishOnboarding() async {
        await home.refresh()
        rescheduleLetters()
    }

    // MARK: - データの削除

    func deleteAllLocalData() {
        do {
            try repository.deleteAll()
        } catch {
            diagnostics.record("data.delete_failed")
        }
        memory.clear()
        defaults.removeAll()
        AppGroup.widgetStore?.clear()
        chat.reset()
        home.resetAfterDataDeletion()
        history.reload()
        scheduleBackgroundRefresh()
        rescheduleLetters()
    }

    // MARK: - 起動

    /// アプリの起動時に使う組み立て。UIテスト (DEBUG ビルドで `-UITesting` 付き) のときだけ、
    /// 端末の状態に左右されない組み立て (メモリ上の保存先・見本の予定・端末内の体験ライブラリ) にする
    static func make(arguments: [String] = ProcessInfo.processInfo.arguments) -> AppDependencies {
        #if DEBUG
        if arguments.contains("-UITesting") {
            let deps = AppDependencies(
                configuration: AppConfiguration(developmentBackendURL: nil),
                inMemory: true,
                calendarProvider: FixedCalendarProvider.sample(),
                locationProvider: FixedLocationProvider(),
                connectionStore: InMemoryConnectionStore(),
                useOnDeviceAI: false
            )
            if arguments.contains("-UITestSeedJournal") {
                for entry in HistoryEntry.sampleJournal() { try? deps.repository.add(entry) }
                deps.history.reload()
            }
            return deps
        }
        #endif
        return AppDependencies(configuration: .fromBundle())
    }

    // MARK: - プレビュー

    static func preview(journal: Bool = true) -> AppDependencies {
        let suite = UserDefaults(suiteName: "preview") ?? .standard
        let deps = AppDependencies(
            configuration: AppConfiguration(developmentBackendURL: nil),
            defaults: DefaultsStore(suite),
            inMemory: true,
            calendarProvider: FixedCalendarProvider.sample(),
            locationProvider: FixedLocationProvider(),
            connectionStore: InMemoryConnectionStore(),
            scheduler: RecordingNotificationScheduler(),
            letters: RecordingLetterScheduler(),
            presence: NoPresence(),
            widgets: RecordingWidgetPublisher(),
            useOnDeviceAI: false,
            diagnostics: NoopDiagnostics()
        )
        if journal {
            for entry in HistoryEntry.sampleJournal() { try? deps.repository.add(entry) }
            deps.history.reload()
        }
        return deps
    }
}

/// 通知のボタン
enum NotificationAction {
    static let accept = "accept"
    static let later = "later"
    static let open = "open"
    static let experienceCategory = "experience"
}
