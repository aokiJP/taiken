import SwiftUI
import TaikenCore

/// 体験の樹を空の上に描く。
/// - 根: 要素の字の入った丸 (内側の輪)
/// - 灯った体験: 朱の印 (重ねるほど少し大きく)
/// - 芽: 呼吸する藍墨の丸
/// - まだ遠い体験: 小さな点
/// - 自分で結んだ糸: 朱の線
struct TreeCanvas: View, Animatable {
    let scene: TreeScene
    var viewport: TreeViewport
    let palette: SkyPalette
    let selected: String?
    let highlighted: String?
    /// 芽の呼吸 (視差効果を減らす設定では止める)
    let time: Double
    /// 体験の名前を添えるか (案内の挿絵では添えない)
    var labels = true

    /// 拡大・移動を、指を離したあとや要素を選んだときに、なめらかに動かす
    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(viewport.zoom, AnimatablePair(viewport.pan.width, viewport.pan.height)) }
        set {
            viewport.zoom = newValue.first
            viewport.pan = CGSize(width: newValue.second.first, height: newValue.second.second)
        }
    }

    var body: some View {
        Canvas { context, size in
            TreeDrawing(
                scene: scene, viewport: viewport, palette: palette, selected: selected, highlighted: highlighted, time: time,
                labels: labels
            ).draw(in: &context, size: size)
        }
    }
}

/// 描画の手順 (型推論を軽くするため、式は小さく分ける)
struct TreeDrawing {
    let scene: TreeScene
    let viewport: TreeViewport
    let palette: SkyPalette
    let selected: String?
    let highlighted: String?
    let time: Double
    var labels = true

    private var ink: Color { palette.onSky }

    func draw(in context: inout GraphicsContext, size: CGSize) {
        let base = TreeViewport.base(for: size, radius: scene.radius)
        drawRings(in: &context, size: size, base: base)
        drawEdges(in: &context, size: size, base: base)
        let points = drawNodes(in: &context, size: size, base: base)
        if labels { drawLabels(in: &context, size: size, points: points) }
    }

    // MARK: - 輪

    private func drawRings(in context: inout GraphicsContext, size: CGSize, base: CGFloat) {
        let center = viewport.screen(.zero, size: size, base: base)
        for (i, radius) in scene.rings.enumerated() {
            let r: CGFloat = CGFloat(radius) * base * viewport.zoom
            let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            let opacity: Double = i == 0 ? 0.12 : 0.06
            context.stroke(
                Path(ellipseIn: rect), with: .color(ink.opacity(opacity)),
                style: StrokeStyle(lineWidth: 0.6, dash: i == 0 ? [] : [2, 5])
            )
        }
    }

    // MARK: - つながり

    private func dims(_ element: String) -> Bool {
        guard let highlighted else { return false }
        return element != highlighted
    }

    private func drawEdges(in context: inout GraphicsContext, size: CGSize, base: CGFloat) {
        for edge in scene.edges {
            let touchesSelection = selected != nil && (edge.fromID == selected || edge.toID == selected)
            let inHighlight = highlighted != nil && (edge.fromElement == highlighted || edge.toElement == highlighted)
            // 別の要素へ渡る静かなつながりは、選んだとき・その要素を見ているときだけ
            if edge.style == .quiet && edge.isCross && !touchesSelection && !inHighlight { continue }
            let a = viewport.screen(edge.from, size: size, base: base)
            let b = viewport.screen(edge.to, size: size, base: base)
            let center = viewport.screen(.zero, size: size, base: base)
            let path = edge.style == .tie ? tiePath(a, b, center: center) : branchPath(a, b, center: center)
            var opacity: Double
            let width: CGFloat
            var dash: [CGFloat] = []
            var color = ink
            switch edge.style {
            case .quiet:
                opacity = edge.isCross ? 0.16 : 0.13
                width = 0.8
            case .toBud:
                opacity = 0.42
                width = 1
                dash = [2, 3]
            case .lit:
                opacity = 0.62
                width = 1.4
            case .tie:
                color = Palette.shu
                opacity = 0.85
                width = 1.4
            }
            if touchesSelection { opacity = max(opacity, 0.7) }
            if highlighted != nil && !inHighlight && !touchesSelection { opacity *= 0.25 }
            context.stroke(path, with: .color(color.opacity(opacity)), style: StrokeStyle(lineWidth: width, lineCap: .round, dash: dash))
        }
    }

