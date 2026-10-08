import SwiftUI
import TaikenCore

// MARK: - 振り返って記す

/// 体験を終えたあと: 問いを思い出し、ひとことだけ残して、体験帳に印を押す
struct ReflectionSheet: View {
    let entry: HistoryEntry
    let record: @MainActor (Rating, String?) -> Void

    @State private var rating: Rating?
    @State private var note = ""
    @FocusState private var noteFocused: Bool
    @Environment(\.dismiss) private var dismiss

    private static let noteLimit = 200

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SheetHeader(title: entry.title, lead: "体験帳に記す")

                Text(entry.reflectionQuestion ?? "やってみて、どうでしたか？")
                    .font(.question)
                    .lineSpacing(5)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 10) {
                    ForEach(Rating.allCases, id: \.self) { value in
                        RatingTile(rating: value, selected: rating == value) {
                            rating = value
                        }
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("どうでしたか")

                VStack(alignment: .leading, spacing: 8) {
                    Text("ひとこと残す（この端末だけに残ります）")
                        .font(.caption)
                        .foregroundStyle(Palette.ink3)
                    TextField("気づいたこと、ひとつだけ", text: $note, axis: .vertical)
                        .font(Typeface.mincho(16))
                        .lineLimit(2...5)
                        .focused($noteFocused)
                        .accessibilityIdentifier("reflection.note")
                        .padding(14)
                        .background(Palette.wash, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                        .onChange(of: note) { _, value in
                            if value.count > Self.noteLimit { note = String(value.prefix(Self.noteLimit)) }
                        }
                }

                Button("記す") {
                    guard let rating else { return }
                    let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
                    record(rating, trimmed.isEmpty ? nil : trimmed)
                    dismiss()
                }
                .buttonStyle(ShuButtonStyle())
                .disabled(rating == nil)
                .accessibilityHint(rating == nil ? "先に、どうだったかを選んでください" : "体験帳に印を押します")
            }
            .padding(22)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.paper)
        .sensoryFeedback(.selection, trigger: rating)
    }
}

/// 振り返りの選択肢。絵文字ではなく、静かな記号と言葉で
private struct RatingTile: View {
    let rating: Rating
    let selected: Bool
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: rating.symbolName)
                    .font(.system(size: 24, weight: .light))
                    .symbolEffect(.bounce, value: selected)
                Text(rating.label)
                    .font(.footnote.weight(.medium))
            }
            .foregroundStyle(selected ? Palette.shu : Palette.ink2)
            .frame(maxWidth: .infinity, minHeight: 92)
            .background(selected ? Palette.shuSoft : Palette.wash, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(selected ? Palette.shu : Palette.line, lineWidth: selected ? 1.5 : 1)
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.75), value: selected)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(rating.label)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - 提案の手がかり

/// 「なぜこの提案なのか」を、事実と推測を分けて見せる (指示書 §7, §9)。
/// 次に渡す内容 (送る前のリクエスト) まで、ここから確かめられる
struct InsightSheet: View {
    let proposal: ExperienceResponse?
    let engine: ProposalEngine
    let previewRequest: @MainActor () async -> ExperienceRequest

    var body: some View {
        NavigationStack {
            ScrollView {
                if let proposal {
                    content(proposal)
                        .padding(22)
                } else {
                    ContentUnavailableView("いまは提案がありません", systemImage: "sparkles")
                        .padding(.top, 60)
                }
            }
            .background(Palette.paper)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    CloseToolbarButton()
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.paper)
    }

    private var title: String {
        proposal?.source.isGenerative == true ? "AIが見たこと" : "提案の手がかり"
    }

    @ViewBuilder
    private func content(_ proposal: ExperienceResponse) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("事実と推測を分けて表示しています。")
                .font(.footnote)
                .foregroundStyle(Palette.ink3)

