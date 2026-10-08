import SwiftUI
import TaikenCore

/// はじめての人には案内を、それ以外はホームを出す。
/// 体験帳は押し出し (ホーム → 体験帳 → 記録)、話す・設定はシートで開く。
struct RootView: View {
    let dependencies: AppDependencies
    @Bindable private var router: AppRouter
    private let pendingRoute = PendingRoute.shared
    @AppStorage(OnboardingKey.completed) private var onboardingCompleted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        router = dependencies.router
    }

    var body: some View {
        ZStack {
            if onboardingCompleted {
                home
                    .transition(.opacity)
            } else {
                OnboardingView(dependencies: dependencies) {
                    withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .easeInOut(duration: 0.7)) {
                        onboardingCompleted = true
                    }
                    Task { await dependencies.finishOnboarding() }
                }
                .transition(.opacity)
            }
        }
        .tint(Palette.ink)
        // ショートカット (App Intents) から開かれたとき
        .onAppear { consumePendingRoute() }
        .onChange(of: pendingRoute.url) { consumePendingRoute() }
    }

    private var home: some View {
        NavigationStack(path: $router.path) {
            HomeView(
                model: dependencies.home,
                engine: dependencies.engineState.engine,
                openChat: { router.sheet = .chat },
                openJournal: { router.openJournal() },
                openSettings: { router.sheet = .settings },
                previewRequest: { await dependencies.previewRequest() },
                livedSeasons: {
                    dependencies.history.reload()
                    return dependencies.history.stats.microSeasons
                }
            )
            .navigationDestination(for: AppRouter.Destination.self) { destination in
                switch destination {
                case .journal:
                    JournalView(model: dependencies.history) { router.returnHome() }
                }
            }
        }
        .sheet(item: $router.sheet) { sheet in
            switch sheet {
            case .chat:
                ChatView(model: dependencies.chat, engine: dependencies.engineState.engine)
            case .settings:
                SettingsView(dependencies: dependencies)
            }
        }
    }

    private func consumePendingRoute() {
        guard let url = pendingRoute.url else { return }
        pendingRoute.url = nil
        dependencies.open(url)
    }
}

#Preview {
    RootView(dependencies: .preview())
}
