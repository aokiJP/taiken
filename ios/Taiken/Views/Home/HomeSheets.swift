import SwiftUI
import TaikenCore

// MARK: - 振り返って記す

/// 体験を終えたあと: 問いを思い出し、ひとことだけ残して、体験帳に印を押す。使った技も選べる
struct ReflectionSheet: View {
    let entry: HistoryEntry
    /// 選べる技 (身についた技のうち、この体験の要素に触れるもの)
    let skills: [TreeNode]
    /// 稽古として始めたので、選ばなくても数える技
    let practiced: [TreeNode]
    let glyph: (TreeNode) -> String
    let record: @MainActor (Rating, String?, [String]) -> Void

    @State private var rating: Rating?
    @State private var note = ""
    @State private var chosen: [String] = []
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

                skillPicker

                Button("記す") {
                    guard let rating else { return }
                    let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
                    record(rating, trimmed.isEmpty ? nil : trimmed, chosen)
                    dismiss()
                }
                .buttonStyle(ShuButtonStyle())
                .disabled(rating == nil)
                .accessibilityHint(rating == nil ? "先に、どうだったかを選んでください" : "体験帳に印を押します")
                .accessibilityIdentifier("reflection.record")
            }
            .padding(22)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.paper)
        .sensoryFeedback(.selection, trigger: rating)
        .sensoryFeedback(.selection, trigger: chosen)
    }

    @ViewBuilder
    private var skillPicker: some View {
        let practicedIDs = Set(practiced.map(\.id))
        let choices = skills.filter { !practicedIDs.contains($0.id) }
        if !practiced.isEmpty || !choices.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                MiniHead("使った技（なくてもよい）")
                if !practiced.isEmpty {
                    Text("\(practiced.map { "「\($0.title)」" }.joined())の稽古なので、選ばなくても数えます。")
                        .font(.caption)
                        .foregroundStyle(Palette.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !choices.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(choices) { node in
                            SkillChip(node: node, glyph: glyph(node), selected: chosen.contains(node.id)) {
                                toggle(node.id)
                            }
                        }
                    }
                    Text("使った技を選ぶと、その技の記録になり、守・破・離と深まっていきます。")
                        .font(.caption)
                        .foregroundStyle(Palette.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func toggle(_ id: String) {
        if let index = chosen.firstIndex(of: id) {
            chosen.remove(at: index)
        } else {
            chosen.append(id)
        }
    }
}

// MARK: - 体験を記す (自分で見つけた体験)

/// 体験を記す: いつもの一日で体験したことを、自分の言葉でひとこと。触れた要素と、使った技を選ぶ。
/// 記した言葉は、この端末の体験帳にだけ残る (AIには送らない)
struct RecordSheet: View {
    let tree: ExperienceTree
    let record: @MainActor (LivedDraft) -> Void

    @State private var draft = LivedDraft()
    /// 要素を自分で選んだら、言葉からの推し量りで上書きしない
    @State private var choseElements = false
    @FocusState private var textFocused: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                SheetHeader(title: "体験を記す", lead: "いつもの一日で、何を体験しましたか？")

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        MiniHead("自分の言葉で、ひとこと")
                        Spacer()
                        let count = draft.text.trimmingCharacters(in: .whitespacesAndNewlines).count
                        Text("\(count)/\(LivedDraft.textLimit)")
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundStyle(count > LivedDraft.textLimit ? Palette.shu : Palette.ink3)
                            .accessibilityLabel("\(LivedDraft.textLimit)文字まで、いま\(count)文字")
                    }
                    TextField("例: 帰り道、パン屋の前で足が止まった", text: $draft.text, axis: .vertical)
                        .font(Typeface.mincho(17))
                        .lineLimit(2...4)
                        .focused($textFocused)
                        .accessibilityIdentifier("record.text")
                        .padding(14)
                        .background(Palette.wash, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
                }

                elementPicker

                if !draft.elements.isEmpty {
                    growthPreview
                }

                skillPicker

                VStack(alignment: .leading, spacing: 10) {
                    Button("記す") {
                        record(draft)
                        dismiss()
                    }
                    .buttonStyle(ShuButtonStyle())
                    .disabled(!draft.isReady)
                    .accessibilityHint(draft.isReady ? "体験帳に印を押します" : "ひとことと、触れた要素を選んでください")
                    .accessibilityIdentifier("record.save")
                    Text("記した言葉は、この端末の体験帳にだけ残ります。AIには送りません。")
                        .font(.caption)
                        .foregroundStyle(Palette.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(22)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.paper)
        .onAppear { textFocused = true }
        .onChange(of: draft.text) { _, text in suggestElements(for: text) }
        .onChange(of: draft.elements) { _, _ in keepOnlyAvailableSkills() }
        .sensoryFeedback(.selection, trigger: draft.elements)
    }

    // MARK: 要素

    private var elementPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            MiniHead("触れた要素（3つまで）")
            FlowLayout(spacing: 8) {
                ForEach(tree.elements) { element in
                    let selected = draft.elements.contains(element.id)
                    Button {
                        toggle(element: element.id)
                    } label: {
                        HStack(spacing: 6) {
                            Text(element.glyph)
                                .font(Typeface.fixedMincho(14))
                            Text(element.label)
                        }
                    }
                    .buttonStyle(ChipButtonStyle(selected: selected))
                    .accessibilityLabel(element.label)
                    .accessibilityHint(element.hint)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            Text(choseElements || draft.elements.isEmpty
                ? "体験の中で、はたらいていた感覚や力を選んでください。"
                : "言葉から推し量りました。違っていたら、選び直してください。")
                .font(.caption)
                .foregroundStyle(Palette.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func toggle(element id: String) {
        choseElements = true
        if let index = draft.elements.firstIndex(of: id) {
            draft.elements.remove(at: index)
        } else if draft.elements.count < 3 {
            draft.elements.append(id)
        }
    }

    private func suggestElements(for text: String) {
        guard !choseElements else { return }
        draft.elements = ElementClassifier(content: tree.content).suggest(for: text)
    }

    // MARK: 記すと、どう伸びるか

    private var growthPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            MiniHead("記すと")
            ForEach(draft.elements, id: \.self) { id in
                if let element = tree.element(id) {
                    let progress = tree.progress(of: id)
                    HStack(spacing: 8) {
                        ElementMark(glyph: element.glyph, size: 18, color: Palette.ink)
                        Text("\(element.label) 経験 +1")
                            .font(.footnote)
                            .foregroundStyle(Palette.ink)
                        Spacer(minLength: 0)
                        Text(nextText(progress))
                            .font(.caption)
                            .foregroundStyle(progress.remaining <= 1 ? Palette.shu : Palette.ink3)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func nextText(_ progress: ElementProgress) -> String {
        let next = Ranks.label(progress.rank + 1)
        return progress.remaining <= 1 ? "\(next)に (芽が出ます)" : "あと\(progress.remaining - 1)で\(next)"
    }

    // MARK: 使った技

    @ViewBuilder
    private var skillPicker: some View {
        let choices = skillChoices
        if !choices.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                MiniHead("使った技（なくてもよい）")
                FlowLayout(spacing: 8) {
                    ForEach(choices) { node in
                        SkillChip(
                            node: node, glyph: tree.glyph(of: node), selected: draft.skills.contains(node.id),
                            hinted: suggestedIDs.contains(node.id)
                        ) {
                            toggle(skill: node.id)
                        }
                    }
                }
                Text("使った技を選ぶと、その技の記録になり、守・破・離と深まっていきます。")
                    .font(.caption)
                    .foregroundStyle(Palette.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 身についた技のうち、選んだ要素に触れるもの (言葉から推し量れたものを先に)
    private var skillChoices: [TreeNode] {
        let all = tree.learnedSkills(touching: draft.elements)
        let hinted = suggestedIDs
        return all.filter { hinted.contains($0.id) } + all.filter { !hinted.contains($0.id) }
    }

    private var suggestedIDs: Set<String> {
        Set(tree.suggestedSkills(for: draft.text, elements: draft.elements).map(\.id))
    }

    private func toggle(skill id: String) {
        if let index = draft.skills.firstIndex(of: id) {
            draft.skills.remove(at: index)
        } else {
            draft.skills.append(id)
        }
    }

    /// 要素を外したら、その要素に触れない技の選択も外す
    private func keepOnlyAvailableSkills() {
        let available = Set(tree.learnedSkills(touching: draft.elements).map(\.id))
        draft.skills.removeAll { !available.contains($0) }
    }
}

/// 使った技を選ぶ札 (身についた技の印と名前)
struct SkillChip: View {
    let node: TreeNode
    let glyph: String
    let selected: Bool
    /// 記した言葉から、使ったかもしれないと推し量れた
    var hinted = false
    let toggle: @MainActor () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 6) {
                SealView(character: glyph, size: 16, style: selected ? .filled : .outlined, rotation: -4)
                Text(node.title)
                if hinted && !selected {
                    Text("かも")
                        .font(.caption2)
                        .opacity(0.7)
                }
            }
        }
        .buttonStyle(ChipButtonStyle(selected: selected))
        .accessibilityLabel(node.title)
        .accessibilityValue(hinted ? "使ったかもしれない技" : "")
        .accessibilityHint(node.ability)
        .accessibilityAddTraits(selected ? .isSelected : [])
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

// MARK: - きっかけの手がかり

/// 「なぜこのきっかけなのか」を、事実と推測を分けて見せる (指示書 §7, §9)。
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
                    ContentUnavailableView("いまはきっかけがありません", systemImage: "sparkles")
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
        proposal?.source.isGenerative == true ? "AIが見たこと" : "きっかけの手がかり"
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
                MiniHead("きっかけをつくったしくみ")
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
                    Text(engine == .server ? "次にサーバーへ渡す内容を確かめる" : "次のきっかけに使う内容を確かめる")
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
            "次にきっかけをもらうときに、自分のサーバーへ送る内容です。自分で記した体験と、ひとことは送りません。送るものを増やしたときは、ここにも必ず表示します。会話は保存されません。"
        case .onDevice:
            "この iPhone の中のAIに渡す内容です。端末の外には出ません。"
        case .library:
            "体験ライブラリからきっかけを選ぶときに使う内容です。端末の外には出ません。"
        }
    }
}
