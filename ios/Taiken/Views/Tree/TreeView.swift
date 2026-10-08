import SwiftUI
import TaikenCore

/// 体験の樹 (3.0)。体験だけでできた、自分の場所。
/// 10の要素の根から体験がつながって伸び、記した体験が朱の印として灯る。その先には芽が出る。
/// 点数・レベル・解放の条件は無い。どの体験も、いつでも始められる。
///
/// - 樹: 指で動かし、つまんで拡大。体験を押すと、下に小さなカードが出る
/// - 一覧: 要素ごとに、根から順に (読み上げのときは、はじめからこちら)
/// - 体験のページ: ひらく先・至る元・結んだ体験・記録。となりの体験へ渡っていける
struct TreeView: View {
    @Bindable var model: TreeViewModel
    let home: HomeViewModel
    let focus: String?

    enum Mode: String, CaseIterable, Identifiable {
        case tree, list
        var id: String { rawValue }
        var label: String {
            switch self {
            case .tree: "樹"
            case .list: "一覧"
            }
        }
    }

    /// ページを閉じきってから行うこと
    enum AfterPage {
        case start(TreeNode)
        case show(String)
    }

    @State private var mode: Mode = .tree
    @State private var scene = TreeScene.empty
    @State private var viewport = TreeViewport()
    @State private var lastTranslation: CGSize?
    @State private var lastMagnification: CGFloat?
    @State private var selected: String?
    @State private var page: NodeRoute?
    @State private var weaving: WeaveRoute?
    @State private var afterPage: AfterPage?
    @State private var confirmingStart: TreeNode?
    @State private var canvasSize: CGSize = .zero
    @State private var prepared = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            let time = TimeOfDay.at(timeline.date, calendar: .current)
            let palette = time.sky(dark: colorScheme == .dark)
            ZStack {
                SkyBackground(time: time)
                VStack(spacing: 0) {
                    header(palette: palette)
                    switch mode {
                    case .tree:
                        canvas(palette: palette)
                            .overlay(alignment: .bottom) { bottomBar(palette: palette) }
                    case .list:
                        TreeList(model: model) { id in page = NodeRoute(id: id) }
                    }
                }
            }
            .environment(\.skyPalette, palette)
        }
        .navigationTitle("体験の樹")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("見かた", selection: $mode) {
                    ForEach(Mode.allCases) { item in
                        Text(item.label).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 132)
                .accessibilityIdentifier("tree.mode")
            }
            ToolbarItem(placement: .topBarTrailing) {
                FloatingIconButton(systemImage: "plus", label: "体験を編む") {
                    weaving = WeaveRoute(growsFrom: weaveParent, elements: weaveElements)
                }
            }
        }
        .onAppear(perform: prepare)
        .onChange(of: model.revision) { rebuildScene() }
        .sheet(item: $page, onDismiss: runAfterPage) { route in
            NodePageSheet(
                model: model,
                route: route,
                start: { node in
                    afterPage = .start(node)
                    page = nil
                },
                showOnTree: { id in
                    afterPage = .show(id)
                    page = nil
                },
                close: { page = nil }
            )
        }
        .sheet(item: $weaving) { route in
            WeaveSheet(model: model, route: route) { id in
                rebuildScene()
                center(on: id, animated: true)
            }
        }
        .confirmationDialog(
            "体験中の体験があります",
            isPresented: Binding(get: { confirmingStart != nil }, set: { if !$0 { confirmingStart = nil } }),
            titleVisibility: .visible,
            presenting: confirmingStart
        ) { node in
            Button("「\(node.title)」を始める") { model.start(node) }
        } message: { node in
            Text("いまの「\(home.activeEntry?.title ?? "")」は記さずに区切って、「\(node.title)」を始めます。")
        }
        .sensoryFeedback(.selection, trigger: selected)
    }

    // MARK: - 見出し

    private func header(palette: SkyPalette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.summary)
                .font(Typeface.mincho(14, relativeTo: .footnote))
                .lineSpacing(3)
                .foregroundStyle(palette.onSkySecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .accessibilityIdentifier("tree.summary")
            ElementStrip(
                elements: model.tree.elements,
                selected: model.highlightedElement,
                touched: Set(model.tree.litNodes.map(\.primaryElement)),
                choose: choose(element:)
            )
        }
        .padding(.top, 2)
        .padding(.bottom, 4)
    }

    // MARK: - 樹

    private func canvas(palette: SkyPalette) -> some View {
        GeometryReader { proxy in
            let size = proxy.size
            TimelineView(.animation(minimumInterval: 1.0 / 15, paused: reduceMotion)) { timeline in
                TreeCanvas(
                    scene: scene,
                    viewport: viewport,
                    palette: palette,
                    selected: selected,
                    highlighted: model.highlightedElement,
                    time: reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                )
            }
            .contentShape(Rectangle())
            .gesture(panAndZoom(size: size))
            .onTapGesture(count: 2) { location in zoom(at: location, size: size) }
            .onTapGesture(count: 1) { location in tap(at: location, size: size) }
            .onAppear {
                canvasSize = size
                prepare()
            }
            .onChange(of: size) { _, newSize in canvasSize = newSize }
        }
        .clipped()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("体験の樹の図")
        .accessibilityValue(model.summary)
        .accessibilityHint("一覧に切り替えると、体験をひとつずつ読み上げます")
        .accessibilityAction(named: "一覧で見る") { mode = .list }
        .accessibilityIdentifier("tree.canvas")
    }

    /// 1本の指で動かし、2本の指で拡大する。指が増えたり減ったりしても跳ねないよう、前回からの差だけを足す
    private func panAndZoom(size: CGSize) -> some Gesture {
        SimultaneousGesture(DragGesture(minimumDistance: 4), MagnifyGesture())
            .onChanged { value in
                var next = viewport
                if let magnify = value.second {
                    if let last = lastMagnification, last > 0 {
                        next = next.zoomed(by: magnify.magnification / last, around: magnify.startLocation, size: size)
                    }
                    lastMagnification = magnify.magnification
                } else {
                    lastMagnification = nil
                }
                if let drag = value.first {
                    // つまんでいるあいだは動かさない (拡大の中心がずれないように)
                    if let last = lastTranslation, value.second == nil {
                        next.pan.width += drag.translation.width - last.width
                        next.pan.height += drag.translation.height - last.height
                    }
                    lastTranslation = drag.translation
                } else {
                    lastTranslation = nil
                }
                viewport = next.clamped(size: size, radius: scene.radius)
            }
            .onEnded { _ in
                lastTranslation = nil
                lastMagnification = nil
            }
    }

    private func tap(at location: CGPoint, size: CGSize) {
        let hit = TreeDrawing.hit(location, scene: scene, viewport: viewport, size: size)
        withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.9)) { selected = hit }
    }

    /// 二度押すと寄る。寄りきっていたら全体に戻る
    private func zoom(at location: CGPoint, size: CGSize) {
        let target: TreeViewport
        if viewport.zoom >= TreeViewport.maximumZoom * 0.9 {
            target = TreeViewport()
        } else {
            target = viewport.zoomed(by: 1.8, around: location, size: size).clamped(size: size, radius: scene.radius)
        }
        withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.86)) { viewport = target }
    }

    // MARK: - 下の帯

    @ViewBuilder
    private func bottomBar(palette: SkyPalette) -> some View {
        Group {
            if let id = selected, let node = model.node(id) {
                NodePeek(
                    node: node,
                    state: model.state(of: id),
                    glyph: model.tree.glyph(of: node),
                    caption: model.caption(of: id),
                    start: { requestStart(node) },
                    open: { page = NodeRoute(id: id) },
                    close: { selected = nil }
                )
                .id(id)
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                HStack(spacing: 10) {
                    if viewport != TreeViewport() {
                        Button {
                            withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.9)) { viewport = TreeViewport() }
                        } label: {
                            SkyCapsuleLabel(title: "全体", systemImage: "arrow.down.right.and.arrow.up.left")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("樹の全体を見る")
                    }
                    Button {
                        weaving = WeaveRoute(growsFrom: nil, elements: weaveElements)
                    } label: {
                        SkyCapsuleLabel(title: "体験を編む", systemImage: "plus")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tree.weave")
                }
                .padding(.bottom, 10)
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.4, dampingFraction: 0.88), value: selected)
    }

    // MARK: - 動き

    private func prepare() {
        if scene.nodes.isEmpty || !prepared { rebuildScene() }
        guard !prepared, canvasSize != .zero || mode == .list else { return }
        prepared = true
        if voiceOver { mode = .list }
        if let focus, model.node(focus) != nil {
            center(on: focus, animated: false)
        }
    }

    private func rebuildScene() {
        scene = TreeScene.make(tree: model.tree, layout: model.layout)
        if let selected, scene.node(selected) == nil { self.selected = nil }
    }

    /// その体験を真ん中に寄せて、選ぶ
    private func center(on id: String, animated: Bool) {
        mode = .tree
        guard let node = scene.node(id), canvasSize != .zero else {
            selected = id
            return
        }
        let base = TreeViewport.base(for: canvasSize, radius: scene.radius)
        let target = TreeViewport().centered(on: node.point, base: base, zoom: max(viewport.zoom, 1.9))
        withAnimation(animated && !reduceMotion ? .spring(response: 0.6, dampingFraction: 0.88) : nil) {
            viewport = target
            selected = id
        }
    }

    /// 要素を選ぶと、その要素の体験が集まるあたりへ寄る。もう一度押すと全体に戻る
    private func choose(element id: String?) {
        let next = model.highlightedElement == id ? nil : id
        model.highlightedElement = next
        guard mode == .tree, canvasSize != .zero else { return }
        var target = TreeViewport()
        if let next, let point = scene.centroid(ofElement: next) {
            let base = TreeViewport.base(for: canvasSize, radius: scene.radius)
            target = TreeViewport().centered(on: point, base: base, zoom: 1.7).clamped(size: canvasSize, radius: scene.radius)
        }
        withAnimation(reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.88)) { viewport = target }
    }

    /// 体験中の体験があれば、区切ってよいかを聞いてから始める
    private func requestStart(_ node: TreeNode) {
        if let active = home.activeEntry, active.nodeID != node.id {
            confirmingStart = node
        } else {
            model.start(node)
        }
    }

    private func runAfterPage() {
        guard let action = afterPage else { return }
        afterPage = nil
        switch action {
        case .start(let node):
            requestStart(node)
        case .show(let id):
            rebuildScene()
            center(on: id, animated: true)
        }
    }

    /// 選んでいる体験が灯っていれば、そこから伸ばす
    private var weaveParent: String? {
        guard let selected, model.state(of: selected) == .lit else { return nil }
        return selected
    }

    private var weaveElements: [String] {
        if let selected, let node = model.node(selected) { return [node.primaryElement] }
        return model.highlightedElement.map { [$0] } ?? []
    }
}

