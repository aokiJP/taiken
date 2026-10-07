import Foundation
import Observation
import SwiftData
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

/// 画面の切り替え (通知から開いたときにシートを閉じる、など)
@MainActor
@Observable
final class AppRouter {
    enum Sheet: String, Identifiable {
        case chat, history, settings
        var id: String { rawValue }
    }

    var sheet: Sheet?
}

/// 依存関係の組み立て (composition root)。UIはここで作られた ViewModel だけを見る。
@MainActor
final class AppDependencies {
    let defaults: DefaultsStore
    let container: ModelContainer
    let router = AppRouter()
    let diagnostics: any Diagnostics
    let locationProvider: any LocationProviding
    let home: HomeViewModel
    let chat: ChatViewModel
    let history: HistoryViewModel
    let settings: SettingsViewModel

    private let repository: any HistoryRepository
    private let memory = ConversationMemory()
    private let service: RoutingExperienceService
    private let background: BackgroundCoordinator

    init(
        configuration: AppConfiguration,
        defaults: DefaultsStore = DefaultsStore(),
        inMemory: Bool = false,
        calendarProvider: (any CalendarProviding)? = nil,
        locationProvider: (any LocationProviding)? = nil,
        connectionStore: (any ConnectionStore)? = nil,
        scheduler: (any NotificationScheduling)? = nil,
        diagnostics: any Diagnostics = OSLogDiagnostics()
    ) {
        self.defaults = defaults
        self.diagnostics = diagnostics
        container = PersistenceFactory.makeContainer(inMemory: inMemory) { error in
            diagnostics.record("persistence.fallback_to_memory", ["error": String(describing: type(of: error))])
        }
        repository = SwiftDataHistoryRepository(context: container.mainContext)

        let installID = defaults.installID()
        let store = connectionStore ?? KeychainConnectionStore(defaults: defaults.defaults, developmentDefault: configuration.developmentBackendURL)
        let makeService: @Sendable (BackendEndpoint) -> any ExperienceService = { endpoint in
            BackendClient(endpoint: endpoint, installID: installID, diagnostics: diagnostics)
        }
        service = RoutingExperienceService(store.load().map(makeService) ?? LocalExperienceService())

        let calendar = calendarProvider ?? EventKitCalendarProvider()
        let location = locationProvider ?? CoarseLocationProvider()
        self.locationProvider = location
        let cache = UserDefaultsProposalCache(defaults: defaults.defaults)
        let notificationScheduler = scheduler ?? UserNotificationScheduler()

        let assembler = ContextAssembler(
            calendarProvider: calendar,
            locationProvider: location,
            history: repository,
            memory: memory,
            consent: { defaults.consent() }
        )

        let home = HomeViewModel(service: service, assembler: assembler, history: repository, cache: cache, diagnostics: diagnostics)
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
                routing.replace(with: endpoint.map(makeService) ?? LocalExperienceService())
            },
            onNotificationPreferencesChange: { preferences in
                BackgroundRefresh.schedule(at: NotificationPolicy.nextCheck(after: Date(), preferences: preferences, calendar: .current))
            }
        )
    }

    var isLocalMode: Bool { service.isLocal }

    // MARK: - バックグラウンド更新と通知

    func performBackgroundRefresh() async {
        let outcome = await background.refresh()
        diagnostics.record("background.outcome", ["value": String(describing: outcome)])
        scheduleBackgroundRefresh()
    }

    func scheduleBackgroundRefresh() {
        BackgroundRefresh.schedule(at: background.nextCheckDate())
    }

    /// 通知から開かれた: シートを閉じ、保存済みの提案を表示する
    func handleNotificationTap() async {
        router.sheet = nil
        await home.refresh()
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
        chat.reset()
        home.resetAfterDataDeletion()
        history.reload()
        scheduleBackgroundRefresh()
    }

    // MARK: - プレビュー

    static func preview() -> AppDependencies {
        let suite = UserDefaults(suiteName: "preview") ?? .standard
        return AppDependencies(
            configuration: AppConfiguration(developmentBackendURL: nil),
            defaults: DefaultsStore(suite),
            inMemory: true,
            calendarProvider: FixedCalendarProvider.sample(),
            locationProvider: FixedLocationProvider(),
            connectionStore: InMemoryConnectionStore(),
            scheduler: RecordingNotificationScheduler(),
            diagnostics: NoopDiagnostics()
        )
    }
}
