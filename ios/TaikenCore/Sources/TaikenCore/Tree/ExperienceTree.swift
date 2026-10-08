import Foundation

/// 体験の樹の1つの体験
public struct TreeNode: Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// 要素の根 (いちばん小さなかたちの体験)
        case root
        /// 体験ライブラリの体験
        case library
        /// 自分で編んだ体験
        case woven
        /// AIが作り、自分でやってみることにした体験
        case found
    }

    public let id: String
    public let kind: Kind
    public let title: String
    public let invitation: String
    public let perspective: String
    public let reflectionQuestion: String?
    /// 要素の id (先頭が主な要素。必ず1つ以上)
    public let elements: [String]
    public let tags: [String]
    /// 時間帯の決まった体験 (空ならいつでも)
    public let times: [String]
    /// 編んだ・見つけた体験の親 (どこから伸びたか)
    public let parentID: String?

    public var primaryElement: String { elements.first ?? "see" }
    public var isPersonal: Bool { kind == .woven || kind == .found }

    /// この体験を「やってみる」ときの形
    public func experience(reason: String = "", growsFrom: String? = nil) -> Experience {
        Experience(
            title: title, perspective: perspective, invitation: invitation, reason: reason, difficulty: .low, tags: tags,
            reflectionQuestion: reflectionQuestion, nodeID: id, elements: elements, growsFrom: growsFrom ?? parentID
        )
    }
}

/// 体験から体験へのつながり
public struct TreeLink: Hashable, Sendable {
    public enum Kind: String, Sendable {
        /// 深める (同じ要素で、より細やかに)
        case deepen
        /// 広げる (同じ要素で、別の場面へ)
        case widen
        /// 渡る (別の要素へ)
        case cross
        /// 編んだ・見つけた体験が伸びた先
        case grow
        /// 自分で結んだ糸
        case tie

        public var label: String {
            switch self {
            case .deepen: "深める"
            case .widen: "広げる"
            case .cross: "渡る"
            case .grow: "伸ばす"
            case .tie: "結ぶ"
            }
        }
    }

    public let from: String
    public let to: String
    public let kind: Kind
    /// 結びに添えたひとこと
    public let note: String?
    public let tieID: UUID?

    public init(from: String, to: String, kind: Kind, note: String? = nil, tieID: UUID? = nil) {
        self.from = from
        self.to = to
        self.kind = kind
        self.note = note
        self.tieID = tieID
    }
}

/// 樹の上での体験の様子
public enum NodeState: String, Sendable, Equatable {
    /// いま体験中
    case active
    /// 灯った (記したことがある)
    case lit
    /// 芽 (灯った体験からつながっている、まだやっていない体験)
    case bud
    /// まだ遠い
    case quiet
}

/// その体験を生きた記録
public struct NodeLife: Sendable, Equatable {
    /// 選んだ記録 (体験中・終えた)。新しい順
    public let entries: [HistoryEntry]

    public init(entries: [HistoryEntry]) {
        self.entries = entries
    }

    /// 記した回数 (重ねた印の数)
    public var litCount: Int { entries.filter { $0.status == .completed }.count }
    public var isActive: Bool { entries.contains { $0.status == .active } }
    public var isLit: Bool { litCount > 0 }

    /// 最後に記した時刻
    public var lastLived: Date? {
        entries.first { $0.status == .completed }.map { $0.finishedAt ?? $0.createdAt }
    }
}

/// 体験の樹。要素の根から、体験がつながって伸びていく。
/// 点数もレベルも無い。灯った体験と、その先の芽と、自分で結んだ糸だけがある。
public struct ExperienceTree: Sendable {
    public let content: TaikenContent
    public let nodes: [TreeNode]
    public let links: [TreeLink]
    /// 体験ごとの記録 (選んだことのある体験だけ)
    public let lives: [String: NodeLife]
    /// 芽 (提案に少しだけ前に出す順)
    public let buds: [String]
    /// 芽 → その芽が伸びている灯った体験
    public let budParents: [String: String]
    /// 要素の中での親 (根からたどった道。表示の配置と道すじに使う)
    public let parents: [String: String]
    /// 要素の根からの深さ (根 = 0)
    public let depths: [String: Int]
    /// 要素の中での子 (並び順は、つながりの順)
    public let children: [String: [String]]
    /// 記録から、どの体験の記録か
    public let entryNodes: [UUID: String]

