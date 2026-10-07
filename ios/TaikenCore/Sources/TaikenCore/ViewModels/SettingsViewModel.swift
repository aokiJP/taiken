import Foundation
import Observation

/// 接続先・通知・データの設定。情報の種類ごとの許可 (ConsentKey) は画面側で直接保存する。
@MainActor
@Observable
public final class SettingsViewModel {
    public enum ConnectionState: Equatable, Sendable {
        case idle
        case testing
        case connected(ServiceStatus)
        case failed(String)
    }

    // MARK: 接続
    public var baseURLText: String
    /// 入力中のトークン。保存済みのトークンは画面に出さない
    public var tokenText = ""
    public private(set) var hasSavedToken: Bool
    public private(set) var isConfigured: Bool
    public private(set) var connectionState: ConnectionState = .idle
    public private(set) var validationMessage: String?

    // MARK: 通知
    public private(set) var notificationPreferences: NotificationPreferences
    public private(set) var notificationAuthorization: NotificationAuthorization = .notDetermined
    public private(set) var notificationMessage: String?

    private let connectionStore: any ConnectionStore
    private let scheduler: any NotificationScheduling
    private let defaults: DefaultsStore
    private let onEndpointChange: @MainActor (BackendEndpoint?) -> Void
    private let onNotificationPreferencesChange: @MainActor (NotificationPreferences) -> Void
    private let makeService: @Sendable (BackendEndpoint) -> any ExperienceService

    public init(
        connectionStore: any ConnectionStore,
        scheduler: any NotificationScheduling,
        defaults: DefaultsStore,
        makeService: @escaping @Sendable (BackendEndpoint) -> any ExperienceService,
        onEndpointChange: @escaping @MainActor (BackendEndpoint?) -> Void,
        onNotificationPreferencesChange: @escaping @MainActor (NotificationPreferences) -> Void = { _ in }
    ) {
        self.connectionStore = connectionStore
        self.scheduler = scheduler
        self.defaults = defaults
        self.makeService = makeService
        self.onEndpointChange = onEndpointChange
        self.onNotificationPreferencesChange = onNotificationPreferencesChange
        let saved = connectionStore.load()
        baseURLText = saved?.baseURL.absoluteString ?? ""
        hasSavedToken = saved?.token != nil
        isConfigured = saved != nil
        notificationPreferences = defaults.notificationPreferences()
    }

    public func onAppear() async {
        notificationAuthorization = await scheduler.authorization()
        if notificationPreferences.enabled, notificationAuthorization == .denied {
            notificationMessage = "iOSの設定で通知が許可されていないため、通知は届きません。"
        }
    }

    // MARK: - 接続

    /// 入力内容を検証して保存し、接続テストまで行う
    public func saveAndTestConnection() async {
        validationMessage = nil
        let url: URL
        switch EndpointValidator.validate(baseURLText) {
        case .success(let value): url = value
        case .failure(let problem):
            validationMessage = problem.message
            return
        }
        let newToken = tokenText.trimmingCharacters(in: .whitespacesAndNewlines)
        let token = newToken.isEmpty ? connectionStore.load()?.token : newToken
        let endpoint = BackendEndpoint(baseURL: url, token: token)

        connectionState = .testing
        let status: ServiceStatus
        do {
            status = try await makeService(endpoint).status()
        } catch {
            // 接続できない設定は保存しない (今の接続を壊さない)
            connectionState = .failed((error as? LocalizedError)?.errorDescription ?? "接続できませんでした。")
            return
        }
        do {
            try connectionStore.save(endpoint)
        } catch {
            connectionState = .failed(AppError.storage.errorDescription ?? "")
            return
        }
        tokenText = ""
        hasSavedToken = endpoint.token != nil
        isConfigured = true
        baseURLText = url.absoluteString
        connectionState = .connected(status)
        onEndpointChange(endpoint)
    }

    /// 保存済みの接続先で接続テストだけ行う
    public func testSavedConnection() async {
        guard let endpoint = connectionStore.load() else {
            connectionState = .failed(AppError.notConfigured.errorDescription ?? "")
            return
        }
        connectionState = .testing
        do {
            connectionState = .connected(try await makeService(endpoint).status())
        } catch {
            connectionState = .failed((error as? LocalizedError)?.errorDescription ?? "接続できませんでした。")
        }
    }

    /// 接続先を消して端末内の簡易モードに戻す
    public func disconnect() {
        try? connectionStore.clear()
        baseURLText = ""
        tokenText = ""
        hasSavedToken = false
        isConfigured = false
        connectionState = .idle
        onEndpointChange(nil)
    }

    // MARK: - 通知

    public func setNotificationsEnabled(_ enabled: Bool) async {
        notificationMessage = nil
        var prefs = notificationPreferences
        if enabled {
            notificationAuthorization = await scheduler.authorization()
            if notificationAuthorization == .notDetermined {
                notificationAuthorization = await scheduler.requestAuthorization() ? .authorized : .denied
            }
            guard notificationAuthorization == .authorized else {
                notificationMessage = "通知が許可されていません。iOSの設定アプリから許可できます。"
                return
            }
        }
        prefs.enabled = enabled
        updateNotificationPreferences(prefs)
    }

    public func updateNotificationPreferences(_ value: NotificationPreferences) {
        notificationPreferences = value.normalized
        defaults.saveNotificationPreferences(notificationPreferences)
        onNotificationPreferencesChange(notificationPreferences)
    }
}