// MARK: - 要素の帯

/// 10の要素を横に並べる。押すと、その要素だけを濃く見る (数は出さない。灯りのある要素に小さな朱の点)
struct ElementStrip: View {
    let elements: [ExperienceElement]
    let selected: String?
    let touched: Set<String>
    let choose: @MainActor (String?) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                Button {
                    choose(nil)
                } label: {
                    Text("すべて")
                }
                .buttonStyle(ChipButtonStyle(selected: selected == nil))
                .accessibilityAddTraits(selected == nil ? .isSelected : [])
                ForEach(elements) { element in
                    Button {
                        choose(element.id)
                    } label: {
                        HStack(spacing: 6) {
                            Text(element.glyph)
                                .font(Typeface.fixedMincho(14))
                            Text(element.label)
                            if touched.contains(element.id) {
                                Circle()
                                    .fill(Palette.shu)
                                    .frame(width: 5, height: 5)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .buttonStyle(ChipButtonStyle(selected: selected == element.id))
                    .accessibilityLabel(element.label)
                    .accessibilityValue(touched.contains(element.id) ? "灯りがあります" : "")
                    .accessibilityHint(element.hint)
                    .accessibilityAddTraits(selected == element.id ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }
}

// MARK: - 選んだ体験の小さなカード

struct NodePeek: View {
    let node: TreeNode
    let state: NodeState
    let glyph: String
    let caption: String
    let start: @MainActor () -> Void
    let open: @MainActor () -> Void
    let close: @MainActor () -> Void

    var body: some View {
        PaperCard(emphasized: state == .active) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    if node.kind == .root && state != .lit && state != .active {
                        ElementMark(glyph: glyph, size: 30, color: Palette.ink)
                    } else {
                        NodeStateMark(state: state, glyph: glyph, size: 30)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(node.title)
                            .font(.experienceTitle)
                            .foregroundStyle(Palette.ink)
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(state == .lit || state == .active ? Palette.shu : Palette.ink3)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Button(action: close) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.ink2)
                            .frame(width: 30, height: 30)
                            .background(Palette.wash, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("閉じる")
                }
                Text(node.invitation)
                    .font(Typeface.mincho(15))
                    .lineSpacing(4)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    if state != .active {
                        Button("やってみる", action: start)
                            .buttonStyle(ShuButtonStyle(compact: true))
                            .accessibilityIdentifier("tree.peek.start")
                    }
                    Button("ひらく", action: open)
                        .buttonStyle(QuietButtonStyle(compact: true))
                        .accessibilityIdentifier("tree.peek.open")
                }
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// 空の上に浮かぶ、文字のある丸い札 (体験を編む・全体)
struct SkyCapsuleLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.callout)
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule())
            .background(Palette.panel, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 1))
            .shadow(color: Palette.shadow.opacity(0.4), radius: 14, x: 0, y: 8)
    }
}

#Preview {
    NavigationStack {
        let deps = AppDependencies.preview()
        TreeView(model: deps.tree, home: deps.home, focus: "meal-first-bite")
    }
}
