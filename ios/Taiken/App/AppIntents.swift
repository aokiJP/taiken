import AppIntents
import Foundation
import Observation

// ショートカット・Siri・Spotlight・アクションボタンから開く入口。
// どれもアプリを開くだけで、何かを勝手に始めたり記録したりはしない。

/// ショートカットから届いた行き先。画面の準備ができたら RootView が受け取る
@MainActor
@Observable
final class PendingRoute {
    static let shared = PendingRoute()
    var url: URL?
}

struct OpenTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "今日の体験をひらく"
    static let description = IntentDescription("今日の体験の提案をひらきます。")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingRoute.shared.url = DeepLink.today.url
        return .result()
    }
}

struct OpenJournalIntent: AppIntent {
    static let title: LocalizedStringResource = "体験帳をひらく"
    static let description = IntentDescription("これまでに記した体験と、七十二候の輪をひらきます。")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingRoute.shared.url = DeepLink.journal.url
        return .result()
    }
}

struct TalkIntent: AppIntent {
    static let title: LocalizedStringResource = "話しかける"
    static let description = IntentDescription("いまの気分を話せる画面をひらきます。会話は保存されません。")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingRoute.shared.url = DeepLink.talk.url
        return .result()
    }
}

struct TaikenShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenTodayIntent(),
            phrases: ["\(.applicationName)で今日の体験をひらく", "\(.applicationName)の今日の体験"],
            shortTitle: "今日の体験",
            systemImageName: "sun.horizon"
        )
        AppShortcut(
            intent: OpenJournalIntent(),
            phrases: ["\(.applicationName)の体験帳をひらく"],
            shortTitle: "体験帳",
            systemImageName: "book.closed"
        )
        AppShortcut(
            intent: TalkIntent(),
            phrases: ["\(.applicationName)に話しかける"],
            shortTitle: "話しかける",
            systemImageName: "bubble.left"
        )
    }
}
