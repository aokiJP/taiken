import Foundation

/// 朝の便り: 決まった時刻に一度だけ届く、短いひとこと (きっかけそのものは入れない。押すとホームがひらき、
/// きっかけがほしければ、そこで「きっかけをもらう」を押す)。
/// サーバーもバックグラウンド実行も要らないので、誰でも使える (既定はオフ)。
/// その日すでにアプリを開いて体験に触れていれば、その日の便りは送らない。
public struct DailyLetterPreferences: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var hour: Int
    public var minute: Int

    public init(enabled: Bool = false, hour: Int = 8, minute: Int = 0) {
        self.enabled = enabled
        self.hour = hour
        self.minute = minute
    }

    public var normalized: DailyLetterPreferences {
        DailyLetterPreferences(enabled: enabled, hour: min(23, max(0, hour)), minute: min(59, max(0, minute)))
    }
}

public struct PlannedLetter: Sendable, Equatable {
    public let identifier: String
    public let fireDate: Date
    public let title: String
    public let body: String
}

/// 予約した便りを、まとめて入れ替える (アプリ側で UNUserNotificationCenter を使う)
public protocol LetterScheduling: Sendable {
    func replaceLetters(with letters: [PlannedLetter]) async
}

/// テスト用
public final class RecordingLetterScheduler: LetterScheduling, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [[PlannedLetter]] = []
    public init() {}
    public var history: [[PlannedLetter]] { lock.withLock { stored } }
    public func replaceLetters(with letters: [PlannedLetter]) async { lock.withLock { stored.append(letters) } }
}

public enum DailyLetter {
    public static let identifierPrefix = "letter-"
    public static let categoryIdentifier = "letter"

    static let title = "今日の体験"
    static let bodies = [
        "いつもの一日に、まだ見ていない体験がある。",
        "ふと足が止まったら、ひとことだけ記せます。",
        "きっかけがほしいときは、ひらいてみてください。",
    ]

    /// これから days 日ぶんの便りを計画する (iOS の予約上限に収まる数だけ)
    public static func plan(
        now: Date, preferences: DailyLetterPreferences, engagedToday: Bool, calendar: Calendar, days: Int = 7
    ) -> [PlannedLetter] {
        let p = preferences.normalized
        guard p.enabled else { return [] }
        let today = calendar.startOfDay(for: now)
        var letters: [PlannedLetter] = []
        for offset in 0..<days {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  let fire = calendar.date(bySettingHour: p.hour, minute: p.minute, second: 0, of: day),
                  fire > now else { continue }
            if offset == 0 && engagedToday { continue }
            let dayNumber = LibrarySelector.dayNumber(of: fire, calendar: calendar)
            let parts = calendar.dateComponents([.year, .month, .day], from: fire)
            let stamp = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
            letters.append(PlannedLetter(
                identifier: identifierPrefix + stamp,
                fireDate: fire,
                title: title,
                body: bodies[((dayNumber % bodies.count) + bodies.count) % bodies.count]
            ))
        }
        return letters
    }
}
