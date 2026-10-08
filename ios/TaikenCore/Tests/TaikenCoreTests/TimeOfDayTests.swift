import Foundation
import XCTest
@testable import TaikenCore

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
