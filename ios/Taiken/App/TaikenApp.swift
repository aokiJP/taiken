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
                    appDelegate.onNotificationTap = { Task { await deps.handleNotificationTap() } }
                }
        }
        .modelContainer(dependencies.container)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // 戻ってきたとき、古い提案だけ作り直す (毎回AIを呼ばない)
                Task { await dependencies.home.refresh() }
            case .background:
                dependencies.scheduleBackgroundRefresh()
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
    var onNotificationTap: (@MainActor () -> Void)?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// アプリを開いているときは、通知を画面に出さず通知センターにだけ残す
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await MainActor.run { self.onNotificationTap?() }
    }
}
