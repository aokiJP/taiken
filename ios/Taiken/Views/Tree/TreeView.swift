import SwiftUI
import TaikenCore

/// 技の樹 (4.0)。自分で記した体験から段が上がり、芽を使って技を伸ばす場所。
/// 10の要素の根から技が伸びる。名前が見えるのは身についた技の隣だけで、その先は霧。
///
/// - 樹: 指で動かし、つまんで拡大。技を押すと、下に小さなカード (伸ばす / ひらく)
/// - 一覧: 要素ごとに、浅い技から (読み上げのときは、はじめからこちら)
/// - 技のページ: できるようになること・届く条件・守破離・稽古・ともにあった体験
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
        case start(Experience)
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
    @State private var confirmingStart: Experience?
    @State private var confirmingLearn: TreeNode?
    /// いま身についた技 (印が押されるところを見せる)
    @State private var justLearned: TreeNode?
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
                .overlay(alignment: .top) { banners }
            }
            .environment(\.skyPalette, palette)
        }
        .navigationTitle("技の樹")
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
                FloatingIconButton(systemImage: "plus", label: "技を編む") {
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
                start: { experience in
                    afterPage = .start(experience)
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
        ) { experience in
            Button("「\(experience.title)」を始める") { home.begin(experience) }
        } message: { experience in
            Text("いまの「\(home.activeEntry?.title ?? "")」は記さずに区切って、「\(experience.title)」を始めます。")
        }
        .confirmationDialog(
            confirmingLearn.map { "「\($0.title)」へ伸ばしますか？" } ?? "",
            isPresented: Binding(get: { confirmingLearn != nil }, set: { if !$0 { confirmingLearn = nil } }),
            titleVisibility: .visible,
            presenting: confirmingLearn
        ) { node in
            Button(learnButtonTitle(for: node)) { learn(node) }
        } message: { node in
            Text(node.ability)
        }
        .sensoryFeedback(.selection, trigger: selected)
        .sensoryFeedback(.impact(weight: .heavy, intensity: 0.9), trigger: justLearned?.id)
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
                ranks: Dictionary(uniqueKeysWithValues: model.tree.elements.map { ($0.id, model.tree.progress(of: $0.id).rank) }),
                sprouting: Set(model.tree.sproutingElements.map(\.id)),
                choose: choose(element:)
            )
        }
        .padding(.top, 2)
        .padding(.bottom, 4)
    }

    // MARK: - 知らせ (身についた・閃いた)

    @ViewBuilder
    private var banners: some View {
        VStack(spacing: 8) {
            if let node = justLearned {
                TreeMomentBanner(
                    glyph: model.tree.glyph(of: node), title: "「\(node.title)」が身につきました",
                    detail: node.ability, flash: false
                ) {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { justLearned = nil }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            ForEach(model.freshFlashes) { node in
                TreeMomentBanner(
                    glyph: "閃", title: "閃き — 「\(node.title)」", detail: node.found ?? node.ability, flash: true
                ) {
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { model.dismissFlashes() }
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.85), value: justLearned?.id)
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.85), value: model.freshFlashes.map(\.id))
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
        .accessibilityLabel("技の樹の図")
        .accessibilityValue(model.summary)
        .accessibilityHint("一覧に切り替えると、技をひとつずつ読み上げます")
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
                    title: model.displayTitle(of: node),
                    state: model.state(of: id),
                    glyph: model.tree.glyph(of: node),
                    mastery: model.tree.mastery(of: id),
                    check: model.tree.check(id),
                    caption: model.caption(of: id),
                    learn: { confirmingLearn = node },
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
                    if let element = model.tree.sproutingElements.first {
                        Button {
                            choose(element: element.id)
                        } label: {
                            SkyCapsuleLabel(title: "芽を見る", systemImage: "leaf")
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("芽が出ている要素へ寄ります")
                        .accessibilityIdentifier("tree.sprouts")
                    }
                    Button {
                        weaving = WeaveRoute(growsFrom: nil, elements: weaveElements)
                    } label: {
                        SkyCapsuleLabel(title: "技を編む", systemImage: "plus")
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

    /// その節を真ん中に寄せて、選ぶ
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

    /// 要素を選ぶと、その要素の技が集まるあたりへ寄る。もう一度押すと全体に戻る
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

    /// 芽を使って伸ばす。身についたら、印が押されるところを見せる
    private func learn(_ node: TreeNode) {
        guard model.learn(node.id) else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.8)) {
            justLearned = model.node(node.id)
        }
        rebuildScene()
        home.treeDidChange()
    }

    private func learnButtonTitle(for node: TreeNode) -> String {
        if case .available(let charge) = model.tree.check(node.id), let element = model.tree.element(charge) {
            return "\(element.label)の芽を使って伸ばす"
        }
        return "伸ばす"
    }

    /// 体験中の体験があれば、区切ってよいかを聞いてから始める
    private func requestStart(_ experience: Experience) {
        if let active = home.activeEntry, active.nodeID != experience.nodeID || active.title != experience.title {
            confirmingStart = experience
        } else {
            home.begin(experience)
        }
    }

    private func runAfterPage() {
        guard let action = afterPage else { return }
        afterPage = nil
        switch action {
        case .start(let experience):
            requestStart(experience)
        case .show(let id):
            rebuildScene()
            center(on: id, animated: true)
        }
    }

    /// 選んでいる技が身についていれば、そこから編む
    private var weaveParent: String? {
        guard let selected, let node = model.node(selected), node.isGrowable, model.state(of: selected) == .learned else { return nil }
        return selected
    }

    private var weaveElements: [String] {
        if let selected, let node = model.node(selected) { return [node.primaryElement] }
        return model.highlightedElement.map { [$0] } ?? []
    }
}

// MARK: - 要素の帯

/// 10の要素を横に並べる。字・名前・段。芽が出ている要素には朱の点。押すと、その要素だけを濃く見る
struct ElementStrip: View {
    let elements: [ExperienceElement]
    let selected: String?
    let ranks: [String: Int]
    let sprouting: Set<String>
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
                    let rank = ranks[element.id] ?? 0
                    Button {
                        choose(element.id)
                    } label: {
                        HStack(spacing: 6) {
                            Text(element.glyph)
                                .font(Typeface.fixedMincho(14))
                            Text(element.label)
                            if rank > 0 {
                                Text(Ranks.kanji(rank))
                                    .font(Typeface.fixedMincho(12, bold: false))
                                    .opacity(0.75)
                            }
                            if sprouting.contains(element.id) {
                                Circle()
                                    .fill(Palette.shu)
                                    .frame(width: 5, height: 5)
                                    .accessibilityHidden(true)
                            }
                        }
                    }
                    .buttonStyle(ChipButtonStyle(selected: selected == element.id))
                    .accessibilityLabel(element.label)
                    .accessibilityValue(accessibilityValue(rank: rank, sprouting: sprouting.contains(element.id)))
                    .accessibilityHint(element.hint)
                    .accessibilityAddTraits(selected == element.id ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func accessibilityValue(rank: Int, sprouting: Bool) -> String {
        var parts: [String] = []
        if rank > 0 { parts.append(Ranks.label(rank)) }
        if sprouting { parts.append("芽が出ています") }
        return parts.joined(separator: "、")
    }
}

// MARK: - 選んだ節の小さなカード

struct NodePeek: View {
    let node: TreeNode
    let title: String
    let state: NodeState
    let glyph: String
    let mastery: Mastery?
    let check: LearnCheck
    let caption: String
    let learn: @MainActor () -> Void
    let open: @MainActor () -> Void
    let close: @MainActor () -> Void

    private var canLearn: Bool {
        if case .available = check { return true }
        return false
    }

    var body: some View {
        PaperCard(emphasized: canLearn) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    NodeStateMark(state: state, kind: node.kind, glyph: glyph, mastery: mastery, growable: canLearn, size: 30)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(title)
                                .font(.experienceTitle)
                                .foregroundStyle(state == .unknown ? Palette.ink3 : Palette.ink)
                            if let kind = node.kindLabel, state != .unknown {
                                KindTag(text: kind)
                            }
                        }
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(state == .learned || canLearn ? Palette.shu : Palette.ink3)
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
                if state != .unknown {
                    Text(node.ability)
                        .font(Typeface.mincho(15))
                        .lineSpacing(4)
                        .foregroundStyle(Palette.ink)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    if canLearn {
                        Button("伸ばす", action: learn)
                            .buttonStyle(ShuButtonStyle(compact: true))
                            .accessibilityIdentifier("tree.peek.learn")
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

/// 身についた・閃いたことを、樹の上にひとこと知らせる
struct TreeMomentBanner: View {
    let glyph: String
    let title: String
    let detail: String
    let flash: Bool
    let dismiss: @MainActor () -> Void
    @State private var stamped = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SealView(character: glyph, size: 34, style: .filled, rotation: flash ? 45 : (stamped ? -6 : -16))
                .scaleEffect(stamped || reduceMotion ? 1 : 1.8)
                .opacity(stamped || reduceMotion ? 1 : 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.experienceTitle)
                    .foregroundStyle(Palette.ink)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Palette.ink2)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.ink2)
                    .frame(width: 28, height: 28)
                    .background(Palette.wash, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("閉じる")
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .background(Palette.panel, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.shu.opacity(0.5), lineWidth: 1))
        .shadow(color: Palette.shadow.opacity(0.4), radius: 14, x: 0, y: 8)
        .onAppear {
            withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.55)) { stamped = true }
        }
        .accessibilityElement(children: .combine)
    }
}

/// 空の上に浮かぶ、文字のある丸い札 (技を編む・全体・芽を見る)
struct SkyCapsuleLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.callout)
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 18)
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
        TreeView(model: deps.tree, home: deps.home, focus: "see-tomeru")
    }
}