    /// 根から外へ伸びる枝: 親の向きに出て、子の向きで入る
    private func branchPath(_ a: CGPoint, _ b: CGPoint, center: CGPoint) -> Path {
        let ra: CGFloat = hypot(a.x - center.x, a.y - center.y)
        let rb: CGFloat = hypot(b.x - center.x, b.y - center.y)
        let angleA: CGFloat = atan2(a.y - center.y, a.x - center.x)
        let angleB: CGFloat = atan2(b.y - center.y, b.x - center.x)
        let mid: CGFloat = (ra + rb) / 2
        let c1 = CGPoint(x: center.x + cos(angleA) * mid, y: center.y + sin(angleA) * mid)
        let c2 = CGPoint(x: center.x + cos(angleB) * mid, y: center.y + sin(angleB) * mid)
        var path = Path()
        path.move(to: a)
        if abs(ra - rb) < 4 {
            path.addLine(to: b)
        } else {
            path.addCurve(to: b, control1: c1, control2: c2)
        }
        return path
    }

    /// 結びの糸: 外側へ少しふくらんだ弧
    private func tiePath(_ a: CGPoint, _ b: CGPoint, center: CGPoint) -> Path {
        let mx: CGFloat = (a.x + b.x) / 2
        let my: CGFloat = (a.y + b.y) / 2
        let dx: CGFloat = mx - center.x
        let dy: CGFloat = my - center.y
        let length: CGFloat = max(1, hypot(dx, dy))
        let bulge: CGFloat = hypot(b.x - a.x, b.y - a.y) * 0.22
        let control = CGPoint(x: mx + dx / length * bulge, y: my + dy / length * bulge)
        var path = Path()
        path.move(to: a)
        path.addQuadCurve(to: b, control: control)
        return path
    }

    // MARK: - 体験

    /// 描いた体験の、画面上の位置と大きさ (ラベルの置き場所に使う)
    struct Placed {
        let node: TreeScene.Node
        let point: CGPoint
        let radius: CGFloat
    }

    private func drawNodes(in context: inout GraphicsContext, size: CGSize, base: CGFloat) -> [Placed] {
        var placed: [Placed] = []
        let scale: CGFloat = min(1.5, max(0.85, sqrt(viewport.zoom)))
        let ordered = scene.nodes.sorted { rank($0) < rank($1) }
        for node in ordered {
            let p = viewport.screen(node.point, size: size, base: base)
            guard p.x > -40, p.y > -40, p.x < size.width + 40, p.y < size.height + 40 else { continue }
            var layer = context
            if dims(node.element) && node.id != selected { layer.opacity = 0.25 }
            let radius = drawNode(node, at: p, scale: scale, in: &layer)
            if node.id == selected {
                let r = radius + 6
                context.stroke(
                    Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
                    with: .color(ink.opacity(0.9)), lineWidth: 1.2
                )
            }
            placed.append(Placed(node: node, point: p, radius: radius))
        }
        return placed
    }

    private func rank(_ node: TreeScene.Node) -> Int {
        switch node.state {
        case .quiet: 0
        case .bud: 1
        case .lit: 2
        case .active: 3
        }
    }

    private func drawNode(_ node: TreeScene.Node, at p: CGPoint, scale: CGFloat, in context: inout GraphicsContext) -> CGFloat {
        if node.kind == .root && node.state != .lit && node.state != .active {
            return drawRoot(node, at: p, scale: scale, in: &context)
        }
        switch node.state {
        case .lit, .active:
            return drawSeal(node, at: p, scale: scale, in: &context)
        case .bud:
            return drawBud(node, at: p, scale: scale, in: &context)
        case .quiet:
            return drawQuiet(node, at: p, scale: scale, in: &context)
        }
    }

    private func drawRoot(_ node: TreeScene.Node, at p: CGPoint, scale: CGFloat, in context: inout GraphicsContext) -> CGFloat {
        let r: CGFloat = 12 * scale
        let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
        context.fill(Path(ellipseIn: rect), with: .color(ink.opacity(palette.isDark ? 0.10 : 0.07)))
        let budGlow: Double = node.state == .bud ? 0.55 + 0.25 * sin(time * 1.6 + node.angle) : 0.45
        context.stroke(Path(ellipseIn: rect), with: .color(ink.opacity(budGlow)), lineWidth: 1)
        var glyph = context.resolve(Text(node.glyph).font(Typeface.fixedMincho(12 * scale)))
        glyph.shading = .color(ink)
        context.draw(glyph, at: p)
        return r
    }

