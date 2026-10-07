import SwiftUI
import TaikenCore

struct RootView: View {
    let dependencies: AppDependencies
    @Bindable private var router: AppRouter

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        router = dependencies.router
    }

    var body: some View {
        NavigationStack {
            HomeView(model: dependencies.home, openChat: { router.sheet = .chat })
                .toolbar {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button {
                            router.sheet = .history
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                        }
                        .accessibilityLabel("体験の履歴")

                        Button {
                            router.sheet = .settings
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                        .accessibilityLabel("設定")
                    }
                }
        }
        .sheet(item: $router.sheet) { sheet in
            switch sheet {
            case .chat:
                ChatView(model: dependencies.chat)
                    .presentationDragIndicator(.visible)
            case .history:
                HistoryView(model: dependencies.history)
            case .settings:
                SettingsView(dependencies: dependencies)
            }
        }
    }
}

#Preview {
    RootView(dependencies: .preview())
}
