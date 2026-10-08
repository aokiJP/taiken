import SwiftData
import SwiftUI
import TaikenCore
import UserNotifications

@main
struct TaikenApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var dependencies = AppDependencies(configuration: .fromBundle())

    var body: some Scene {
        WindowGroup {
            RootView(dependencies: dependencies)
                .onAppear {
                    let deps = dependencies
                    appDelegate.onNotificationResponse = { action in
                        Task { await deps.handleNotification(action: action) }
                    }
                }
                .onOpenURL { url in dependencies.open(url) }
        }
        .modelContainer(dependencies.container)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // はじめの案内の途中では、まだ提案を作らない
                guard dependencies.defaults.hasCompletedOnboarding else { return }
                // 戻ってきたとき、古い提案だけ作り直す (毎回AIを呼ばない)
                Task {
                    await dependencies.home.refresh()
                    dependencies.rescheduleLetters()
                }
            case .background:
                dependencies.scheduleBackgroundRefresh()
                dependencies.rescheduleLetters()
            default:
                break
            }
        }
        .backgroundTask(.appRefresh(BackgroundRefresh.identifier)) {
            await dependencies.performBackgroundRefresh()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// 通知のボタンが押された (画面の準備ができる前に届いたものは、準備ができてから渡す)
    var onNotificationResponse: (@MainActor (String) -> Void)? {
        didSet { flushPendingAction() }
    }

    private var pendingAction: String?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        NotificationCategories.register()
        return true
    }

    /// アプリを開いているときは、通知を画面に出さず通知センターにだけ残す
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action: String = switch response.actionIdentifier {
        case NotificationAction.accept: NotificationAction.accept
        case NotificationAction.later: NotificationAction.later
        default: NotificationAction.open
        }
        await MainActor.run { self.deliver(action) }
    }

    @MainActor
    private func deliver(_ action: String) {
        pendingAction = action
        flushPendingAction()
    }

    @MainActor
    private func flushPendingAction() {
        guard let action = pendingAction, let handler = onNotificationResponse else { return }
        pendingAction = nil
        handler(action)
    }
}