    private func drawSeal(_ node: TreeScene.Node, at p: CGPoint, scale: CGFloat, in context: inout GraphicsContext) -> CGFloat {
        let stack: CGFloat = CGFloat(min(max(node.litCount - 1, 0), 3))
        let side: CGFloat = (11 + stack * 2.2) * scale
        let rect = CGRect(x: p.x - side / 2, y: p.y - side / 2, width: side, height: side)
        let shape = Path(roundedRect: rect, cornerRadius: side * 0.2)
        if node.state == .active {
            let pulse: CGFloat = side * (0.9 + 0.25 * CGFloat(sin(time * 2)))
            let ring = CGRect(x: p.x - pulse, y: p.y - pulse, width: pulse * 2, height: pulse * 2)
            context.stroke(Path(ellipseIn: ring), with: .color(Palette.shu.opacity(0.45)), lineWidth: 1.2)
        }
        // 重ねた印: うしろに少しずらした印をもう一枚
        if stack > 0 {
            let back = Path(roundedRect: rect.offsetBy(dx: 2 * scale, dy: -2 * scale), cornerRadius: side * 0.2)
            context.fill(back, with: .color(Palette.shu.opacity(0.35)))
        }
        context.fill(shape, with: .color(Palette.shu))
        if side >= 13 {
            var glyph = context.resolve(Text(node.glyph).font(Typeface.fixedMincho(side * 0.6)))
            glyph.shading = .color(Palette.onShu)
            context.draw(glyph, at: p)
        }
        return side / 2
    }

    private func drawBud(_ node: TreeScene.Node, at p: CGPoint, scale: CGFloat, in context: inout GraphicsContext) -> CGFloat {
        let r: CGFloat = 4.6 * scale
        let rect = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
        context.stroke(Path(ellipseIn: rect), with: .color(ink.opacity(0.9)), lineWidth: 1.2)
        let breath: CGFloat = 0.45 + 0.35 * CGFloat(sin(time * 1.8 + node.angle * 3))
        let inner: CGFloat = r * 0.45 * (0.7 + breath * 0.5)
        context.fill(
            Path(ellipseIn: CGRect(x: p.x - inner, y: p.y - inner, width: inner * 2, height: inner * 2)),
            with: .color(ink.opacity(Double(breath)))
        )
        return r
    }

    private func drawQuiet(_ node: TreeScene.Node, at p: CGPoint, scale: CGFloat, in context: inout GraphicsContext) -> CGFloat {
        if node.kind == .woven || node.kind == .found {
            // 自分の樹にある体験は、小さな菱形
            let r: CGFloat = 3.6 * scale
            var path = Path()
            path.move(to: CGPoint(x: p.x, y: p.y - r))
            path.addLine(to: CGPoint(x: p.x + r, y: p.y))
            path.addLine(to: CGPoint(x: p.x, y: p.y + r))
            path.addLine(to: CGPoint(x: p.x - r, y: p.y))
            path.closeSubpath()
            context.stroke(path, with: .color(ink.opacity(0.8)), lineWidth: 1)
            return r
        }
        let r: CGFloat = 2.1 * scale
        context.fill(
            Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)),
            with: .color(ink.opacity(0.36))
        )
        return r
    }

    // MARK: - 名前

    private func labelPriority(_ node: TreeScene.Node) -> Int? {
        if node.id == selected { return 0 }
        if node.kind == .root { return nil }
        switch node.state {
        case .active: return 1
        case .bud: return 2
        case .lit: return 3
        case .quiet:
            if node.kind == .woven { return 4 }
            return viewport.zoom >= 1.9 ? 5 : nil
        }
    }

    private func drawLabels(in context: inout GraphicsContext, size: CGSize, points: [Placed]) {
        let candidates = points.compactMap { item -> (Placed, Int)? in
            guard let priority = labelPriority(item.node) else { return nil }
            if dims(item.node.element) && item.node.id != selected { return nil }
            return (item, priority)
        }.sorted { lhs, rhs in
            lhs.1 == rhs.1 ? (lhs.0.node.lastLived ?? .distantPast) > (rhs.0.node.lastLived ?? .distantPast) : lhs.1 < rhs.1
        }
        var taken: [CGRect] = points.filter { $0.node.kind == .root }.map {
            CGRect(x: $0.point.x - $0.radius, y: $0.point.y - $0.radius, width: $0.radius * 2, height: $0.radius * 2)
        }
        let fontSize: CGFloat = viewport.zoom >= 1.6 ? 11.5 : 10.5
        for (item, priority) in candidates {
            var text = context.resolve(Text(item.node.title).font(Typeface.fixedMincho(fontSize, bold: priority <= 1)))
            let opacity: Double = item.node.state == .quiet ? 0.7 : 0.95
            text.shading = .color(ink.opacity(opacity))
            let measured = text.measure(in: CGSize(width: 180, height: 40))
            let toRight = cos(item.node.angle) >= -0.15
            let gap: CGFloat = item.radius + 4
            let origin = CGPoint(
                x: toRight ? item.point.x + gap : item.point.x - gap - measured.width,
                y: item.point.y - measured.height / 2
            )
            let rect = CGRect(origin: origin, size: measured).insetBy(dx: -2, dy: -1)
            guard rect.minX > 2, rect.maxX < size.width - 2, rect.minY > 2, rect.maxY < size.height - 2 else { continue }
            if priority > 0 && taken.contains(where: { $0.intersects(rect) }) { continue }
            taken.append(rect)
            context.draw(text, at: CGPoint(x: origin.x, y: item.point.y), anchor: .leading)
        }
    }

    // MARK: - タップ

    /// 画面上の点に、いちばん近い体験 (指の届く範囲だけ)
    static func hit(_ location: CGPoint, scene: TreeScene, viewport: TreeViewport, size: CGSize, reach: CGFloat = 26) -> String? {
        let base = TreeViewport.base(for: size, radius: scene.radius)
        var best: (id: String, distance: CGFloat)?
        for node in scene.nodes {
            let p = viewport.screen(node.point, size: size, base: base)
            let d = hypot(p.x - location.x, p.y - location.y)
            if d <= reach, d < (best?.distance ?? .infinity) {
                best = (node.id, d)
            }
        }
        return best?.id
    }
}

