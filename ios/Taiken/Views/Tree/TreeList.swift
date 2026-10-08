import SwiftUI
import TaikenCore

/// 技の樹を、要素ごとの一覧で。要素の根 (段・経験・芽) の下に、浅い技から並べる。
/// 読み上げで使うときは、はじめからこちらを出す
struct TreeList: View {
    @Bindable var model: TreeViewModel
    let open: @MainActor (String) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(Palette.ink3)
                    TextField("技を探す", text: $model.query)
                        .font(.callout)
                        .submitLabel(.search)
                        .accessibilityIdentifier("tree.search")
                    if !model.query.isEmpty {
                        Button {
                            model.query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(Palette.ink3)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("探す言葉を消す")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 11)
                .background(.ultraThinMaterial, in: Capsule())
                .background(Palette.panel, in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 1))

                let sections = visibleSections
                if sections.isEmpty {
                    Text("「\(model.query)」に合う技は、まだ見えていません。霧の中の技は、名前で探せません。")
                        .font(.footnote)
                        .foregroundStyle(Palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 6)
                }
                ForEach(sections) { section in
                    ElementSectionPanel(section: section, model: model, open: open)
                }
                if model.hasHiddenFlashes, model.query.isEmpty, model.highlightedElement == nil {
                    Text("樹のどこかに、まだ閃いていない技があります。どんな暮らし方で現れるかは、書いてありません。")
                        .font(.caption)
                        .foregroundStyle(Palette.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.immediately)
    }

    /// 要素を選んでいれば、その要素だけ
    private var visibleSections: [TreeViewModel.Section] {
        let all = model.sections
        guard let element = model.highlightedElement else { return all }
        return all.filter { $0.element.id == element }
    }
}

/// 要素ひとつぶんの面: 根 (字・名前・段・経験・芽) と、その要素の技
private struct ElementSectionPanel: View {
    let section: TreeViewModel.Section
    let model: TreeViewModel
    let open: @MainActor (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                open(ExperienceTree.rootID(section.element.id))
            } label: {
                header
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("tree.root")

            ForEach(section.nodes) { node in
                Button {
                    open(node.id)
                } label: {
                    NodeRow(model: model, node: node, depth: max(0, model.depth(of: node.id) - 1))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tree.row")
            }
        }
        .padding(16)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(.ultraThinMaterial)
                RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Palette.panel)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(section.isSprouting ? Palette.shu.opacity(0.45) : Palette.line, lineWidth: 1)
        )
    }

    private var header: some View {
        let progress = section.progress
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                ElementMark(glyph: section.element.glyph, size: 32, color: Palette.ink)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(section.element.label)
                            .font(Typeface.mincho(18, bold: true, relativeTo: .headline))
                            .foregroundStyle(Palette.ink)
                        Text(Ranks.label(progress.rank))
                            .font(Typeface.mincho(14, relativeTo: .subheadline))
                            .foregroundStyle(progress.rank > 0 ? Palette.ink : Palette.ink3)
                    }
                    Text(section.element.hint)
                        .font(.caption)
                        .foregroundStyle(Palette.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if progress.sprouts > 0 {
                    Label("芽 \(progress.sprouts)", systemImage: "leaf.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(section.isSprouting ? Palette.shu : Palette.ink2)
                }
            }
            HStack(spacing: 10) {
                ExperienceGauge(gained: progress.gained, span: progress.span, height: 4)
                Text(progress.rank == 0 ? "記すと一段" : "次まで \(progress.remaining)")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink3)
                    .fixedSize()
            }
        }
        .padding(.bottom, 8)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("\(section.element.label)、\(Ranks.label(progress.rank))")
        .accessibilityValue(accessibilityValue(progress))
        .accessibilityHint("要素のページをひらきます")
    }

    private func accessibilityValue(_ progress: ElementProgress) -> String {
        var parts = ["経験 \(progress.experience)"]
        if progress.rank > 0 { parts.append("次の段まで あと\(progress.remaining)") }
        if progress.sprouts > 0 { parts.append("芽 \(progress.sprouts)") }
        if section.isSprouting { parts.append("伸ばせる技があります") }
        return parts.joined(separator: "、")
    }
}
