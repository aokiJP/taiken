import SwiftUI
import TaikenCore

/// ホーム (4.0): 真ん中は、自分の樹と「体験を記す」。
/// 体験は、自分で生きて、自分で記すもの。記すと触れた要素に経験が積もり、段が上がると芽が出る。
/// AIや体験ライブラリの提案は「きっかけ」として、求められたときだけ出す (勝手には出さない)。
/// 地はいまの空。真ん中に、その時いちばん大事なカードがひとつだけある。
struct HomeView: View {
    let model: HomeViewModel
    let tree: TreeViewModel
    let engine: ProposalEngine
    let openChat: @MainActor () -> Void
    let openJournal: @MainActor () -> Void
    /// 技の樹をひらく (技の id があれば、そこを中心に)
    let openTree: @MainActor (String?) -> Void
    let openSettings: @MainActor () -> Void
    let previewRequest: @MainActor () async -> ExperienceRequest
    /// ショートカットやウィジェットから「体験を記す」を求められた
    var recordRequested = false
    var consumeRecordRequest: @MainActor () -> Void = {}

    @State private var sheet: HomeSheet?
    /// シートが閉じきってから印を押す (押す瞬間を見てもらうため)
    @State private var pending: Pending?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum HomeSheet: String, Identifiable {
        case insight, reflection, record
        var id: String { rawValue }
    }