// MARK: - ホームの小さな樹

/// ホームの見出しの横に置く、小さな樹 (根の輪と、灯った体験と芽だけ)。押すと体験の樹がひらく
struct MiniTreeBadge: View {
    let scene: TreeScene
    let palette: SkyPalette
    var size: CGFloat = 58

    var body: some View {
        Canvas { context, canvasSize in
            Self.draw(scene: scene, palette: palette, in: &context, size: canvasSize)
        }
        .frame(width: size, height: size)
        .background(palette.onSky.opacity(0.06), in: Circle())
        .overlay(Circle().strokeBorder(palette.onSky.opacity(0.26), lineWidth: 1))
    }

    static func draw(scene: TreeScene, palette: SkyPalette, in context: inout GraphicsContext, size: CGSize) {
        let side = min(size.width, size.height)
        let base: CGFloat = side / 2 / CGFloat(scene.radius + 0.12)
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        for node in scene.nodes {
            let p = CGPoint(x: center.x + node.point.x * base, y: center.y + node.point.y * base)
            let r: CGFloat
            let color: Color
            switch node.state {
            case .lit, .active:
                r = 2.2
                color = Palette.shu
            case .bud:
                r = 1.3
                color = palette.onSky.opacity(0.8)
            case .quiet:
                guard node.kind == .root else { continue }
                r = 1.4
                color = palette.onSky.opacity(0.45)
            }
            context.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(color))
        }
    }
}

// MARK: - 要素の小さな印 (カードや一覧で)

/// 要素の字を、細い枠の小さな四角に (朱は記した印だけに使うので、ここは藍墨)
struct ElementMark: View {
    let glyph: String
    var size: CGFloat = 18
    var color: Color = Palette.ink2

    var body: some View {
        Text(glyph)
            .font(Typeface.fixedMincho(size * 0.62))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .overlay(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).strokeBorder(color.opacity(0.55), lineWidth: 1))
            .accessibilityHidden(true)
    }
}

/// 一覧・つながりの行に添える、体験の様子の印
struct NodeStateMark: View {
    let state: NodeState
    let glyph: String
    var size: CGFloat = 26

    var body: some View {
        switch state {
        case .lit, .active:
            SealView(character: glyph, size: size, style: .filled, rotation: -4)
        case .bud:
            Circle()
                .strokeBorder(Palette.ink, lineWidth: 1.2)
                .overlay(Circle().fill(Palette.ink.opacity(0.55)).padding(size * 0.3))
                .frame(width: size * 0.62, height: size * 0.62)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        case .quiet:
            Circle()
                .fill(Palette.ink3.opacity(0.6))
                .frame(width: size * 0.22, height: size * 0.22)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}

extension NodeState {
    /// 一覧やつながりの行に添える、短い説明
    var label: String {
        switch self {
        case .active: "体験中"
        case .lit: "灯った"
        case .bud: "芽"
        case .quiet: ""
        }
    }
}