    private let index: [String: Int]
    private let outgoingIndex: [String: [Int]]
    private let incomingIndex: [String: [Int]]
    private let budSet: Set<String>

    init(
        content: TaikenContent, nodes: [TreeNode], links: [TreeLink], lives: [String: NodeLife], buds: [String],
        budParents: [String: String], parents: [String: String], depths: [String: Int], children: [String: [String]],
        entryNodes: [UUID: String]
    ) {
        self.content = content
        self.nodes = nodes
        self.links = links
        self.lives = lives
        self.buds = buds
        self.budParents = budParents
        self.parents = parents
        self.depths = depths
        self.children = children
        self.entryNodes = entryNodes
        var index: [String: Int] = [:]
        for (i, node) in nodes.enumerated() where index[node.id] == nil { index[node.id] = i }
        self.index = index
        var outgoing: [String: [Int]] = [:]
        var incoming: [String: [Int]] = [:]
        for (i, link) in links.enumerated() {
            outgoing[link.from, default: []].append(i)
            incoming[link.to, default: []].append(i)
        }
        outgoingIndex = outgoing
        incomingIndex = incoming
        budSet = Set(buds)
    }

    // MARK: - 引く

    public func node(_ id: String) -> TreeNode? { index[id].map { nodes[$0] } }

    public var elements: [ExperienceElement] { content.elements }

    public func element(_ id: String) -> ExperienceElement? { content.element(id) }

    /// 体験の印の字 (主な要素の字)
    public func glyph(of node: TreeNode) -> String {
        ElementClassifier.glyph(for: node.elements, content: content)
    }

    public func root(of elementID: String) -> TreeNode? {
        content.element(elementID).flatMap { node($0.root) }
    }

    public func state(of id: String) -> NodeState {
        if let life = lives[id] {
            if life.isActive { return .active }
            if life.isLit { return .lit }
        }
        return budSet.contains(id) ? .bud : .quiet
    }

    public func isBud(_ id: String) -> Bool { budSet.contains(id) }

    /// この体験からひらく体験 (結びは含まない)
    public func outgoing(from id: String) -> [TreeLink] {
        (outgoingIndex[id] ?? []).map { links[$0] }.filter { $0.kind != .tie }
    }

    /// この体験へ至る体験 (結びは含まない)
    public func incoming(to id: String) -> [TreeLink] {
        (incomingIndex[id] ?? []).map { links[$0] }.filter { $0.kind != .tie }
    }

    /// この体験と結んだ糸
    public func ties(of id: String) -> [TreeLink] {
        let out = (outgoingIndex[id] ?? []).map { links[$0] }
        let into = (incomingIndex[id] ?? []).map { links[$0] }
        return (out + into).filter { $0.kind == .tie }
    }

    /// 要素の体験 (主な要素がその要素のもの)。根が先頭
    public func nodes(inElement elementID: String) -> [TreeNode] {
        nodes.filter { $0.primaryElement == elementID }.sorted { lhs, rhs in
            (depths[lhs.id] ?? 9, index[lhs.id] ?? 0) < (depths[rhs.id] ?? 9, index[rhs.id] ?? 0)
        }
    }

    /// 灯った体験 (最近記したものから)
    public var litNodes: [TreeNode] {
        nodes.filter { lives[$0.id]?.isLit == true }.sorted {
            (lives[$0.id]?.lastLived ?? .distantPast) > (lives[$1.id]?.lastLived ?? .distantPast)
        }
    }

    public var activeNode: TreeNode? { nodes.first { lives[$0.id]?.isActive == true } }

    /// 灯った体験の数 (要素ごと)。数を競わせないため、画面には「どの要素に触れたか」としてだけ使う
    public func litCount(inElement elementID: String) -> Int {
        nodes.filter { $0.primaryElement == elementID && lives[$0.id]?.isLit == true }.count
    }

    /// 根から、この体験までの道すじ (根が先頭)
    public func path(to id: String) -> [TreeNode] {
        var result: [TreeNode] = []
        var current: String? = id
        var guardCount = 0
        while let value = current, let found = node(value), guardCount < 32 {
            result.append(found)
            current = parents[value]
            guardCount += 1
        }
        return result.reversed()
    }

