import SwiftUI
import TaikenCore

/// 技を編むときの行き先 (新しく編む・どこから伸ばすか・書き直す)
struct WeaveRoute: Identifiable, Hashable {
    let id = UUID()
    var growsFrom: String?
    /// はじめから選んでおく要素
    var elements: [String] = []
    /// 書き直す技
    var revising: String?

    init(growsFrom: String? = nil, elements: [String] = []) {
        self.growsFrom = growsFrom
        self.elements = elements
    }

    init(revising id: String) {
        revising = id
    }
}

/// 技を編む: 暮らしの中で身につきかけている自分だけの見方や力に、名前をつけて樹に植える。
/// 植えた技も、ほかの技と同じく芽を使って伸ばす (編んだだけでは、まだ身についていない)。
struct WeaveSheet: View {
    let model: TreeViewModel
    let route: WeaveRoute
    var created: @MainActor (String) -> Void = { _ in }

    @State private var draft = WeaveDraft()
    @State private var loaded = false
    @State private var triedSaving = false
    @FocusState private var focused: Field?
    @Environment(\.dismiss) private var dismiss

    enum Field: Hashable { case title, ability, practice }

    private var isRevising: Bool { route.revising != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(isRevising
                        ? "名前・できるようになること・稽古・要素を書き直せます。身についていれば、身についたままです。"
                        : "暮らしの中で、身につきかけている自分だけの見方や力に、名前をつけて樹に植えます。植えた技は、ほかの技と同じく芽を使って伸ばします。")
                        .font(.footnote)
                        .foregroundStyle(Palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)

                    field(
                        "名前", text: $draft.title, prompt: "例: 湯気のゆくえ", limit: WeaveDraft.titleLimit,
                        multiline: false, focus: .title
                    )
                    field(
                        "身につくと、できるようになること", text: $draft.ability,
                        prompt: "例: 湯気が消えるところまで、見届けられる。",
                        limit: WeaveDraft.abilityLimit, multiline: true, focus: .ability
                    )
                    field(
                        "自分の稽古（なくてもよい）", text: $draft.practice,
                        prompt: "例: 温かい飲み物を入れたら、湯気がどこで見えなくなるかを追ってみる",
                        limit: WeaveDraft.practiceLimit, multiline: true, focus: .practice
                    )

                    elementPicker
                    parentPicker

                    VStack(alignment: .leading, spacing: 10) {
                        if triedSaving, let problem = problems.first {
                            Label(problem.message, systemImage: "exclamationmark.circle")
                                .font(.footnote)
                                .foregroundStyle(Palette.shu)
                        } else if triedSaving, let message = model.errorMessage {
                            Label(message, systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(Palette.shu)
                        }
                        Button(isRevising ? "書き直す" : "樹に植える", action: save)
                            .buttonStyle(ShuButtonStyle())
                            .accessibilityIdentifier("weave.save")
                        Text("編んだ技は、この端末の中の樹に置かれます。体験帳と同じく、iCloud にも送りません。")
                            .font(.caption)
                            .foregroundStyle(Palette.ink3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(22)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Palette.paper.ignoresSafeArea())
            .navigationTitle(isRevising ? "書き直す" : "技を編む")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    CloseToolbarButton()
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.paper)
        .onAppear(perform: load)
        .sensoryFeedback(.selection, trigger: draft.elements)
    }

    // MARK: - 書く欄

    private func field(
        _ title: String, text: Binding<String>, prompt: String, limit: Int, multiline: Bool, focus: Field
    ) -> some View {
        let count = text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).count
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                MiniHead(title)
                Spacer()
                Text("\(count)/\(limit)")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(count > limit ? Palette.shu : Palette.ink3)
                    .accessibilityLabel("\(limit)文字まで、いま\(count)文字")
            }
            Group {
                if multiline {
                    TextField(prompt, text: text, axis: .vertical)
                        .lineLimit(2...5)
                } else {
                    TextField(prompt, text: text)
                        .submitLabel(.next)
                }
            }
            .font(Typeface.mincho(16))
            .foregroundStyle(Palette.ink)
            .focused($focused, equals: focus)
            .padding(14)
            .background(Palette.wash, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(count > limit ? Palette.shu : Palette.line, lineWidth: 1)
            )
            .accessibilityIdentifier("weave.\(focus)")
        }
    }

    // MARK: - 要素

    private var elementPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            MiniHead("要素（\(WeaveDraft.elementLimit)つまで。最初に選んだものの段が、伸ばす条件になります）")
            FlowLayout(spacing: 8) {
                ForEach(model.tree.elements) { element in
                    let order = draft.elements.firstIndex(of: element.id)
                    Button {
                        toggle(element.id)
                    } label: {
                        HStack(spacing: 6) {
                            Text(element.glyph)
                                .font(Typeface.fixedMincho(14))
                            Text(element.label)
                            if order == 0 {
                                Text("主")
                                    .font(.caption2.weight(.bold))
                            }
                        }
                    }
                    .buttonStyle(ChipButtonStyle(selected: order != nil))
                    .accessibilityLabel(element.label)
                    .accessibilityValue(order == 0 ? "主な要素" : "")
                    .accessibilityAddTraits(order != nil ? .isSelected : [])
                }
            }
            if let first = draft.elements.first, let element = model.tree.element(first) {
                Text(element.hint)
                    .font(.caption)
                    .foregroundStyle(Palette.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func toggle(_ id: String) {
        if let index = draft.elements.firstIndex(of: id) {
            draft.elements.remove(at: index)
        } else if draft.elements.count < WeaveDraft.elementLimit {
            draft.elements.append(id)
        }
    }

    // MARK: - どこから伸ばすか

    private var parentPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            MiniHead("どこから伸ばすか")
            Picker("どこから伸ばすか", selection: $draft.growsFrom) {
                Text("要素の根から").tag(String?.none)
                ForEach(parentCandidates) { node in
                    Text(node.title).tag(Optional(node.id))
                }
            }
            .pickerStyle(.menu)
            .tint(Palette.ink)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.wash, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text(draft.growsFrom == nil
                ? "根から伸ばすと、主な要素が一段あれば伸ばせます。"
                : "身についた技から伸ばすと、その先の技として樹に出ます。")
                .font(.caption)
                .foregroundStyle(Palette.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 伸ばす元の候補: 身についた技 (いま選んでいる元も)
    private var parentCandidates: [TreeNode] {
        model.weaveParents(excluding: route.revising, current: draft.growsFrom)
    }

    // MARK: - 植える

    private var problems: [WeaveDraft.Problem] {
        model.problems(of: draft, revising: route.revising)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let id = route.revising, let node = model.node(id) {
            draft = model.draft(for: node)
        } else {
            draft = WeaveDraft(elements: Array(route.elements.prefix(WeaveDraft.elementLimit)), growsFrom: route.growsFrom)
            focused = .title
        }
    }

    private func save() {
        triedSaving = true
        guard problems.isEmpty else { return }
        if let id = route.revising {
            if model.revise(id, with: draft) { dismiss() }
        } else if let node = model.weave(draft) {
            dismiss()
            created(node.id)
        }
    }
}
