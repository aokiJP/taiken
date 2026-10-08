import Foundation

/// 技の樹の配置。中心から10の要素が放射状に伸び、根は内側の輪に、深い技ほど外側に並ぶ。
/// 閃きは、その要素の扇のいちばん外の輪に置く。
/// 同じ樹からはいつも同じ配置になる (乱数を使わない)。座標は中心 (0, 0)・根の輪の半径 0.3 前後の単位で返す。
public struct TreeLayout: Sendable, Equatable {
    public struct Point: Sendable, Hashable {
        public var x: Double
        public var y: Double

        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }

        public func distance(to other: Point) -> Double {
            ((x - other.x) * (x - other.x) + (y - other.y) * (y - other.y)).squareRoot()
        }
    }

    /// 要素の扇 (角度はラジアン。上が -π/2、時計回りに増える)
    public struct Sector: Sendable, Equatable {
        public let element: String
        public let start: Double
        public let end: Double
        public var center: Double { (start + end) / 2 }
    }

    public let positions: [String: Point]
    public let sectors: [Sector]
    /// いちばん外側の体験までの半径
    public let radius: Double

    /// 根の輪の半径と、深さごとの間隔
    public static let rootRadius = 0.3
    public static let ringStep = 0.2
    /// 同じ輪の上で、隣の体験と少なくともこれだけ離す (弧の長さ)
    static let minimumArc = 0.085

    public func position(of id: String) -> Point? { positions[id] }

    public static func ring(forDepth depth: Int) -> Double {
        rootRadius + Double(depth) * ringStep
    }

    /// 樹の形 (体験と親子) が同じなら、同じ配置になる
    public static func signature(of tree: ExperienceTree) -> Int {
        var hasher = Hasher()
        for node in tree.nodes {
            hasher.combine(node.id)
            hasher.combine(node.primaryElement)
            hasher.combine(tree.parents[node.id])
        }
        return hasher.finalize()
    }

    public static func make(tree: ExperienceTree) -> TreeLayout {
        let elements = tree.content.elements
        guard !elements.isEmpty else { return TreeLayout(positions: [:], sectors: [], radius: 1) }

        // 葉の数 (子の無い体験を1とする)
        var leaves: [String: Double] = [:]
        func leafWeight(_ id: String, depth: Int) -> Double {
            if let cached = leaves[id] { return cached }
            let kids = (tree.children[id] ?? []).filter { tree.parents[$0] == id }
            let value = kids.isEmpty || depth > 24 ? 1 : kids.reduce(0) { $0 + leafWeight($1, depth: depth + 1) }
            leaves[id] = value
            return value
        }

        // 扇の広さは、その要素の葉の数に合わせる (体験の多い要素が窮屈にならないように)
        var weights: [Double] = []
        for element in elements {
            let weight = tree.root(of: element.id).map { leafWeight($0.id, depth: 0) } ?? 1
            weights.append(max(3, weight))
        }
        let total = weights.reduce(0, +)
        let fullTurn = 2 * Double.pi
        var start = -Double.pi / 2 - fullTurn * (weights[0] / total) / 2
        var sectors: [Sector] = []
        for (i, element) in elements.enumerated() {
            let width = fullTurn * weights[i] / total
            sectors.append(Sector(element: element.id, start: start, end: start + width))
            start += width
        }

        var angles: [String: Double] = [:]
        var radii: [String: Double] = [:]

        func place(_ id: String, from lower: Double, to upper: Double, depth: Int) {
            angles[id] = (lower + upper) / 2
            radii[id] = ring(forDepth: depth) + (depth == 0 ? 0 : wobble(id))
            let kids = (tree.children[id] ?? []).filter { tree.parents[$0] == id }
            guard !kids.isEmpty, depth < 24 else { return }
            let sum = kids.reduce(0) { $0 + (leaves[$1] ?? 1) }
            var cursor = lower
            for kid in kids {
                let span = (upper - lower) * (leaves[kid] ?? 1) / max(sum, 1)
                place(kid, from: cursor, to: cursor + span, depth: depth + 1)
                cursor += span
            }
        }

        for sector in sectors {
            guard let root = tree.root(of: sector.element)?.id else { continue }
            let gap = (sector.end - sector.start) * 0.06
            place(root, from: sector.start + gap, to: sector.end - gap, depth: 0)
        }
        // 閃きは、その要素の扇のいちばん外の輪に、扇の中で等しく間をあけて置く
        let outer = (tree.depths.values.max() ?? 2) + 1
        for sector in sectors {
            let flashes = tree.nodes.filter { $0.kind == .flash && $0.primaryElement == sector.element }
            for (i, node) in flashes.enumerated() {
                let share = (sector.end - sector.start) / Double(flashes.count + 1)
                angles[node.id] = sector.start + share * Double(i + 1)
                radii[node.id] = ring(forDepth: outer)
            }
        }
        // どの根にもつながらない技 (根が無いなど) は外側の輪に並べる
        let stray = tree.nodes.filter { angles[$0.id] == nil }
        for (i, node) in stray.enumerated() {
            angles[node.id] = -Double.pi / 2 + fullTurn * Double(i) / Double(max(stray.count, 1))
            radii[node.id] = ring(forDepth: outer + 1)
        }

        relax(&angles, radii: radii, order: tree.nodes.map(\.id))

        var positions: [String: Point] = [:]
        var radius = rootRadius
        for node in tree.nodes {
            guard let angle = angles[node.id], let r = radii[node.id] else { continue }
            positions[node.id] = Point(x: r * cos(angle), y: r * sin(angle))
            radius = max(radius, r)
        }
        return TreeLayout(positions: positions, sectors: sectors, radius: radius)
    }

    /// 体験ごとに決まった、ほんの少しの揺らぎ (輪が機械的に見えないように)
    static func wobble(_ id: String) -> Double {
        (Double(LibrarySelector.fnv1a(id) % 1000) / 1000 - 0.5) * 0.04
    }

    /// 同じ輪の上で近すぎる体験を、角度だけ動かして離す (順番は変えない)
    static func relax(_ angles: inout [String: Double], radii: [String: Double], order: [String]) {
        var rings: [Int: [String]] = [:]
        for id in order {
            guard let r = radii[id] else { continue }
            let key = Int(((r - rootRadius) / ringStep).rounded())
            rings[key, default: []].append(id)
        }
        for key in rings.keys.sorted() {
            guard var ids = rings[key], ids.count > 1 else { continue }
            let r = ring(forDepth: max(0, key))
            let minimum = min(minimumArc / max(r, 0.1), 2 * Double.pi / Double(ids.count) * 0.9)
            for _ in 0..<60 {
                ids.sort { (angles[$0] ?? 0, $0) < (angles[$1] ?? 0, $1) }
                var moved = false
                for i in 0..<ids.count {
                    let a = ids[i]
                    let b = ids[(i + 1) % ids.count]
                    guard let first = angles[a], var second = angles[b] else { continue }
                    if i == ids.count - 1 { second += 2 * Double.pi }
                    let gap = second - first
                    if gap < minimum {
                        let push = (minimum - gap) / 2
                        angles[a] = first - push
                        angles[b] = (angles[b] ?? 0) + push
                        moved = true
                    }
                }
                if !moved { break }
            }
        }
    }
}
