import Foundation
import Observation

/// 体験の樹 (指示書には無い 3.0 の場所)。
/// 灯った体験・その先の芽・自分で編んだ体験・自分で結んだ糸を、ひとつの樹として眺め、そこから体験を始められる。
/// 点数・レベル・解放の条件は無い。どの体験も、いつでも始められる。
@MainActor
@Observable
public final class TreeViewModel {
    /// 一覧で見るときの、要素ごとのまとまり
    public struct Section: Identifiable, Equatable, Sendable {
        public var id: String { element.id }
        public let element: ExperienceElement
        public let nodes: [TreeNode]
        /// 灯った体験がある
        public let isTouched: Bool
    }

    public private(set) var tree: ExperienceTree
    public private(set) var layout: TreeLayout
    /// 樹が変わるたびに変わる (描き直しの合図)
    public private(set) var revision = UUID()
    /// ひとつの要素だけを濃く見る
    public var highlightedElement: String?
    /// 一覧で探す言葉
    public var query = ""
    public private(set) var errorMessage: String?

    private let source: TreeSource
    private let onStart: @MainActor (TreeNode) -> Void
    private let onChange: @MainActor () -> Void
    private var layoutSignature: Int

    public init(
        source: TreeSource,
        onStart: @escaping @MainActor (TreeNode) -> Void,
        onChange: @escaping @MainActor () -> Void = {}
    ) {
        self.source = source
        self.onStart = onStart
        self.onChange = onChange
        let tree = source.tree()
        self.tree = tree
        layout = TreeLayout.make(tree: tree)
        layoutSignature = TreeLayout.signature(of: tree)
    }

    public var content: TaikenContent { source.content }

    /// 体験帳や自分の樹が変わったあと (画面に戻ったときなど) に呼ぶ
    public func reload() {
        let next = source.tree()
        tree = next
        let signature = TreeLayout.signature(of: next)
        if signature != layoutSignature {
            layout = TreeLayout.make(tree: next)
            layoutSignature = signature
        }
        revision = UUID()
    }

    // MARK: - 見る

    public func node(_ id: String) -> TreeNode? { tree.node(id) }

    public func state(of id: String) -> NodeState { tree.state(of: id) }

    /// 要素ごとの一覧 (探す言葉があれば、名前と誘いかけで絞る)
    public var sections: [Section] {
        let words = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return tree.elements.compactMap { element in
            var nodes = tree.nodes(inElement: element.id)
            if !words.isEmpty {
                nodes = nodes.filter { $0.title.contains(words) || $0.invitation.contains(words) }
                if nodes.isEmpty { return nil }
            }
            return Section(element: element, nodes: nodes, isTouched: tree.litCount(inElement: element.id) > 0)
        }
    }

    /// この体験の要素の根から、この体験までの道すじ
    public func path(to id: String) -> [TreeNode] { tree.path(to: id) }

    /// 樹を説明する一文 (数を目標にしない言い方で)
    public var summary: String {
        let lit = tree.litNodes
        guard let latest = lit.first else {
            return "まだ灯った体験はありません。10の根のどこからでも始められます。"
        }
        let touched = tree.elements.filter { tree.litCount(inElement: $0.id) > 0 }.map(\.label)
        return "最近灯ったのは「\(latest.title)」。\(touched.joined(separator: "・"))の枝に、灯りがあります。"
    }

    /// 灯った体験 (結ぶ相手を選ぶとき)。自分自身と、すでに結んだ体験は除く
    public func tieCandidates(for id: String) -> [TreeNode] {
        let tied = Set(tree.ties(of: id).compactMap { $0.from == id ? $0.to : $0.from })
        return tree.litNodes.filter { $0.id != id && !tied.contains($0.id) }
    }

    // MARK: - 体験のページ

    /// ページに並べる、となりの体験
    public struct Relation: Identifiable, Equatable, Sendable {
        public var id: String { node.id }
        public let node: TreeNode
        public let kind: TreeLink.Kind
        /// 結びに添えたひとこと
        public let note: String?
        public let link: TreeLink
    }

    /// この体験からひらく体験 (深める・広げる・渡る・伸ばす)
    public func opens(from id: String) -> [Relation] {
        Self.unique(tree.outgoing(from: id).compactMap { link in
            tree.node(link.to).map { Relation(node: $0, kind: link.kind, note: nil, link: link) }
        })
    }

    /// この体験へ至る体験
    public func leadsHere(to id: String) -> [Relation] {
        Self.unique(tree.incoming(to: id).compactMap { link in
            tree.node(link.from).map { Relation(node: $0, kind: link.kind, note: nil, link: link) }
        })
    }