    /// この体験の先で、まだ灯っていない体験 (記したあとに「芽が出た」と見せる)
    public func opened(by id: String, limit: Int = 3) -> [TreeNode] {
        var seen = Set<String>()
        return outgoing(from: id)
            .compactMap { node($0.to) }
            .filter { lives[$0.id]?.isLit != true && seen.insert($0.id).inserted }
            .prefix(limit)
            .map { $0 }
    }

    /// 記録が、樹の上のどの体験か
    public func nodeID(of entry: HistoryEntry) -> String? { entryNodes[entry.id] }

    /// 提案に添えて送る、樹のいま (灯った体験は最近のものから、芽は前に出す順)
    public func context(maxLived: Int = 12, maxBuds: Int = 16) -> TreeContext {
        TreeContext(
            lived: litNodes.prefix(maxLived).map { TreeContext.LivedNode(id: $0.id, title: $0.title, elements: $0.elements) },
            buds: Array(buds.prefix(maxBuds))
        )
    }

    /// ライブラリの体験から選ぶとき、芽として前に出す id
    public var budIDs: Set<String> { budSet }
}

// MARK: - 組み立て

public enum TreeBuilder {
    /// 体験ライブラリ・自分の樹 (編んだ体験・見つけた体験・結び)・体験帳から、いまの樹を組み立てる
    public static func build(content: TaikenContent = .shared, garden: Garden, entries: [HistoryEntry]) -> ExperienceTree {
        var nodes: [TreeNode] = []
        var known = Set<String>()
        let classifier = ElementClassifier(content: content)

        func elements(_ ids: [String], title: String, invitation: String, perspective: String, tags: [String]) -> [String] {
            let filtered = Array(content.knownElements(ids).prefix(3))
            return filtered.isEmpty
                ? classifier.classify(title: title, invitation: invitation, perspective: perspective, tags: tags) : filtered
        }

        for item in content.experiences where known.insert(item.id).inserted {
            nodes.append(TreeNode(
                id: item.id, kind: content.isRoot(item.id) ? .root : .library, title: item.title, invitation: item.invitation,
                perspective: item.perspective, reflectionQuestion: item.reflectionQuestion,
                elements: elements(item.elements, title: item.title, invitation: item.invitation, perspective: item.perspective, tags: item.tags),
                tags: item.tags, times: item.times, parentID: nil
            ))
        }
        for item in garden.nodes where known.insert(item.id).inserted {
            nodes.append(TreeNode(
                id: item.id, kind: item.kind == .woven ? .woven : .found, title: item.title, invitation: item.invitation,
                perspective: item.perspective, reflectionQuestion: item.reflectionQuestion,
                elements: elements(item.elements, title: item.title, invitation: item.invitation, perspective: item.perspective, tags: item.tags),
                tags: item.tags, times: [], parentID: item.growsFrom
            ))
        }

        // 記録を体験に結びつける。どこにも無い体験 (3.0 より前にAIが作った体験など) は、記録から樹に植える
        var byTitle: [String: String] = [:]
        for node in nodes where byTitle[node.title] == nil { byTitle[node.title] = node.id }
        var grouped: [String: [HistoryEntry]] = [:]
        var entryNodes: [UUID: String] = [:]
        for entry in entries where entry.wasChosen {
            let id: String
            if let nodeID = entry.nodeID, known.contains(nodeID) {
                id = nodeID
            } else if let match = byTitle[entry.title] {
                id = match
            } else {
                id = "h-" + String(LibrarySelector.fnv1a(entry.title), radix: 16)
                if known.insert(id).inserted {
                    nodes.append(TreeNode(
                        id: id, kind: .found, title: entry.title, invitation: entry.invitation, perspective: entry.perspective,
                        reflectionQuestion: entry.reflectionQuestion, elements: entry.resolvedElements(content: content),
                        tags: entry.tags, times: [], parentID: nil
                    ))
                    byTitle[entry.title] = id
                }
            }
            grouped[id, default: []].append(entry)
            entryNodes[entry.id] = id
        }
        var lives: [String: NodeLife] = [:]
        for (id, list) in grouped {
            lives[id] = NodeLife(entries: list.sorted { $0.createdAt > $1.createdAt })
        }

        // つながり
        var links: [TreeLink] = []
        for item in content.experiences {
            for link in item.opens where known.contains(link.to) && link.to != item.id {
                let kind: TreeLink.Kind = switch link.kind {
                case .deepen: .deepen
                case .widen: .widen
                case .cross: .cross
                }
                links.append(TreeLink(from: item.id, to: link.to, kind: kind))
            }
        }
        for node in nodes where node.isPersonal {
            let parent = node.parentID.flatMap { known.contains($0) && $0 != node.id ? $0 : nil }
                ?? content.element(node.primaryElement)?.root
            if let parent, known.contains(parent), parent != node.id {
                links.append(TreeLink(from: parent, to: node.id, kind: .grow))
            }
        }
        for tie in garden.ties where known.contains(tie.a) && known.contains(tie.b) && tie.a != tie.b {
            links.append(TreeLink(from: tie.a, to: tie.b, kind: .tie, note: tie.note, tieID: tie.id))
        }

        let (parents, depths, children) = spanning(content: content, nodes: nodes, links: links)
        let (buds, budParents) = sprout(content: content, nodes: nodes, links: links, lives: lives)

        return ExperienceTree(
            content: content, nodes: nodes, links: links, lives: lives, buds: buds, budParents: budParents,
            parents: parents, depths: depths, children: children, entryNodes: entryNodes
        )
    }

