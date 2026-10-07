import BackgroundTasks
import Foundation
import os
import TaikenCore
import UserNotifications

/// ローカル通知 (サーバーからのプッシュは使わない: 端末が必要なときだけ確認する「必要時接続」)
struct UserNotificationScheduler: NotificationScheduling {
    func authorization() async -> NotificationAuthorization {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .authorized
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])) ?? false
    }

    func deliver(_ content: NotificationContent, identifier: String) async throws {
        let body = UNMutableNotificationContent()
        body.title = content.title
        body.body = content.body
        body.threadIdentifier = "experience"
        // 負担をかけない: 音は鳴らさない
        body.sound = nil
        body.interruptionLevel = .active
        body.userInfo = ["route": "home"]
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: body, trigger: nil))
    }
}

/// バックグラウンド更新の予約。実行は TaikenApp の .backgroundTask で受ける
enum BackgroundRefresh {
    static let identifier = "com.example.taiken.refresh"

    static func schedule(at date: Date?) {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        guard let date else { return }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = date
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // シミュレータでは失敗する (実機のみ対応)
            Logger.app.notice("background.schedule_failed \(String(describing: error), privacy: .public)")
        }
    }
}

extension Logger {
    static let app = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Taiken", category: "app")
}

/// 診断ログ (Console.app / sysdiagnose)。イベント名だけ公開し、詳細は private で記録する
struct OSLogDiagnostics: Diagnostics {
    func record(_ event: String, _ fields: [String: String]) {
        let detail = fields.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        Logger.app.notice("\(event, privacy: .public) \(detail, privacy: .private)")
    }
}

/// 強いつらさのサインがあったときに案内する相談先 (厚生労働省「まもろうよ こころ」)
enum SupportResources {
    static let url = URL(string: "https://www.mhlw.go.jp/mamorouyokokoro/")!
    static let title = "まもろうよ こころ (厚生労働省)"
    static let description = "電話・SNSで相談できる窓口がまとまっています。今すぐ危険がある場合は 119 / 110 へ。"
}