    /// この体験と自分で結んだ体験
    public func tied(to id: String) -> [Relation] {
        Self.unique(tree.ties(of: id).compactMap { link in
            let other = link.from == id ? link.to : link.from
            return tree.node(other).map { Relation(node: $0, kind: .tie, note: link.note, link: link) }
        })
    }

    /// 要素の根からの深さ (一覧の字下げに使う)
    public func depth(of id: String) -> Int { tree.depths[id] ?? 0 }

    /// 体験の様子を短い一文で (数を目標にしない言い方で)
    public func caption(of id: String, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let node = tree.node(id) else { return "" }
        let elementLabel = tree.element(node.primaryElement)?.label ?? ""
        switch tree.state(of: id) {
        case .active:
            return "いま体験中"
        case .lit:
            let life = tree.lives[id]
            let count = life?.litCount ?? 1
            guard let last = life?.lastLived else { return "灯った体験" }
            let when = Self.relativeDay(last, now: now, calendar: calendar)
            if count > 1 { return "灯った体験 · \(count)回記した · 最後は\(when)" }
            let particle = (when == "今日" || when == "昨日") ? "" : "に"
            return "灯った体験 · \(when)\(particle)記した"
        case .bud:
            if let parent = tree.budParents[id].flatMap({ tree.node($0) }) {
                if node.kind == .woven { return "あなたが編んだ体験 · 「\(parent.title)」の先の芽" }
                return "「\(parent.title)」の先に出た芽"
            }
            if node.kind == .root { return "「\(elementLabel)」の根 · ここから始められます" }
            return "あなたの樹の芽"
        case .quiet:
            switch node.kind {
            case .root:
                return "「\(elementLabel)」の根 · いちばん小さなかたち"
            case .woven:
                if let parent = node.parentID.flatMap({ tree.node($0) }) { return "あなたが編んだ体験 · 「\(parent.title)」から" }
                return "あなたが編んだ体験"
            case .found:
                return "見つけた体験"
            case .library:
                if let parent = tree.parents[id].flatMap({ tree.node($0) }) { return "「\(parent.title)」の先" }
                return "「\(elementLabel)」の枝"
            }
        }
    }

    /// 「今日」「昨日」「3日前」「8月3日」
    static func relativeDay(_ date: Date, now: Date, calendar: Calendar) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ..<1: return "今日"
        case 1: return "昨日"
        case 2...30: return "\(days)日前"
        default:
            let parts = calendar.dateComponents([.month, .day], from: date)
            return "\(parts.month ?? 1)月\(parts.day ?? 1)日"
        }
    }

    private static func unique(_ relations: [Relation]) -> [Relation] {
        var seen = Set<String>()
        return relations.filter { seen.insert($0.node.id).inserted }
    }

    // MARK: - する

    /// この体験を、いま始める (ホームの「体験中」になる)
    public func start(_ node: TreeNode) {
        onStart(node)
        reload()
    }

    /// 体験を編んで、樹に植える
    @discardableResult
    public func weave(_ draft: WeaveDraft) -> TreeNode? {
        do {
            let created = try source.weave(draft)
            errorMessage = nil
            changed()
            return tree.node(created.id)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? AppError.storage.errorDescription
            return nil
        }
    }

    /// 編んだ体験を書き直す
    public func revise(_ id: String, with draft: WeaveDraft) -> Bool {
        do {
            try source.revise(id, with: draft)
            errorMessage = nil
            changed()
            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? AppError.storage.errorDescription
            return false
        }
    }

    /// 編んだ・見つけた体験を手放す
    public func remove(_ id: String) {
        do {
            try source.remove(id)
            errorMessage = nil
            changed()
        } catch {
            errorMessage = AppError.storage.errorDescription
        }
    }

    /// 2つの体験を朱の糸で結ぶ
    public func tie(_ first: String, _ second: String, note: String?) {
        do {
            try source.tie(first, second, note: note)
            errorMessage = nil
            changed()
        } catch {
            errorMessage = AppError.storage.errorDescription
        }
    }

    public func untie(_ link: TreeLink) {
        guard let id = link.tieID else { return }
        do {
            try source.untie(id)
            errorMessage = nil
            changed()
        } catch {
            errorMessage = AppError.storage.errorDescription
        }
    }

    /// 編んだ体験の下書き (書き直すとき)
    public func draft(for node: TreeNode) -> WeaveDraft {
        WeaveDraft(
            title: node.title, invitation: node.invitation, perspective: node.perspective,
            reflectionQuestion: node.reflectionQuestion ?? "", elements: node.elements, growsFrom: node.parentID
        )
    }

    private func changed() {
        reload()
        onChange()
    }
}
