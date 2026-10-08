import SwiftUI
import TaikenCore

/// 体験の樹を、要素ごとの一覧で。根から順に、つながりの深さで字下げする。
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
                    TextField("体験を探す", text: $model.query)
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
                    Text("「\(model.query)」に合う体験は、まだ樹にありません。")
                        .font(.footnote)
                        .foregroundStyle(Palette.ink2)
                        .padding(.horizontal, 6)
                }
                ForEach(sections) { section in
                    ElementSectionPanel(section: section, model: model, open: open)
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

/// 要素ひとつぶんの面: 字・名前・説明と、その要素の体験
private struct ElementSectionPanel: View {
    let section: TreeViewModel.Section
    let model: TreeViewModel
    let open: @MainActor (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                ElementMark(glyph: section.element.glyph, size: 32, color: Palette.ink)
                VStack(alignment: .leading, spacing: 3) {
                    Text(section.element.label)
                        .font(Typeface.mincho(18, bold: true, relativeTo: .headline))
                        .foregroundStyle(Palette.ink)
                    Text(section.element.hint)
                        .font(.caption)
                        .foregroundStyle(Palette.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, 6)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            ForEach(section.nodes) { node in
                Button {
                    open(node.id)
                } label: {
                    NodeRow(
                        node: node,
                        state: model.state(of: node.id),
                        glyph: model.tree.glyph(of: node),
                        depth: model.depth(of: node.id)
                    )
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
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
    }
}