    /// シートを閉じたあとに記すもの
    enum Pending {
        case finish(rating: Rating, note: String?, skills: [String])
        case record(LivedDraft)
    }

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            let time = TimeOfDay.at(timeline.date, calendar: .current)
            let palette = time.sky(dark: colorScheme == .dark)
            ZStack {
                SkyBackground(time: time)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HomeHeader(
                            date: timeline.date,
                            time: time,
                            palette: palette,
                            scene: TreeScene.make(tree: tree.tree, layout: tree.layout),
                            sprouting: !tree.tree.sproutingElements.isEmpty
                        ) {
                            openTree(nil)
                        }
                        if let notice = model.notice {
                            NoticeLine(notice: notice, palette: palette)
                        }
                        if let welcome = model.welcome, model.stage == .idle {
                            WelcomeCard(report: welcome) {
                                model.dismissWelcome()
                                openTree(welcome.sproutElements.first.map { ExperienceTree.rootID($0.id) })
                            } dismiss: {
                                model.dismissWelcome()
                            }
                            .transition(.opacity)
                        }
                        if model.calendarAccess == .notDetermined, model.stage == .proposal || model.stage == .loading {
                            CalendarInvite(palette: palette) { Task { await model.requestCalendarAccess() } }
                        }
                        stageCard
                        if model.stage == .proposal {
                            MoodChips(selected: model.mood, palette: palette) { mood in
                                Task { await model.choose(mood: mood) }
                            }
                            // きっかけを見ているあいだも、自分で見つけた体験はいつでも記せる (断らなくてよい)
                            Button {
                                sheet = .record
                            } label: {
                                Label("自分で見つけた体験を記す", systemImage: "square.and.pencil")
                                    .font(.footnote)
                                    .foregroundStyle(palette.onSky)
                            }
                            .buttonStyle(.plain)
                            .padding(.leading, 4)
                            .accessibilityHint("きっかけはそのままに、いつもの一日で体験したことを記します")
                            .accessibilityIdentifier("home.record.aside")
                        }
                        if !model.todayEntries.isEmpty {
                            TodayStamps(entries: model.todayEntries, palette: palette, open: openJournal)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .environment(\.skyPalette, palette)
            }
            .onChange(of: time) { model.updateClock() }
        }
        .safeAreaInset(edge: .bottom) {
            TalkButton(action: openChat)
                .padding(.bottom, 6)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                FloatingIconButton(systemImage: "book.closed", label: "体験帳", action: openJournal)
            }
            ToolbarItem(placement: .topBarTrailing) {
                FloatingIconButton(systemImage: "slider.horizontal.3", label: "設定", action: openSettings)
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.refresh() }
        .onChange(of: recordRequested, initial: true) { _, requested in
            guard requested else { return }
            consumeRecordRequest()
            sheet = .record
        }
        // 記した・始めた・伸ばしたあとは、小さな樹も描き直す
        .onChange(of: model.treeRevision) { tree.reload() }
        .sheet(item: $sheet, onDismiss: applyPending) { item in
            switch item {
            case .insight:
                InsightSheet(proposal: model.proposal, engine: engine, previewRequest: previewRequest)
            case .reflection:
                if let entry = model.activeEntry {
                    ReflectionSheet(
                        entry: entry,
                        skills: tree.tree.learnedSkills(touching: entry.resolvedElements()),
                        practiced: practiced(by: entry),
                        glyph: { tree.tree.glyph(of: $0) }
                    ) { rating, note, skills in
                        pending = .finish(rating: rating, note: note, skills: skills)
                    }
                }
            case .record:
                RecordSheet(tree: tree.tree) { draft in
                    pending = .record(draft)
                }
            }
        }
        // 触覚: 気分を選ぶ (軽く)、体験を始める (確かに)、印を押す (重く)
        .sensoryFeedback(.selection, trigger: model.mood)
        .sensoryFeedback(.impact(weight: .medium), trigger: model.activeEntry?.id)
        .sensoryFeedback(.impact(weight: .heavy, intensity: 0.9), trigger: model.completedEntry?.id)
    }

    // MARK: - 真ん中のカード

    @ViewBuilder
    private var stageCard: some View {
        Group {
            switch model.stage {
            case .loading:
                LoadingCard()
                    .transition(.opacity)
            case .proposal:
                if let proposal = model.proposal {
                    ProposalCard(
                        response: proposal,
                        lineage: model.proposalLineage,
                        isLoading: model.isLoading,
                        openBranch: openTree,
                        tryIt: model.tryIt,
                        another: { Task { await model.showAnother() } },
                        notNow: model.notNow,
                        showInsight: { sheet = .insight }
                    )
                    .id(model.proposalID)
                    .transition(reduceMotion ? .opacity : .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))
                }
            case .active:
                if let entry = model.activeEntry {
                    ActiveCard(
                        entry: entry,
                        lineage: model.activeLineage,
                        openBranch: openTree,
                        finish: { sheet = .reflection },
                        abandon: model.abandonActive,
                        presenceChanged: model.presenceSettingChanged(enabled:)
                    )
                    .transition(.scale(scale: 0.96).combined(with: .opacity))
                }
            case .completed:
                if let entry = model.completedEntry {
                    CompletedCard(
                        entry: entry,
                        growth: model.completedGrowth,
                        skills: tree.tree.skills(usedIn: entry.id).filter { tree.tree.state(of: $0.id) == .learned },
                        openTree: openTree,
                        openJournal: openJournal,
                        close: model.dismissCompleted
                    )
                    .transition(.opacity)
                }
            case .failed(let message):
                FailedCard(message: message) {
                    Task { await model.generate() }
                } close: {
                    model.dismissFailure()
                }
                .transition(.opacity)
            case .idle:
                TreeStatusCard(
                    tree: tree.tree,
                    record: { sheet = .record },
                    requestPrompt: { Task { await model.requestPrompt() } },
                    openTree: openTree
                )
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.55, dampingFraction: 0.86), value: stageKey)
    }

    /// 段階ときっかけが変わったときだけ動かす
    private var stageKey: String {
        "\(model.stage)-\(model.proposalID)-\(model.activeEntry?.id.uuidString ?? "")-\(model.completedEntry?.id.uuidString ?? "")"
    }

    /// 稽古として始めた体験なら、選ばなくても数える技 (身についたもの)
    private func practiced(by entry: HistoryEntry) -> [TreeNode] {
        guard let id = entry.nodeID else { return [] }
        return tree.tree.skills(practicing: id).filter { tree.tree.state(of: $0.id) == .learned }
    }

    private func applyPending() {
        guard let action = pending else { return }
        pending = nil
        switch action {
        case .finish(let rating, let note, let skills):
            model.finish(rating: rating, note: note, skills: skills)
        case .record(let draft):
            model.record(draft)
        }
    }
}

// MARK: - 見出し: 日付とあいさつと、小さな技の樹

struct HomeHeader: View {
    let date: Date
    let time: TimeOfDay
    let palette: SkyPalette
    let scene: TreeScene
    /// 芽が出ていて、伸ばせる技がある
    let sprouting: Bool
    let openTree: @MainActor () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(date.formatted(.dateTime.month().day().weekday(.wide))) · \(time.label)")
                    .font(.footnote)
                    .tracking(0.8)
                    .foregroundStyle(palette.onSkySecondary)
                // 「体験|はある」のように途中で折り返さないよう、句の切れ目で改行する
                Text("\(time.greeting)。\nいつもの一日に、\n体験はある。")
                    .font(Typeface.mincho(21, relativeTo: .title2))
                    .lineSpacing(4)
                    .foregroundStyle(palette.onSky)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 8)
            Button(action: openTree) {
                VStack(spacing: 5) {
                    MiniTreeBadge(scene: scene, palette: palette, size: 58)
                        .overlay(alignment: .topTrailing) {
                            if sprouting {
                                Circle()
                                    .fill(Palette.shu)
                                    .frame(width: 9, height: 9)
                                    .offset(x: -2, y: 2)
                            }
                        }
                    Text("技の樹")
                        .font(.caption2)
                        .foregroundStyle(palette.onSkySecondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("技の樹をひらく")
            .accessibilityValue(sprouting ? "芽が出ています" : "")
            .accessibilityIdentifier("home.tree")
        }
        .padding(.horizontal, 4)
    }
}

