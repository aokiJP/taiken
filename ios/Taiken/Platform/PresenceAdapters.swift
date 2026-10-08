import Foundation
import os
import TaikenCore
import WidgetKit
#if canImport(ActivityKit)
import ActivityKit
#endif

/// ウィジェットへ今日の状態を渡す。内容が変わったときだけ描き直してもらう
struct AppGroupWidgetPublisher: WidgetPublishing {
    let store: WidgetSnapshotStore?

    func publish(_ snapshot: WidgetSnapshot) {
        guard let store, store.save(snapshot) else { return }
        WidgetCenter.shared.reloadAllTimelines()
    }
}

#if canImport(ActivityKit)
/// 体験中の内容をロック画面と Dynamic Island に置く (Live Activity)。
/// 音も通知も出さない、静かな「持ち歩くメモ」として使う。終えたら・やめたらすぐ消す。
@MainActor
final class LiveActivityPresence: ExperiencePresence {
    /// Live Activity は最長8時間まで更新できる。それを過ぎたら古い表示として扱われる
    private let staleAfter: TimeInterval = 8 * 3600

    func begin(_ entry: HistoryEntry) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        endAll()
        let attributes = ExperienceActivityAttributes(
            title: entry.title,
            invitation: entry.invitation,
            sealCharacter: entry.sealCharacter,
            startedAt: entry.createdAt,
            microSeason: MicroSeason.at(entry.createdAt, calendar: .current).name
        )
        let state = ExperienceActivityAttributes.ContentState(reflectionQuestion: entry.reflectionQuestion)
        do {
            _ = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(staleAfter)),
                pushType: nil
            )
        } catch {
            Logger.app.notice("presence.request_failed \(String(describing: type(of: error)), privacy: .public)")
        }
    }

    func end() {
        endAll()
    }

    func sync(active: HistoryEntry?) {
        // 体験中でなければ、残っている表示を片づける。体験中の表示をユーザーが消していても、勝手には戻さない
        if active == nil { endAll() }
    }

    private func endAll() {
        for activity in Activity<ExperienceActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
#endif
