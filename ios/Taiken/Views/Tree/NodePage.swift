import SwiftUI
import TaikenCore

/// 体験のページへの道しるべ
struct NodeRoute: Identifiable, Hashable {
    let id: String
}

/// 体験のページをシートで開く。中で、となりの体験へ渡っていける (ノートからノートへ渡るように)
struct NodePageSheet: View {
    let model: TreeViewModel
    let route: NodeRoute
    let start: @MainActor (TreeNode) -> Void
    let showOnTree: @MainActor (String) -> Void
    let close: @MainActor () -> Void

    var body: some View {
        NavigationStack {
            NodePage(model: model, id: route.id, start: start, showOnTree: showOnTree, close: close)
                .navigationDestination(for: NodeRoute.self) { next in
                    NodePage(model: model, id: next.id, start: start, showOnTree: showOnTree, close: close)
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.paper)
    }
}

/// 体験の1ページ: 誘いかけ・根からの道すじ・ひらく先・至る元・結んだ体験・記録
struct NodePage: View {
    let model: TreeViewModel
    let id: String
    let start: @MainActor (TreeNode) -> Void
    let showOnTree: @MainActor (String) -> Void
    let close: @MainActor () -> Void

    @State private var weaving: WeaveRoute?
    @State private var tying = false
    @State private var confirmsRemoval = false

    var body: some View {
        Group {
            if let node = model.node(id) {
                page(node)
            } else {
                ContentUnavailableView(
                    "この体験は、樹から外れました",
                    systemImage: "leaf",
                    description: Text("体験帳の記録は残っています。")
                )
            }
        }
        .background(Palette.paper.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("閉じる", action: close)
                    .tint(Palette.ink)
            }
        }
        .sheet(item: $weaving) { route in
            WeaveSheet(model: model, route: route)
        }
        .sheet(isPresented: $tying) {
            TieSheet(model: model, nodeID: id)
        }
    }

    // MARK: - ページ