struct NoticeLine: View {
    let notice: HomeViewModel.Notice
    let palette: SkyPalette

    var body: some View {
        Label(notice.message, systemImage: icon)
            .font(.footnote)
            .foregroundStyle(notice.kind == .error ? Palette.shu : palette.onSkySecondary)
            .padding(.horizontal, 4)
    }

    private var icon: String {
        switch notice.kind {
        case .offline: "wifi.exclamationmark"
        case .degraded: "exclamationmark.circle"
        case .info: "info.circle"
        case .error: "exclamationmark.triangle"
        }
    }
}

struct CalendarInvite: View {
    let palette: SkyPalette
    let allow: @MainActor () -> Void

    var body: some View {
        PaperCard {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "calendar")
                    .font(.title3)
                    .foregroundStyle(Palette.shu)
                VStack(alignment: .leading, spacing: 6) {
                    Text("予定から、きっかけを見つけますか？")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Text("きっかけをもらうときに、今日と明日の予定の、時間とタイトルだけを使います。許可しなくても使えます。")
                        .font(.footnote)
                        .foregroundStyle(Palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("カレンダーを許可", action: allow)
                        .font(.footnote.weight(.semibold))
                        .tint(Palette.shu)
                }
            }
        }
    }
}

// MARK: - 気分 (きっかけを見ているときだけ)

struct MoodChips: View {
    let selected: Mood?
    let palette: SkyPalette
    let choose: @MainActor (Mood) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("いまの気分で選び直す")
                .font(.caption)
                .tracking(1)
                .foregroundStyle(palette.onSkySecondary)
                .padding(.leading, 4)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(Mood.allCases) { mood in
                        Button {
                            choose(mood)
                        } label: {
                            Label(mood.label, systemImage: mood.symbolName)
                                .labelStyle(.titleOnly)
                        }
                        .buttonStyle(ChipButtonStyle(selected: selected == mood))
                        .accessibilityAddTraits(selected == mood ? .isSelected : [])
                        .accessibilityHint(selected == mood ? "もう一度押すと、気分の指定をやめます" : "この気分に合うきっかけに選び直します")
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
    }
}

// MARK: - 今日の印

struct TodayStamps: View {
    let entries: [HistoryEntry]
    let palette: SkyPalette
    let open: @MainActor () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("今日の印")
                .font(.caption)
                .tracking(1.2)
                .foregroundStyle(palette.onSkySecondary)
                .padding(.leading, 4)
            ForEach(entries) { entry in
                Button(action: open) {
                    HStack(spacing: 12) {
                        SealView(character: entry.sealCharacter, size: 34, style: entry.status == .completed ? .outlined : .ghost)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.title)
                                .font(.experienceTitle)
                                .foregroundStyle(Palette.ink)
                                .lineLimit(2)
                            Text(subtitle(for: entry))
                                .font(.caption)
                                .foregroundStyle(Palette.ink3)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background {
                        ZStack {
                            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.ultraThinMaterial)
                            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.panel)
                        }
                    }
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint("体験帳をひらきます")
            }
        }
    }

    private func subtitle(for entry: HistoryEntry) -> String {
        if entry.status == .active { return "体験中" }
        if let note = entry.note { return "「\(note)」" }
        if entry.isSelfRecorded { return "自分で記した体験" }
        return entry.rating?.label ?? ""
    }
}

// MARK: - 話しかける

struct TalkButton: View {
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            Label("話しかける", systemImage: "bubble.left")
                .font(.callout)
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 22)
                .padding(.vertical, 13)
                .background(.ultraThinMaterial, in: Capsule())
                .background(Palette.panel, in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 1))
                .shadow(color: Palette.shadow.opacity(0.4), radius: 14, x: 0, y: 8)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    NavigationStack {
        let deps = AppDependencies.preview()
        HomeView(
            model: deps.home, tree: deps.tree, engine: .library, openChat: {}, openJournal: {}, openTree: { _ in },
            openSettings: {}, previewRequest: { await deps.previewRequest() }
        )
    }
}
