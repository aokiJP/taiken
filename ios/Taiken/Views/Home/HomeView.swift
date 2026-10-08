import SwiftUI
import TaikenCore

/// 指示書 §6, §21: 「今日何をするか」ではなく「今日、何を体験できるか」を中心に置く。
/// 地はいまの空。真ん中に、その時いちばん大事なカードがひとつだけある。
struct HomeView: View {
    let model: HomeViewModel
    let engine: ProposalEngine
    let openChat: @MainActor () -> Void
    let openJournal: @MainActor () -> Void
    let openSettings: @MainActor () -> Void
    let previewRequest: @MainActor () async -> ExperienceRequest
    /// この一年で体験を記した七十二候 (季節の輪に灯す)
    let livedSeasons: @MainActor () -> Set<Int>

    @State private var sheet: HomeSheet?
    @State private var lived: Set<Int> = []
    /// 振り返りのシートが閉じきってから印を押す (押す瞬間を見てもらうため)
    @State private var pendingRecord: PendingRecord?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum HomeSheet: String, Identifiable {
        case insight, reflection, season
        var id: String { rawValue }
    }

    struct PendingRecord {
        let rating: Rating
        let note: String?
    }

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            let time = TimeOfDay.at(timeline.date, calendar: .current)
            let palette = time.sky(dark: colorScheme == .dark)
            ZStack {
                SkyBackground(time: time)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        SeasonHeader(date: timeline.date, time: time, season: model.season, palette: palette) {
                            lived = livedSeasons()
                            sheet = .season
                        }
                        if let notice = model.notice {
                            NoticeLine(notice: notice, palette: palette)
                        }
                        if model.calendarAccess == .notDetermined, model.stage != .active {
                            CalendarInvite(palette: palette) { Task { await model.requestCalendarAccess() } }
                        }
                        stageCard
                        if model.stage != .active {
                            MoodChips(selected: model.mood, palette: palette) { mood in
                                Task { await model.choose(mood: mood) }
                            }
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
        .task(id: model.restingUntil) { await wakeWhenRestEnds() }
        .sheet(item: $sheet, onDismiss: { applyPendingRecord() }) { item in
            switch item {
            case .insight:
                InsightSheet(proposal: model.proposal, engine: engine, previewRequest: previewRequest)
            case .reflection:
                if let entry = model.activeEntry {
                    ReflectionSheet(entry: entry) { rating, note in
                        pendingRecord = PendingRecord(rating: rating, note: note)
                    }
                }
            case .season:
                SeasonSheet(season: model.season, lived: lived)
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
                        isLoading: model.isLoading,
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
                        season: MicroSeason.at(entry.createdAt, calendar: .current),
                        another: { Task { await model.wakeUp() } },
                        openJournal: openJournal
                    )
                    .transition(.opacity)
                }
            case .resting(let until):
                RestingCard(until: until) { Task { await model.wakeUp() } }
                    .transition(.opacity)
            case .failed(let message):
                RestingCard(title: "提案を作れませんでした", message: message, actionTitle: "もう一度") {
                    Task { await model.generate() }
                }
                .transition(.opacity)
            case .idle:
                RestingCard(title: "また気が向いたら。", message: "提案はいつでも受け取れます。", actionTitle: "提案を受け取る") {
                    Task { await model.wakeUp() }
                }
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.55, dampingFraction: 0.86), value: stageKey)
    }

    /// 段階と提案が変わったときだけ動かす
    private var stageKey: String {
        "\(model.stage)-\(model.proposalID)-\(model.activeEntry?.id.uuidString ?? "")-\(model.completedEntry?.id.uuidString ?? "")"
    }

    private func applyPendingRecord() {
        guard let record = pendingRecord else { return }
        pendingRecord = nil
        model.finish(rating: record.rating, note: record.note)
    }

    /// ひと休みが終わったら、開いたままでも次の提案を用意する
    private func wakeWhenRestEnds() async {
        guard let until = model.restingUntil else { return }
        let wait = until.timeIntervalSinceNow
        if wait > 0 {
            try? await Task.sleep(for: .seconds(wait + 1))
        }
        guard !Task.isCancelled else { return }
        await model.refresh()
    }
}

// MARK: - 見出し: 日付と、七十二候の短冊

struct SeasonHeader: View {
    let date: Date
    let time: TimeOfDay
    let season: MicroSeason
    let palette: SkyPalette
    let openSeason: @MainActor () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(date.formatted(.dateTime.month().day().weekday(.wide))) · \(time.label)")
                    .font(.footnote)
                    .tracking(0.8)
                    .foregroundStyle(palette.onSkySecondary)
                Text("\(time.greeting)。\n今日、何を体験できるか。")
                    .font(Typeface.mincho(21, relativeTo: .title2))
                    .lineSpacing(4)
                    .foregroundStyle(palette.onSky)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: 8) {
                    Text("\(season.solarTerm)・\(season.positionLabel)")
                        .font(.footnote.weight(.semibold))
                    Text(season.meaning)
                        .font(.footnote)
                        .foregroundStyle(palette.onSkySecondary)
                }
                .foregroundStyle(palette.onSky)
                .padding(.top, 2)
            }
            Spacer(minLength: 8)
            Button(action: openSeason) {
                TanzakuView(text: season.name, size: 21, foreground: palette.onSky, border: palette.onSky.opacity(0.26))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("七十二候 \(season.name)（\(season.reading)）について")
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
                    Text("予定から体験を見つけますか？")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                    Text("今日と明日の予定の、時間とタイトルだけを使います。許可しなくても使えます。")
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

// MARK: - 気分

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
                        .accessibilityHint(selected == mood ? "もう一度押すと、気分の指定をやめます" : "この気分に合う体験に選び直します")
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
            model: deps.home, engine: .library, openChat: {}, openJournal: {}, openSettings: {},
            previewRequest: { await deps.previewRequest() }, livedSeasons: { deps.history.stats.microSeasons }
        )
    }
}
