import Foundation

/// 太陽の視黄経 (度)。二十四節気・七十二候を日付から求めるために使う。
/// 精度は約0.01度 (時刻にして十数分) で、日単位の判定には十分 (国立天文台の暦要項と日付が一致することをテストで確認)。
public enum SolarLongitude {
    public static func degrees(at date: Date) -> Double {
        let julianDay = date.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let t = (julianDay - 2_451_545.0) / 36_525
        let meanLongitude = 280.46646 + 36_000.76983 * t + 0.0003032 * t * t
        let meanAnomaly = (357.52911 + 35_999.05029 * t - 0.0001537 * t * t) * .pi / 180
        let center = (1.914602 - 0.004817 * t - 0.000014 * t * t) * sin(meanAnomaly)
            + (0.019993 - 0.000101 * t) * sin(2 * meanAnomaly)
            + 0.000289 * sin(3 * meanAnomaly)
        let omega = (125.04 - 1_934.136 * t) * .pi / 180
        let apparent = meanLongitude + center - 0.00569 - 0.00478 * sin(omega)
        let normalized = apparent.truncatingRemainder(dividingBy: 360)
        return normalized < 0 ? normalized + 360 : normalized
    }
}

/// 七十二候。立春から5日ほどずつ、一年を72に分けた季節の名前。
/// 「いつもの一日」の中の小さな変化に目を向けるきっかけとして、Home の見出しや体験づくりに使う。
public struct MicroSeason: Sendable, Hashable, Identifiable {
    /// 0〜71 (0 = 立春 初候「東風解凍」)
    public let index: Int
    public let name: String
    public let reading: String
    public let meaning: String
    /// 0〜23 (0 = 立春)
    public let solarTermIndex: Int
    public let solarTerm: String
    public let solarTermReading: String

    public var id: Int { index }

    /// 節気の中で何番目か (0 = 初候, 1 = 次候, 2 = 末候)
    public var positionInTerm: Int { index % 3 }

    public var positionLabel: String { ["初候", "次候", "末候"][positionInTerm] }

    /// 春・夏・秋・冬 (立春・立夏・立秋・立冬で切り替わる)
    public var seasonName: String { ["春", "夏", "秋", "冬"][solarTermIndex / 6] }

    public var context: SeasonContext {
        SeasonContext(solarTerm: solarTerm, microSeason: name, meaning: meaning)
    }

    public var next: MicroSeason { Self.entry((index + 1) % 72) }
    public var previous: MicroSeason { Self.entry((index + 71) % 72) }

    // MARK: - 日付から求める

    /// その瞬間の候 (黄経を5度ごとに区切る)
    public static func index(atInstant date: Date) -> Int {
        let fromSpring = (SolarLongitude.degrees(at: date) - 315 + 360).truncatingRemainder(dividingBy: 360)
        return min(71, max(0, Int(fromSpring / 5)))
    }

    /// その日の候。暦の慣習どおり、切り替わる瞬間を含む日は新しい候の日として扱う (その日の終わりで判定)
    public static func index(on date: Date, calendar: Calendar) -> Int {
        index(atInstant: endOfDay(date, calendar: calendar))
    }

    public static func at(_ date: Date, calendar: Calendar, content: TaikenContent = .shared) -> MicroSeason {
        entry(index(on: date, calendar: calendar), content: content)
    }

    public static func entry(_ index: Int, content: TaikenContent = .shared) -> MicroSeason {
        let i = ((index % 72) + 72) % 72
        let termIndex = i / 3
        let season = content.microSeasons.indices.contains(i) ? content.microSeasons[i] : TaikenContent.minimal.microSeasons[0]
        let term = content.solarTerms.indices.contains(termIndex) ? content.solarTerms[termIndex] : TaikenContent.minimal.solarTerms[0]
        return MicroSeason(
            index: i, name: season.name, reading: season.reading, meaning: season.meaning,
            solarTermIndex: termIndex, solarTerm: term.name, solarTermReading: term.reading
        )
    }

    /// この候が続く日付の範囲 (最初の日の0時〜最後の日の翌日0時)。
    /// date がこの候の日でなければ、その日だけの範囲を返す
    public func period(around date: Date, calendar: Calendar) -> DateInterval {
        let day = calendar.startOfDay(for: date)
        guard Self.index(on: day, calendar: calendar) == index else {
            return DateInterval(start: day, end: calendar.date(byAdding: .day, value: 1, to: day) ?? day)
        }
        var first = day
        for _ in 0..<8 {
            guard let previous = calendar.date(byAdding: .day, value: -1, to: first),
                  Self.index(on: previous, calendar: calendar) == index else { break }
            first = previous
        }
        var last = day
        for _ in 0..<8 {
            guard let following = calendar.date(byAdding: .day, value: 1, to: last),
                  Self.index(on: following, calendar: calendar) == index else { break }
            last = following
        }
        let end = calendar.date(byAdding: .day, value: 1, to: last) ?? last
        return DateInterval(start: first, end: end)
    }

    static func endOfDay(_ date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        let next = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return next.addingTimeInterval(-1)
    }
}