    /// 要素ごとに、根からつながりをたどった木 (主な要素が同じ体験だけ)。たどり着けない体験は根に直接つなぐ
    static func spanning(content: TaikenContent, nodes: [TreeNode], links: [TreeLink]) -> ([String: String], [String: Int], [String: [String]]) {
        var parents: [String: String] = [:]
        var depths: [String: Int] = [:]
        var children: [String: [String]] = [:]
        var primary: [String: String] = [:]
        for node in nodes { primary[node.id] = node.primaryElement }
        var outgoing: [String: [String]] = [:]
        for link in links where link.kind != .tie {
            outgoing[link.from, default: []].append(link.to)
        }

        for element in content.elements {
            guard primary[element.root] != nil else { continue }
            depths[element.root] = 0
            var queue = [element.root]
            var head = 0
            while head < queue.count {
                let current = queue[head]
                head += 1
                for next in outgoing[current] ?? [] where primary[next] == element.id && depths[next] == nil {
                    depths[next] = (depths[current] ?? 0) + 1
                    parents[next] = current
                    children[current, default: []].append(next)
                    queue.append(next)
                }
            }
        }
        // 根からたどれない体験 (主な要素の根へ直接)
        for node in nodes where depths[node.id] == nil {
            guard let root = content.element(node.primaryElement)?.root, depths[root] != nil, root != node.id else {
                depths[node.id] = 0
                continue
            }
            depths[node.id] = 1
            parents[node.id] = root
            children[root, default: []].append(node.id)
        }
        return (parents, depths, children)
    }

    /// 芽: 灯った体験 (最近のものから) の先にある、まだやっていない体験。
    /// 何も灯っていなければ、すべての根が芽になる。芽が少ないときは、まだ触れていない要素の根を足す
    static func sprout(content: TaikenContent, nodes: [TreeNode], links: [TreeLink], lives: [String: NodeLife]) -> ([String], [String: String]) {
        let lit = nodes.filter { lives[$0.id]?.isLit == true }.sorted {
            (lives[$0.id]?.lastLived ?? .distantPast) > (lives[$1.id]?.lastLived ?? .distantPast)
        }
        var outgoing: [String: [String]] = [:]
        for link in links where link.kind != .tie {
            outgoing[link.from, default: []].append(link.to)
        }
        func taken(_ id: String) -> Bool {
            guard let life = lives[id] else { return false }
            return life.isLit || life.isActive
        }

        var buds: [String] = []
        var parents: [String: String] = [:]
        var seen = Set<String>()
        for node in lit {
            for next in outgoing[node.id] ?? [] where !taken(next) && seen.insert(next).inserted {
                buds.append(next)
                parents[next] = node.id
            }
        }
        if lit.isEmpty {
            for element in content.elements where !taken(element.root) && seen.insert(element.root).inserted {
                buds.append(element.root)
            }
        } else if buds.count < 3 {
            let touched = Set(lit.map(\.primaryElement))
            for element in content.elements where !touched.contains(element.id) && !taken(element.root) && seen.insert(element.root).inserted {
                buds.append(element.root)
            }
        }
        return (buds, parents)
    }
}
