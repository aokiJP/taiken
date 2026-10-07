import EventKit
import Foundation
import TaikenCore

/// EventKit から今日・明日の予定を読む。読むのは時間とタイトルだけ (メモ・場所・参加者は読まない)。
final class EventKitCalendarProvider: CalendarProviding, @unchecked Sendable {
    // EKEventStore は1つを使い回すのが推奨。スレッドセーフに使える
    private let store = EKEventStore()

    func access() -> PermissionState {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied // writeOnly / denied / restricted
        }
    }

    func requestAccess() async -> PermissionState {
        do {
            return try await store.requestFullAccessToEvents() ? .granted : .denied
        } catch {
            return .denied
        }
    }

    func events(from start: Date, to end: Date) -> [CalendarEventSnapshot] {
        guard access() == .granted else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map {
            CalendarEventSnapshot(title: $0.title, start: $0.startDate, end: $0.endDate, isAllDay: $0.isAllDay)
        }
    }
}
