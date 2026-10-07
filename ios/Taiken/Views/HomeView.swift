import SwiftUI
import TaikenCore

/// 指示書 §6, §21: 「今日何をするか」ではなく「今日、何を体験できるか」を中心に置く。
struct HomeView: View {
    let model: HomeViewModel
    let openChat: @MainActor () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header

                if model.calendarAccess == .notDetermined {
                    CalendarInviteBanner { Task { await model.requestCalendarAccess() } }
                }

                if let notice = model.notice {
                    NoticeLine(notice: notice)
                }

                centerCard

                if let situation = model.proposal?.situation, !situation.summary.isEmpty {
                    SituationSection(situation: situation)
                }

                if let references = model.proposal?.references, !references.isEmpty {
                    ReferencesSection(references: references)
                }

                if !model.todayEntries.isEmpty {
                    TodaySection(entries: model.todayEntries)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) {
            Button(action: openChat) {
                Label("AIと話す", systemImage: "bubble.left.and.text.bubble.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .task { await model.refresh() }
        .refreshable {
            if model.activeEntry == nil { await model.generate() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(Date.now, format: .dateTime.month().day().weekday(.wide))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("今日、何を体験できるか")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
        }
    }

    @ViewBuilder
    private var centerCard: some View {
        if let entry = model.activeEntry {
            ActiveExperienceCard(
                entry: entry,
                finish: { rating, note in model.finish(rating: rating, note: note) },
                abandon: model.abandonActive
            )
        } else if let proposal = model.proposal {
            ProposalCard(
                experience: proposal.experience,
                isLoading: model.isLoading,
                tryIt: model.tryIt,
                another: { Task { await model.showAnother() } },
                notNow: model.notNow
            )
        } else {
            switch model.phase {
            case .loading:
                CardContainer {
                    ProgressView("いつもの一日を眺めています…")
                        .frame(maxWidth: .infinity, minHeight: 160)
                }
            case .failed(let message):
                EmptyCard(message: message, actionTitle: "もう一度") { Task { await model.generate() } }
            case .idle, .ready:
                EmptyCard(message: "提案はお休み中です。気が向いたら、また見てみてください。", actionTitle: "提案を見る") {
                    Task { await model.generate() }
                }
            }
        }
    }
}

// MARK: - カード

struct ProposalCard: View {
    let experience: Experience
    let isLoading: Bool
    let tryIt: @MainActor () -> Void
    let another: @MainActor () -> Void
    let notNow: @MainActor () -> Void
    @State private var showsReason = false

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 18) {
                Text("今日の体験")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(experience.title)
                    .font(.headline)

                Text(experience.invitation)
                    .font(.system(.title3, design: .serif))
                    .fixedSize(horizontal: false, vertical: true)

                Text(experience.perspective)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                DisclosureGroup("なぜ今？", isExpanded: $showsReason) {
                    Text(experience.reason)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                .font(.footnote)

                VStack(spacing: 10) {
                    Button(action: tryIt) {
                        Text("やってみる").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    HStack(spacing: 10) {
                        Button(action: another) {
                            Group {
                                if isLoading { ProgressView() } else { Text("別の提案") }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        Button(action: notNow) {
                            Text("今はやらない").frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                .disabled(isLoading)
            }
        }
        .animation(.default, value: experience)
    }
}

struct ActiveExperienceCard: View {
    let entry: HistoryEntry
    let finish: @MainActor (Rating, String?) -> Void
    let abandon: @MainActor () -> Void
    @State private var note = ""
    @State private var confirmsAbandon = false

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label("体験中", systemImage: "sparkle")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                    Spacer()
                    Menu {
                        Button("この体験をやめる", role: .destructive) { confirmsAbandon = true }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .accessibilityLabel("その他の操作")
                }

                Text(entry.title)
                    .font(.headline)

                Text(entry.invitation)
                    .font(.system(.title3, design: .serif))
                    .fixedSize(horizontal: false, vertical: true)

                Divider()

                Text("やってみて、どうでしたか？")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextField("ひとこと (任意・この端末にだけ残ります)", text: $note, axis: .vertical)
                    .lineLimit(1...3)
                    .font(.footnote)
                    .padding(10)
                    .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 12))

                HStack(spacing: 12) {
                    ForEach(Rating.allCases, id: \.self) { rating in
                        Button {
                            finish(rating, note)
                            note = ""
                        } label: {
                            Text(rating.emoji)
                                .font(.title)
                                .frame(maxWidth: .infinity, minHeight: 52)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel(rating.label)
                    }
                }
            }
        }
        .confirmationDialog("この体験をやめますか？", isPresented: $confirmsAbandon, titleVisibility: .visible) {
            Button("やめる", role: .destructive, action: abandon)
        } message: {
            Text("評価はせずに終わります。")
        }
    }
}

struct EmptyCard: View {
    let message: String
    let actionTitle: String
    let action: @MainActor () -> Void

    var body: some View {
        CardContainer {
            VStack(alignment: .leading, spacing: 16) {
                Text(message)
                    .foregroundStyle(.secondary)
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
            }
        }
    }
}

struct CalendarInviteBanner: View {
    let allow: @MainActor () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "calendar")
                .font(.title3)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 8) {
                Text("予定から体験を見つけますか？")
                    .font(.subheadline.weight(.semibold))
                Text("今日と明日の予定の時間とタイトルだけを使います。許可しなくても使えます。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("カレンダーを許可", action: allow)
                    .font(.footnote.weight(.semibold))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
    }
}

struct NoticeLine: View {
    let notice: HomeViewModel.Notice

    var body: some View {
        Label(notice.message, systemImage: icon)
            .font(.footnote)
            .foregroundStyle(notice.kind == .error ? Color.red : Color.secondary)
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

// MARK: - 状態・参照・今日の履歴

struct SituationSection: View {
    let situation: Situation
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("今日の状態")
                .font(.subheadline.weight(.semibold))
            Text(situation.summary)
                .font(.callout)
                .foregroundStyle(.secondary)

            if !situation.observations.isEmpty {
                DisclosureGroup("AIが受け取ったこと", isExpanded: $expanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(situation.observations, id: \.self) { SituationNoteRow(note: $0) }
                    }
                    .padding(.top, 6)
                }
                .font(.footnote)
            }
        }
    }
}

struct ReferencesSection: View {
    let references: [Reference]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("参考にした情報")
                .font(.subheadline.weight(.semibold))
            ForEach(references, id: \.self) { reference in
                if let url = reference.safeURL {
                    Link(destination: url) {
                        Label(reference.title, systemImage: "link")
                            .font(.footnote)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

struct TodaySection: View {
    let entries: [HistoryEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("今日の体験")
                .font(.subheadline.weight(.semibold))
            ForEach(entries) { entry in
                HStack(spacing: 12) {
                    Text(entry.rating?.emoji ?? "…")
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title).font(.callout)
                        Text(entry.createdAt, format: .dateTime.hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if entry.status == .active {
                        Text("体験中").font(.caption).foregroundStyle(.tint)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

#Preview {
    NavigationStack {
        HomeView(model: AppDependencies.preview().home, openChat: {})
    }
}
