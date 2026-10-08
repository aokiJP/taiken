import SwiftUI
import TaikenCore

/// 体験の樹を描くための材料。樹が変わったときだけ作り直し、毎フレームの描画ではこれを読むだけにする。
struct TreeScene {
    struct Node: Identifiable {
        let id: String
        /// 樹の座標 (中心 0,0。根の輪がおよそ 0.3)
        let point: CGPoint
        let angle: Double
        let state: NodeState
        let kind: TreeNode.Kind
        let glyph: String
        let title: String
        let element: String
        /// 重ねた印の数
        let litCount: Int
        /// 最後に記した時刻 (ラベルの優先順位に使う)
        let lastLived: Date?
    }

    struct Edge {
        enum Style { case quiet, toBud, lit, tie }
        let from: CGPoint
        let to: CGPoint
        let style: Style
        /// 別の要素へ渡るつながり (静かなものは、選んだときだけ描く)
        let isCross: Bool
        let fromID: String
        let toID: String
        let fromElement: String
        let toElement: String
    }

    let nodes: [Node]
    let edges: [Edge]
    let radius: Double
    /// 深さごとの輪の半径
    let rings: [Double]
    private let index: [String: Int]

    init(nodes: [Node], edges: [Edge], radius: Double, rings: [Double]) {
        self.nodes = nodes
        self.edges = edges
        self.radius = radius
        self.rings = rings
        var index: [String: Int] = [:]
        for (i, node) in nodes.enumerated() { index[node.id] = i }
        self.index = index
    }

    func node(_ id: String) -> Node? { index[id].map { nodes[$0] } }

    /// 要素の体験が集まっているあたり (要素を選んだとき、そこへ寄る)
    func centroid(ofElement element: String) -> CGPoint? {
        let points = nodes.filter { $0.element == element }.map(\.point)
        guard !points.isEmpty else { return nil }
        let count = CGFloat(points.count)
        return CGPoint(x: points.map(\.x).reduce(0, +) / count, y: points.map(\.y).reduce(0, +) / count)
    }

    static let empty = TreeScene(nodes: [], edges: [], radius: 1, rings: [])

    static func make(tree: ExperienceTree, layout: TreeLayout) -> TreeScene {
        var nodes: [Node] = []
        for node in tree.nodes {
            guard let p = layout.position(of: node.id) else { continue }
            let life = tree.lives[node.id]
            nodes.append(Node(
                id: node.id,
                point: CGPoint(x: p.x, y: p.y),
                angle: atan2(p.y, p.x),
                state: tree.state(of: node.id),
                kind: node.kind,
                glyph: tree.glyph(of: node),
                title: node.title,
                element: node.primaryElement,
                litCount: life?.litCount ?? 0,
                lastLived: life?.lastLived
            ))
        }
        var states: [String: NodeState] = [:]
        var elements: [String: String] = [:]
        for node in nodes {
            states[node.id] = node.state
            elements[node.id] = node.element
        }
        func isTaken(_ state: NodeState?) -> Bool { state == .lit || state == .active }

        var edges: [Edge] = []
        for link in tree.links {
            guard let a = layout.position(of: link.from), let b = layout.position(of: link.to) else { continue }
            let style: Edge.Style
            if link.kind == .tie {
                style = .tie
            } else if isTaken(states[link.from]) && isTaken(states[link.to]) {
                style = .lit
            } else if isTaken(states[link.from]) && states[link.to] == .bud {
                style = .toBud
            } else {
                style = .quiet
            }
            let fromElement = elements[link.from] ?? ""
            let toElement = elements[link.to] ?? ""
            edges.append(Edge(
                from: CGPoint(x: a.x, y: a.y), to: CGPoint(x: b.x, y: b.y), style: style,
                isCross: fromElement != toElement, fromID: link.from, toID: link.to,
                fromElement: fromElement, toElement: toElement
            ))
        }
        // 静かなつながりを先に、灯ったつながりと糸をあとに描く
        edges.sort { order($0.style) < order($1.style) }
        let maxDepth = tree.depths.values.max() ?? 0
        let rings = (0...max(maxDepth, 1)).map { TreeLayout.ring(forDepth: $0) }
        return TreeScene(nodes: nodes, edges: edges, radius: layout.radius, rings: rings)
    }

    private static func order(_ style: Edge.Style) -> Int {
        switch style {
        case .quiet: 0
        case .toBud: 1
        case .lit: 2
        case .tie: 3
        }
    }
}

/// 見ている範囲 (拡大と移動)
struct TreeViewport: Equatable {
    var zoom: CGFloat = 1
    var pan: CGSize = .zero

    static let minimumZoom: CGFloat = 0.7
    static let maximumZoom: CGFloat = 4.5

    /// 樹の座標 → 画面の座標
    func screen(_ world: CGPoint, size: CGSize, base: CGFloat) -> CGPoint {
        CGPoint(
            x: size.width / 2 + pan.width + world.x * base * zoom,
            y: size.height / 2 + pan.height + world.y * base * zoom
        )
    }

    /// 樹全体が収まる、拡大 1 のときの1単位の長さ
    static func base(for size: CGSize, radius: Double) -> CGFloat {
        let side = min(size.width, size.height)
        return max(40, side / 2 / CGFloat(radius + 0.14))
    }

    /// world の点を画面の中心に
    func centered(on world: CGPoint, base: CGFloat, zoom newZoom: CGFloat? = nil) -> TreeViewport {
        let z = newZoom ?? zoom
        return TreeViewport(zoom: z, pan: CGSize(width: -world.x * base * z, height: -world.y * base * z))
    }

    /// 樹が画面から離れすぎないように、移動の幅をおさえる
    func clamped(size: CGSize, radius: Double) -> TreeViewport {
        let reach = CGFloat(radius) * Self.base(for: size, radius: radius) * zoom
        let limitX = reach + size.width * 0.25
        let limitY = reach + size.height * 0.25
        var next = self
        next.pan = CGSize(width: min(limitX, max(-limitX, pan.width)), height: min(limitY, max(-limitY, pan.height)))
        return next
    }

    /// anchor (画面の中心からのずれ) を動かさずに拡大する
    func zoomed(by factor: CGFloat, around anchor: CGPoint, size: CGSize) -> TreeViewport {
        let target = min(Self.maximumZoom, max(Self.minimumZoom, zoom * factor))
        let real = target / zoom
        let ax = anchor.x - size.width / 2
        let ay = anchor.y - size.height / 2
        return TreeViewport(
            zoom: target,
            pan: CGSize(width: ax - (ax - pan.width) * real, height: ay - (ay - pan.height) * real)
        )
    }
}
