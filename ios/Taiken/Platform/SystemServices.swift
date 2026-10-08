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
        // 通知から「やってみる」「あとで」を選べる
        body.categoryIdentifier = NotificationAction.experienceCategory
        // 負担をかけない: 音は鳴らさない
        body.sound = nil
        body.interruptionLevel = .active
        body.userInfo = ["route": "home"]
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: identifier, content: body, trigger: nil))
    }
}

/// 朝の便り: 決まった時刻の通知を、これから数日分まとめて予約し直す
struct UserNotificationLetterScheduler: LetterScheduling {
    func replaceLetters(with letters: [PlannedLetter]) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let old = pending.map(\.identifier).filter { $0.hasPrefix(DailyLetter.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: old)
        for letter in letters {
            let content = UNMutableNotificationContent()
            content.title = letter.title
            content.body = letter.body
            content.threadIdentifier = DailyLetter.categoryIdentifier
            content.categoryIdentifier = DailyLetter.categoryIdentifier
            content.sound = nil
            content.interruptionLevel = .active
            content.userInfo = ["route": "home"]
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: letter.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            do {
                try await center.add(UNNotificationRequest(identifier: letter.identifier, content: content, trigger: trigger))
            } catch {
                Logger.app.notice("letter.schedule_failed")
            }
        }
    }
}

enum NotificationCategories {
    /// 通知のボタン。「やってみる」はアプリを開いてそのまま体験を始める
    static func register() {
        let accept = UNNotificationAction(identifier: NotificationAction.accept, title: "やってみる", options: [.foreground])
        let later = UNNotificationAction(identifier: NotificationAction.later, title: "あとで", options: [])
        let experience = UNNotificationCategory(identifier: NotificationAction.experienceCategory, actions: [accept, later], intentIdentifiers: [], options: [])
        let letter = UNNotificationCategory(identifier: DailyLetter.categoryIdentifier, actions: [], intentIdentifiers: [], options: [])
        UNUserNotificationCenter.current().setNotificationCategories([experience, letter])
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