    private func page(_ node: TreeNode) -> some View {
        let state = model.state(of: node.id)
        let glyph = model.tree.glyph(of: node)
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header(node, state: state, glyph: glyph)
                lineage(node)

                Text(node.invitation)
                    .font(.invitation)
                    .lineSpacing(7)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if !node.perspective.isEmpty {
                    Text(node.perspective)
                        .font(.footnote)
                        .lineSpacing(4)
                        .foregroundStyle(Palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let question = node.reflectionQuestion, !question.isEmpty {
                    LinedBox {
                        VStack(alignment: .leading, spacing: 6) {
                            MiniHead("終わったあとの問い")
                            Text(question)
                                .font(.question)
                                .foregroundStyle(Palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                actions(node, state: state)

                relations("ここからひらく", model.opens(from: node.id))
                relations("ここへ至る", model.leadsHere(to: node.id))
                ties(node)
                records(node, glyph: glyph)
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .navigationTitle(node.title)
        .confirmationDialog("「\(node.title)」を樹から手放しますか？", isPresented: $confirmsRemoval, titleVisibility: .visible) {
            Button("手放す", role: .destructive) {
                model.remove(node.id)
                close()
            }
        } message: {
            Text("結んだ糸もほどけます。体験帳の記録は残ります。")
        }
    }

    private func header(_ node: TreeNode, state: NodeState, glyph: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    ForEach(node.elements, id: \.self) { elementID in
                        if let element = model.tree.element(elementID) {
                            HStack(spacing: 5) {
                                ElementMark(glyph: element.glyph, size: 18)
                                Text(element.label)
                                    .font(.caption)
                                    .foregroundStyle(Palette.ink2)
                            }
                        }
                    }
                    if node.kind == .woven {
                        KindTag(text: "編んだ")
                    } else if node.kind == .found {
                        KindTag(text: "見つけた")
                    }
                }
                .accessibilityElement(children: .combine)
                Text(node.title)
                    .font(.displayTitle)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(model.caption(of: node.id))
                    .font(.footnote)
                    .foregroundStyle(state == .lit || state == .active ? Palette.shu : Palette.ink3)
            }
            Spacer(minLength: 8)
            if state == .lit || state == .active {
                SealView(character: glyph, size: 64, style: .filled, rotation: -6)
            } else if node.kind == .root {
                ElementMark(glyph: glyph, size: 56, color: Palette.ink)
            } else {
                SealView(character: glyph, size: 56, style: .ghost, rotation: 0)
            }
        }
    }

    /// 要素の根から、この体験までの道すじ
    @ViewBuilder
    private func lineage(_ node: TreeNode) -> some View {
        let path = Array(model.path(to: node.id).dropLast())
        if !path.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(path) { step in
                        NavigationLink(value: NodeRoute(id: step.id)) {
                            Text(step.title)
                                .font(.caption)
                                .foregroundStyle(Palette.ink2)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Palette.wash, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        Image(systemName: "chevron.compact.right")
                            .font(.caption2)
                            .foregroundStyle(Palette.ink3)
                            .accessibilityHidden(true)
                    }
                    Text(node.title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                }
            }
            .scrollIndicators(.hidden)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("根からの道すじ")
        }
    }

    // MARK: - すること

    private func actions(_ node: TreeNode, state: NodeState) -> some View {
        VStack(spacing: 10) {
            if state == .active {
                Label("いま体験中です。終えたら、ホームから記せます。", systemImage: "seal")
                    .font(.footnote)
                    .foregroundStyle(Palette.shu)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Button(state == .lit ? "もう一度やってみる" : "これをやってみる") { start(node) }
                    .buttonStyle(ShuButtonStyle())
                    .accessibilityIdentifier("node.start")
            }
            HStack(spacing: 10) {
                Button {
                    weaving = WeaveRoute(growsFrom: node.id, elements: [node.primaryElement])
                } label: {
                    Label("ここから伸ばす", systemImage: "arrow.up.right")
                }
                .buttonStyle(QuietButtonStyle(compact: true))
                if state == .lit || state == .active {
                    Button {
                        tying = true
                    } label: {
                        Label("結ぶ", systemImage: "link")
                    }
                    .buttonStyle(QuietButtonStyle(compact: true))
                    .accessibilityIdentifier("node.tie")
                }
            }
            HStack(spacing: 18) {
                Button {
                    showOnTree(node.id)
                } label: {
                    Label("樹の上で見る", systemImage: "scope")
                }
                if node.kind == .woven {
                    Button("書き直す") {
                        weaving = WeaveRoute(revising: node.id)
                    }
                }
                if node.isPersonal {
                    Button("手放す") { confirmsRemoval = true }
                }
                Spacer(minLength: 0)
            }
            .font(.footnote)
            .foregroundStyle(Palette.ink2)
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
    }

    // MARK: - となりの体験

    @ViewBuilder
    private func relations(_ title: String, _ items: [TreeViewModel.Relation]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                MiniHead(title)
                    .padding(.bottom, 4)
                ForEach(items) { item in
                    NavigationLink(value: NodeRoute(id: item.node.id)) {
                        NodeRow(
                            node: item.node,
                            state: model.state(of: item.node.id),
                            glyph: model.tree.glyph(of: item.node),
                            detail: item.kind.label
                        )
                    }
                    .buttonStyle(.plain)
                    Rectangle().fill(Palette.line).frame(height: 1)
                }
            }
        }
    }

    @ViewBuilder
    private func ties(_ node: TreeNode) -> some View {
        let items = model.tied(to: node.id)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                MiniHead("結んだ体験")
                    .padding(.bottom, 4)
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 0) {
                        NavigationLink(value: NodeRoute(id: item.node.id)) {
                            NodeRow(
                                node: item.node,
                                state: model.state(of: item.node.id),
                                glyph: model.tree.glyph(of: item.node),
                                detail: "結び"
                            )
                        }
                        .buttonStyle(.plain)
                        if let note = item.note {
                            HStack(spacing: 8) {
                                Rectangle().fill(Palette.shu).frame(width: 14, height: 1.5)
                                Text(note)
                                    .font(Typeface.mincho(14))
                                    .foregroundStyle(Palette.ink)
                            }
                            .padding(.bottom, 10)
                        }
                    }
                    .contextMenu {
                        Button("糸をほどく", systemImage: "scissors", role: .destructive) { model.untie(item.link) }
                    }
                    .accessibilityAction(named: "糸をほどく") { model.untie(item.link) }
                    Rectangle().fill(Palette.line).frame(height: 1)
                }
                Text("長押しで、糸をほどけます。")
                    .font(.caption2)
                    .foregroundStyle(Palette.ink3)
                    .padding(.top, 6)
            }
        }
    }

    @ViewBuilder
    private func records(_ node: TreeNode, glyph: String) -> some View {
        if let life = model.tree.lives[node.id], !life.entries.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                MiniHead("記録")
                ForEach(life.entries) { entry in
                    HStack(alignment: .top, spacing: 12) {
                        SealView(
                            character: glyph, size: 26, style: entry.status == .completed ? .outlined : .ghost,
                            rotation: Double(Calendar.current.component(.day, from: entry.createdAt) % 5) - 3
                        )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.createdAt.formatted(.dateTime.year().month().day().weekday(.abbreviated)))
                                .font(.caption)
                                .foregroundStyle(Palette.ink3)
                            if entry.status == .active {
                                Text("体験中")
                                    .font(.footnote)
                                    .foregroundStyle(Palette.shu)
                            } else if let rating = entry.rating {
                                Label(rating.label, systemImage: rating.symbolName)
                                    .font(.footnote)
                                    .foregroundStyle(Palette.ink2)
                            }
                            if let note = entry.note {
                                Text("「\(note)」")
                                    .font(Typeface.mincho(15))
                                    .foregroundStyle(Palette.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

// MARK: - 行

/// 一覧・つながりの1行: 様子の印・名前・誘いかけの書き出し
struct NodeRow: View {
    let node: TreeNode
    let state: NodeState
    let glyph: String
    var depth: Int = 0
    /// 右に添える言葉 (つながりの種類など)。無ければ様子
    var detail: String?

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if node.kind == .root && state != .lit && state != .active {
                ElementMark(glyph: glyph, size: 24, color: Palette.ink)
            } else {
                NodeStateMark(state: state, glyph: glyph, size: 24)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(node.title)
                        .font(.experienceTitle)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(1)
                    if node.kind == .woven {
                        KindTag(text: "編んだ")
                    }
                }
                Text(node.invitation)
                    .font(.caption)
                    .foregroundStyle(Palette.ink2)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let text = detail ?? (state.label.isEmpty ? nil : state.label) {
                Text(text)
                    .font(.caption2)
                    .foregroundStyle(state == .lit || state == .active ? Palette.shu : Palette.ink3)
            }
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Palette.ink3)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .padding(.leading, CGFloat(min(depth, 3)) * 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("体験のページをひらきます")
    }
}

/// 「編んだ」「見つけた」の小さな札
struct KindTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(Palette.ink2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 1))
    }
}
