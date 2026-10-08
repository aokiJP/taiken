import Foundation
import TaikenCore
#if canImport(ActivityKit)
import ActivityKit
#endif

/// アプリとウィジェットが共有する置き場所 (App Group)。
/// ID は xcconfig の TAIKEN_APP_GROUP → Info.plist の TaikenAppGroup から読む。
/// 署名で App Group を有効にしていない場合も落ちず、ウィジェットに内容が届かないだけになる。
enum AppGroup {
    static var identifier: String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "TaikenAppGroup") as? String else { return nil }
        let value = raw.trimmingCharacters(in: .whitespaces)
        return value.isEmpty || value.hasPrefix("$(") ? nil : value
    }

    static var defaults: UserDefaults? {
        identifier.flatMap { UserDefaults(suiteName: $0) }
    }

    static var widgetStore: WidgetSnapshotStore? {
        defaults.map { WidgetSnapshotStore(defaults: $0) }
    }
}

/// アプリを開く URL。ウィジェット・Live Activity・ショートカットから使う
enum DeepLink: Equatable {
    case today
    case journal
    case talk

    static let scheme = "taiken"

    init?(url: URL) {
        guard url.scheme == Self.scheme else { return nil }
        switch url.host {
        case "today": self = .today
        case "journal": self = .journal
        case "talk": self = .talk
        default: return nil
        }
    }

    var url: URL {
        // 定数だけで組み立てるので失敗しない
        URL(string: "\(Self.scheme)://\(host)")!
    }

    private var host: String {
        switch self {
        case .today: "today"
        case .journal: "journal"
        case .talk: "talk"
        }
    }
}

#if canImport(ActivityKit)
/// 体験中の内容をロック画面と Dynamic Island に置く (Live Activity)
struct ExperienceActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// 体験のあとに思い返すための問い
        var reflectionQuestion: String?
    }

    var title: String
    var invitation: String
    var sealCharacter: String
    var startedAt: Date
    var microSeason: String
}
#endif
