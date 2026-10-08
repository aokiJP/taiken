import SwiftUI
import WidgetKit

/// ホーム画面・ロック画面のウィジェットと、体験中の Live Activity
@main
struct TaikenWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        #if canImport(ActivityKit)
        ExperienceLiveActivity()
        #endif
    }
}
