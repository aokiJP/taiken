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
    static let title: LocalizedStringResource = "ホームをひらく"
    static let description = IntentDescription("自分の樹と、体験を記す入口をひらきます。きっかけは、ひらいてから求めたときだけ出ます。")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingRoute.shared.url = DeepLink.today.url
        return .result()
    }
}

struct OpenJournalIntent: AppIntent {
    static let title: LocalizedStringResource = "体験帳をひらく"
    static let description = IntentDescription("これまでに記した体験と、月の暦をひらきます。")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingRoute.shared.url = DeepLink.journal.url
        return .result()
    }
}

struct RecordIntent: AppIntent {
    static let title: LocalizedStringResource = "体験を記す"
    static let description = IntentDescription("いつもの一日で体験したことを、ひとこと記す画面をひらきます。記したことは、この端末の中にだけ残ります。")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingRoute.shared.url = DeepLink.record.url
        return .result()
    }
}

struct OpenTreeIntent: AppIntent {
    static let title: LocalizedStringResource = "技の樹をひらく"
    static let description = IntentDescription("要素ごとの段と、身についた技と、伸ばせる芽が見える技の樹をひらきます。")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        PendingRoute.shared.url = DeepLink.tree.url
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
            intent: RecordIntent(),
            phrases: ["\(.applicationName)で体験を記す", "\(.applicationName)に体験を記す"],
            shortTitle: "体験を記す",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: OpenTodayIntent(),
            phrases: ["\(.applicationName)のホームをひらく", "\(.applicationName)の今日の体験"],
            shortTitle: "ホーム",
            systemImageName: "sun.horizon"
        )
        AppShortcut(
            intent: OpenJournalIntent(),
            phrases: ["\(.applicationName)の体験帳をひらく"],
            shortTitle: "体験帳",
            systemImageName: "book.closed"
        )
        AppShortcut(
            intent: OpenTreeIntent(),
            phrases: ["\(.applicationName)の技の樹をひらく"],
            shortTitle: "技の樹",
            systemImageName: "circle.hexagongrid"
        )
        AppShortcut(
            intent: TalkIntent(),
            phrases: ["\(.applicationName)に話しかける"],
            shortTitle: "話しかける",
            systemImageName: "bubble.left"
        )
    }
}