            VStack(alignment: .leading, spacing: 10) {
                MiniHead("状況")
                Text(proposal.situation.summary)
                    .font(Typeface.mincho(16))
                    .lineSpacing(4)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if proposal.situation.observations.isEmpty {
                    Text("今回は、予定や発言の手がかりはありませんでした。")
                        .font(.footnote)
                        .foregroundStyle(Palette.ink2)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(proposal.situation.observations, id: \.self) { note in
                            SituationNoteRow(note: note)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                MiniHead("選んだ理由")
                Text(proposal.experience.reason)
                    .font(.callout)
                    .lineSpacing(3)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !proposal.possibleObligations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    MiniHead("やらなければならないことかもしれないもの")
                    ForEach(proposal.possibleObligations, id: \.self) { item in
                        KeyValueRow(key: Self.likelihoodLabel(item.likelihood), value: item.label)
                    }
                    Text("義務を無理に楽しいものに変えようとはしません。")
                        .font(.caption)
                        .foregroundStyle(Palette.ink3)
                }
            }

            let references = proposal.references.filter { $0.safeURL != nil }
            if !references.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    MiniHead("参照した情報")
                    ForEach(references, id: \.self) { reference in
                        if let url = reference.safeURL {
                            Link(destination: url) {
                                Label(reference.title, systemImage: "arrow.up.right.square")
                                    .font(.footnote)
                            }
                            .tint(Palette.shu)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                MiniHead("提案をつくったしくみ")
                Text(proposal.source.engineLabel)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text(detail(for: proposal))
                    .font(.footnote)
                    .foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            NavigationLink {
                RequestPreviewView(engine: engine, load: previewRequest)
            } label: {
                HStack {
                    Image(systemName: "doc.text.magnifyingglass")
                    Text(engine == .server ? "次にサーバーへ渡す内容を確かめる" : "次の提案に使う内容を確かめる")
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote)
                        .foregroundStyle(Palette.ink3)
                }
                .font(.callout)
                .foregroundStyle(Palette.ink)
                .padding(14)
                .background(Palette.wash, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func detail(for proposal: ExperienceResponse) -> String {
        switch proposal.source {
        case .ai, .mock: ProposalEngine.server.detail
        case .onDevice: ProposalEngine.onDevice.detail
        case .local: ProposalEngine.library.detail
        case .fallback: "サーバーのAIが使えなかったため、サーバー側の体験ライブラリから選びました。"
        }
    }

    static func likelihoodLabel(_ value: Double) -> String {
        switch value {
        case ..<0.34: "たぶん違う"
        case ..<0.67: "どちらとも"
        default: "たぶんそう"
        }
    }
}

/// ナビゲーションバーの「閉じる」
struct CloseToolbarButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button("閉じる") { dismiss() }
            .tint(Palette.ink)
    }
}

// MARK: - 次に渡す内容

/// 送る前のリクエストを、人が読める形と実際のデータの両方で見せる
struct RequestPreviewView: View {
    let engine: ProposalEngine
    let load: @MainActor () async -> ExperienceRequest
    @State private var request: ExperienceRequest?
    @State private var showsJSON = false

    var body: some View {
        List {
            if let request {
                Section {
                    ForEach(RequestPreview.sections(for: request)) { section in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(section.title)
                                .font(.caption)
                                .foregroundStyle(Palette.ink3)
                            ForEach(Array(section.items.enumerated()), id: \.offset) { item in
                                Text(item.element)
                                    .font(.callout)
                                    .foregroundStyle(item.element == RequestPreview.notSent ? Palette.ink3 : Palette.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(.vertical, 2)
                        .accessibilityElement(children: .combine)
                    }
                } footer: {
                    Text(footer)
                }
                Section {
                    DisclosureGroup("実際のデータ（JSON）", isExpanded: $showsJSON) {
                        ScrollView(.horizontal) {
                            Text(RequestPreview.json(for: request))
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(.vertical, 6)
                        }
                    }
                }
            } else {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.paper.ignoresSafeArea())
        .navigationTitle("次に渡す内容")
        .navigationBarTitleDisplayMode(.inline)
        .task { request = await load() }
        .refreshable { request = await load() }
    }

    private var footer: String {
        switch engine {
        case .server:
            "次の提案のときに、自分のサーバーへ送る内容です。送るものを増やしたときは、ここにも必ず表示します。会話は保存されません。"
        case .onDevice:
            "この iPhone の中のAIに渡す内容です。端末の外には出ません。"
        case .library:
            "体験ライブラリから選ぶときに使う内容です。端末の外には出ません。"
        }
    }
}
