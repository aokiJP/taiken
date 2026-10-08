import Foundation
import Observation

/// 技の樹 (4.0)。自分で記した体験から段が上がり、芽を使って技を伸ばす場所。
/// 名前が見えるのは、身についた技の隣だけ。その先は霧と条件だけ。閃きは身につくまで出ない。
@MainActor
@Observable
public final class TreeViewModel {
    /// 一覧で見るときの、要素ごとのまとまり
    public struct Section: Identifiable, Equatable, Sendable {
        public var id: String { element.id }
        public let element: ExperienceElement
        public let progress: ElementProgress
        public let nodes: [TreeNode]
        /// 芽があって、伸ばせる技がある
        public let isSprouting: Bool
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
    /// 伸ばした・結んだことで、いま閃いた技 (樹の画面で、ひとこと知らせる)
    public private(set) var freshFlashes: [TreeNode] = []

    private let source: TreeSource
    private let onStart: @MainActor (Experience) -> Void
    private let onChange: @MainActor () -> Void
    private var layoutSignature: Int

    public init(
        source: TreeSource,
        onStart: @escaping @MainActor (Experience) -> Void,
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

    /// 霧の中の技は、名前を明かさない
    public func displayTitle(of node: TreeNode) -> String {
        state(of: node.id) == .unknown ? "まだ霧の中の技" : node.title
    }

    /// 要素ごとの一覧 (探す言葉があれば、名前とできるようになることで絞る。霧の中の技は探さない)
    public var sections: [Section] {
        let words = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return tree.elements.compactMap { element in
            var nodes = tree.nodes(inElement: element.id)
            if !words.isEmpty {
                nodes = nodes.filter { state(of: $0.id) != .unknown && ($0.title.contains(words) || $0.ability.contains(words)) }
                if nodes.isEmpty { return nil }
            }
            return Section(
                element: element, progress: tree.progress(of: element.id), nodes: nodes,
                isSprouting: tree.hasLearnable(inElement: element.id)
            )
        }
    }

    /// この技の要素の根から、この技までの道すじ
    public func path(to id: String) -> [TreeNode] { tree.path(to: id) }

    /// 樹を説明する一文
    public var summary: String {
        let sprouting = tree.sproutingElements
        if !sprouting.isEmpty {
            let names = sprouting.map(\.label).joined(separator: "・")
            return "\(names)に芽が出ています。どの技へ伸ばすかを、選べます。"
        }
        if let latest = tree.learnedNodes.first {
            return "最近身についたのは「\(latest.title)」。年輪は\(Ranks.kanji(tree.totalRank))。"
        }
        if tree.totalRank > 0 {
            return "段が上がると芽が出ます。芽が出たら、どの技へ伸ばすかを選べます。"
        }
        return "まだ経験はありません。ホームから体験を記すと、触れた要素に経験が積もり、段が上がります。"
    }

    /// まだ閃いていない閃きがあるか (数は出さない)
    public var hasHiddenFlashes: Bool { tree.hiddenFlashes > 0 }

    /// 結ぶ相手 (身についた技)。自分自身と、すでに結んだ技は除く
    public func tieCandidates(for id: String) -> [TreeNode] {
        let tied = Set(tree.ties(of: id).compactMap { $0.from == id ? $0.to : $0.from })
        return tree.learnedNodes.filter { $0.id != id && !tied.contains($0.id) }
    }

    // MARK: - 技のページ

    /// ページに並べる、となりの技
    public struct Relation: Identifiable, Equatable, Sendable {
        public var id: String { node.id }
        public let node: TreeNode
        public let kind: TreeLink.Kind
        /// 結びに添えたひとこと
        public let note: String?
        public let link: TreeLink
    }

    /// この節から伸びる技 (閃きは、身についていれば出る)
    public func opens(from id: String) -> [Relation] {
        Self.unique(tree.outgoing(from: id).compactMap { link in
            tree.node(link.to).map { Relation(node: $0, kind: link.kind, note: nil, link: link) }
        })
    }

    /// この技へ至る節
    public func leadsHere(to id: String) -> [Relation] {
        Self.unique(tree.incoming(to: id).compactMap { link in
            tree.node(link.from).map { Relation(node: $0, kind: link.kind, note: nil, link: link) }
        })
    }

    /// この技と自分で結んだ技
    public func tied(to id: String) -> [Relation] {
        Self.unique(tree.ties(of: id).compactMap { link in
            let other = link.from == id ? link.to : link.from
            return tree.node(other).map { Relation(node: $0, kind: .tie, note: link.note, link: link) }
        })
    }

    /// 稽古 (体験ライブラリの体験)。霧の中の技は見せない
    public func practices(of id: String) -> [TaikenContent.LibraryExperience] {
        guard let node = tree.node(id), state(of: id) != .unknown else { return [] }
        if node.isRoot {
            // 要素の稽古: 身についた技の稽古。まだ何も身についていなければ、一の技の稽古 (はじめの入口)
            let arts = tree.nodes(inElement: node.primaryElement).filter { $0.isGrowable }
            let learned = arts.filter { state(of: $0.id) == .learned }
            let source = learned.isEmpty ? arts.filter { $0.kind == .art && $0.after.isEmpty } : learned
            return source
                .flatMap(\.practice)
                .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
                .compactMap { content.experience($0) }
        }
        return node.practice.compactMap { content.experience($0) }
    }

    /// この要素に経験を積もらせた記録 (要素のページに並べる。新しい順)
    public func entries(touching elementID: String, limit: Int = 30) -> [HistoryEntry] {
        source.entries(touching: elementID, limit: limit)
    }

    /// 要素の根からの深さ (一覧の字下げに使う)
    public func depth(of id: String) -> Int {
        guard let node = tree.node(id) else { return 0 }
        return node.kind == .flash ? 1 : tree.depths[id] ?? 0
    }

    /// 技の様子を短い一文で
    public func caption(of id: String, now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let node = tree.node(id) else { return "" }
        if node.isRoot {
            let progress = tree.progress(of: node.primaryElement)
            guard progress.rank > 0 else { return "\(node.title)の根 · 記すと経験が積もります" }
            var text = "\(node.title) \(Ranks.label(progress.rank)) · 次の段まで あと\(progress.remaining)"
            if progress.sprouts > 0 { text += " · 芽 \(progress.sprouts)" }
            return text
        }
        switch state(of: id) {
        case .learned:
            if node.kind == .flash {
                let when = tree.learnedAt(id).map { Self.relativeDay($0, now: now, calendar: calendar) } ?? ""
                return when.isEmpty ? "閃き" : "閃き · \(when)"
            }
            let mastery = tree.mastery(of: id) ?? .shu
            let uses = tree.life(of: id)?.uses ?? 0
            return uses > 0 ? "身についた技 · \(mastery.glyph) · 稽古 \(uses)" : "身についた技 · \(mastery.glyph)"
        case .ready:
            switch tree.check(id) {
            case .available(let charge):
                return "伸ばせます · \(content.element(charge)?.label ?? "")の芽を使います"
            case .needsSprout(let elements):
                let names = elements.compactMap { content.element($0)?.label }.joined(separator: "か")
                return "条件はそろいました · \(names)の段が上がると、芽が出ます"
            default:
                return "育てられる技"
            }
        case .sensed:
            return tree.requirement(of: id).map { "気配 · \($0.sentence)" } ?? "気配"
        case .unknown:
            return "霧の中 · 隣の技が身につくと、名前が見えてきます"
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

    /// 芽をひとつ使って、技を伸ばす
    @discardableResult
    public func learn(_ id: String) -> Bool {
        do {
            let flashes = try source.learn(id)
            errorMessage = nil
            changed()
            freshFlashes = flashes.compactMap { tree.node($0) }
            return true
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? AppError.storage.errorDescription
            return false
        }
    }

    /// 閃きの知らせを見終えた
    public func dismissFlashes() {
        freshFlashes = []
    }

    /// 稽古を、いま始める (ホームの「体験中」になる)
    public func start(practice item: TaikenContent.LibraryExperience, for node: TreeNode) {
        onStart(item.asExperience(reason: node.isRoot ? "「\(node.title)」の稽古です。" : "技「\(node.title)」の稽古です。"))
        reload()
    }

    /// 編んだ技の、自分の稽古を始める
    public func startOwnPractice(of node: TreeNode) {
        guard let experience = node.ownPractice() else { return }
        onStart(experience)
        reload()
    }

    /// 技を編んで、樹に植える
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

    /// 編んだ技を書き直す
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

    /// 編んだ技を手放す
    public func remove(_ id: String) {
        do {
            try source.remove(id)
            errorMessage = nil
            changed()
        } catch {
            errorMessage = AppError.storage.errorDescription
        }
    }

    /// 2つの技を朱の糸で結ぶ
    public func tie(_ first: String, _ second: String, note: String?) {
        do {
            let flashes = try source.tie(first, second, note: note)
            errorMessage = nil
            changed()
            freshFlashes = flashes.compactMap { tree.node($0) }
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

    /// 編む下書きの、直すところ (同じ名前の技があるかも見る)
    public func problems(of draft: WeaveDraft, revising id: String? = nil) -> [WeaveDraft.Problem] {
        draft.problems(existingTitles: source.existingTitles(excluding: id))
    }

    /// 編む技を伸ばす元の候補: 身についた技 (書き直す技自身と、閃きは除く)。いま選んでいる元も入れる
    public func weaveParents(excluding id: String?, current: String? = nil) -> [TreeNode] {
        var result = tree.learnedNodes.filter { $0.isGrowable && $0.id != id }
        if let current, current != id, let node = tree.node(current), node.isGrowable, !result.contains(where: { $0.id == current }) {
            result.insert(node, at: 0)
        }
        return result
    }

    /// 編んだ技の下書き (書き直すとき)
    public func draft(for node: TreeNode) -> WeaveDraft {
        WeaveDraft(
            title: node.title, ability: node.ability, practice: node.practiceText ?? "", elements: node.elements,
            growsFrom: node.after.first
        )
    }

    private func changed() {
        reload()
        onChange()
    }
}

extension TaikenContent.LibraryExperience {
    /// この体験を、きっかけとして始めるときの形
    public func asExperience(reason: String = "") -> Experience {
        Experience(
            title: title, perspective: perspective, invitation: invitation, reason: reason,
            difficulty: effort == "medium" ? .medium : .low, tags: tags, reflectionQuestion: reflectionQuestion,
            nodeID: id, elements: elements
        )
    }
}
