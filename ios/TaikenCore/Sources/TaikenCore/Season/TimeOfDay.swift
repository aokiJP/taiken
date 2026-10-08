import Foundation

/// 一日の時間帯。空の色・あいさつ・体験の選び方に使う。
/// 境界は Backend と同じ (夜明け 4時 / 朝 6時 / 昼 10時 / 夕方 16時 / 夜 19時 / 深夜 0時)
public enum TimeOfDay: String, Codable, Sendable, CaseIterable {
    case dawn, morning, daytime, evening, night, lateNight

    public static func of(hour: Int) -> TimeOfDay {
        switch hour {
        case 4..<6: .dawn
        case 6..<10: .morning
        case 10..<16: .daytime
        case 16..<19: .evening
        case 19..<24: .night
        default: .lateNight
        }
    }

    public static func at(_ date: Date, calendar: Calendar) -> TimeOfDay {
        of(hour: calendar.component(.hour, from: date))
    }

    public var label: String {
        switch self {
        case .dawn: "夜明け"
        case .morning: "朝"
        case .daytime: "昼"
        case .evening: "夕方"
        case .night: "夜"
        case .lateNight: "深夜"
        }
    }

    public var greeting: String {
        switch self {
        case .dawn, .morning: "おはようございます"
        case .daytime: "こんにちは"
        case .evening, .night: "こんばんは"
        case .lateNight: "静かな夜ですね"
        }
    }

    /// 空が暗い時間帯か (空の上の文字を明るくする)
    public var isDark: Bool { self == .night || self == .lateNight }

    /// この時間帯が始まる時刻 (時)
    public var startHour: Int {
        switch self {
        case .dawn: 4
        case .morning: 6
        case .daytime: 10
        case .evening: 16
        case .night: 19
        case .lateNight: 0
        }
    }

    /// date より後で、次に時間帯が切り替わる時刻
    public static func nextBoundary(after date: Date, calendar: Calendar) -> Date {
        let hours = [0, 4, 6, 10, 16, 19]
        let start = calendar.startOfDay(for: date)
        for day in 0...1 {
            guard let base = calendar.date(byAdding: .day, value: day, to: start) else { continue }
            for hour in hours {
                if let candidate = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: base), candidate > date {
                    return candidate
                }
            }
        }
        return date.addingTimeInterval(3600)
    }
}
