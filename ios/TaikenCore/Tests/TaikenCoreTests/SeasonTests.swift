import Foundation
import XCTest
@testable import TaikenCore

final class MicroSeasonTests: XCTestCase {
    func testReferenceDateIsKouganKitaru() {
        let season = MicroSeason.at(referenceDate, calendar: tokyoCalendar)
        XCTAssertEqual(season.index, 48)
        XCTAssertEqual(season.name, "鴻雁来")
        XCTAssertEqual(season.reading, "こうがんきたる")
        XCTAssertEqual(season.meaning, "雁が北から渡ってくる頃")
        XCTAssertEqual(season.solarTerm, "寒露")
        XCTAssertEqual(season.positionLabel, "初候")
        XCTAssertEqual(season.seasonName, "秋")
        XCTAssertEqual(season.context, SeasonContext(solarTerm: "寒露", microSeason: "鴻雁来", meaning: "雁が北から渡ってくる頃"))
    }

    /// 国立天文台「暦要項」(2026年) の二十四節気の日付と一致する
    func testSolarTermDatesMatchAlmanac2026() {
        let expected: [(String, String)] = [
            ("小寒", "2026-01-05"), ("大寒", "2026-01-20"), ("立春", "2026-02-04"), ("雨水", "2026-02-19"),
            ("啓蟄", "2026-03-05"), ("春分", "2026-03-20"), ("清明", "2026-04-05"), ("穀雨", "2026-04-20"),
            ("立夏", "2026-05-05"), ("小満", "2026-05-21"), ("芒種", "2026-06-06"), ("夏至", "2026-06-21"),
            ("小暑", "2026-07-07"), ("大暑", "2026-07-23"), ("立秋", "2026-08-07"), ("処暑", "2026-08-23"),
            ("白露", "2026-09-07"), ("秋分", "2026-09-23"), ("寒露", "2026-10-08"), ("霜降", "2026-10-23"),
            ("立冬", "2026-11-07"), ("小雪", "2026-11-22"), ("大雪", "2026-12-07"), ("冬至", "2026-12-22"),
        ]
        for (name, day) in expected {
            let first = MicroSeason.at(tokyoDate(day, hour: 12), calendar: tokyoCalendar)
            XCTAssertEqual(first.solarTerm, name, day)
            XCTAssertEqual(first.positionInTerm, 0, day)
            let previous = tokyoCalendar.date(byAdding: .day, value: -1, to: tokyoDate(day, hour: 12))!
            XCTAssertNotEqual(MicroSeason.at(previous, calendar: tokyoCalendar).solarTerm, name, "\(day) の前日はまだ\(name)ではない")
        }
    }

    /// 切り替わる瞬間 (寒露は 10/8 15時半ごろ) を含む日は、朝から新しい候として扱う
    func testDayContainingTheBoundaryBelongsToTheNewSeason() {
        let earlyMorning = tokyoDate("2026-10-08", hour: 0, minute: 30)
        XCTAssertEqual(MicroSeason.index(atInstant: earlyMorning), 47)
        XCTAssertEqual(MicroSeason.at(earlyMorning, calendar: tokyoCalendar).name, "鴻雁来")
    }

    func testPeriodAndNeighbors() {
        let season = MicroSeason.at(referenceDate, calendar: tokyoCalendar)
        let period = season.period(around: referenceDate, calendar: tokyoCalendar)
        XCTAssertEqual(period.start, tokyoDate("2026-10-08"))
        XCTAssertEqual(period.end, tokyoDate("2026-10-13"))
        XCTAssertEqual(season.next.name, "菊花開")
        XCTAssertEqual(season.previous.name, "水始涸")
        XCTAssertEqual(MicroSeason.entry(71).next.name, "東風解凍")
        XCTAssertEqual(MicroSeason.entry(0).previous.name, "鶏始乳")
    }

    func testAllSeventyTwoAreDistinctAndGroupedByThree() {
        let all = (0..<72).map { MicroSeason.entry($0) }
        XCTAssertEqual(Set(all.map(\.name)).count, 72)
        XCTAssertEqual(Set(all.map(\.solarTerm)).count, 24)
        for season in all {
            XCTAssertEqual(season.solarTermIndex, season.index / 3)
            XCTAssertFalse(season.meaning.isEmpty)
        }
        XCTAssertEqual(MicroSeason.entry(-1).index, 71)
        XCTAssertEqual(MicroSeason.entry(72).index, 0)
    }

    func testSolarLongitudeStaysInRange() {
        for day in stride(from: 0.0, through: 400.0, by: 7.5) {
            let degrees = SolarLongitude.degrees(at: referenceDate.addingTimeInterval(day * 86_400))
            XCTAssertTrue((0..<360).contains(degrees))
        }
    }
}

final class TimeOfDayTests: XCTestCase {
    func testBoundariesMatchBackend() {
        let expected: [(Int, TimeOfDay)] = [
            (0, .lateNight), (3, .lateNight), (4, .dawn), (5, .dawn), (6, .morning), (9, .morning),
            (10, .daytime), (15, .daytime), (16, .evening), (18, .evening), (19, .night), (23, .night),
        ]
        for (hour, time) in expected {
            XCTAssertEqual(TimeOfDay.of(hour: hour), time, "\(hour)時")
        }
        XCTAssertEqual(TimeOfDay.at(referenceDate, calendar: tokyoCalendar), .evening)
    }

    func testNextBoundary() {
        XCTAssertEqual(TimeOfDay.nextBoundary(after: referenceDate, calendar: tokyoCalendar), tokyoDate("2026-10-08", hour: 19))
        XCTAssertEqual(TimeOfDay.nextBoundary(after: tokyoDate("2026-10-08", hour: 23, minute: 30), calendar: tokyoCalendar), tokyoDate("2026-10-09"))
        XCTAssertEqual(TimeOfDay.nextBoundary(after: tokyoDate("2026-10-09", hour: 2), calendar: tokyoCalendar), tokyoDate("2026-10-09", hour: 4))
    }

    func testLabelsAndSky() {
        XCTAssertEqual(TimeOfDay.evening.label, "夕方")
        XCTAssertEqual(TimeOfDay.morning.greeting, "おはようございます")
        XCTAssertTrue(TimeOfDay.night.isDark)
        XCTAssertTrue(TimeOfDay.lateNight.isDark)
        XCTAssertFalse(TimeOfDay.evening.isDark)
        for time in TimeOfDay.allCases {
            XCTAssertEqual(TimeOfDay.of(hour: time.startHour), time)
        }
    }
}
