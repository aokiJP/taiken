import Foundation

/// 自分で体験を編むときの下書き
public struct WeaveDraft: Sendable, Equatable {
    public enum Problem: String, Sendable, Equatable {
        case missingTitle, longTitle, missingInvitation, longInvitation, longPerspective, longQuestion, missingElement, tooManyElements, duplicateTitle

        public var message: String {
            switch self {
            case .missingTitle: "名前をつけてください。"
            case .longTitle: "名前は\(WeaveDraft.titleLimit)文字までです。"
            case .missingInvitation: "誘いかけを書いてください。"
            case .longInvitation: "誘いかけは\(WeaveDraft.invitationLimit)文字までです。"
            case .longPerspective: "見方は\(WeaveDraft.perspectiveLimit)文字までです。"
            case .longQuestion: "問いは\(WeaveDraft.questionLimit)文字までです。"
            case .missingElement: "要素をひとつ選んでください。"
            case .tooManyElements: "要素は3つまでです。"
            case .duplicateTitle: "同じ名前の体験がすでにあります。"
            }
        }
    }

    public static let titleLimit = 20
    public static let invitationLimit = 120
    public static let perspectiveLimit = 100
    public static let questionLimit = 40

    public var title: String
    public var invitation: String
    public var perspective: String
    public var reflectionQuestion: String
    /// 先頭が主な要素
    public var elements: [String]
    /// どの体験から伸ばすか
    public var growsFrom: String?

    public init(
        title: String = "", invitation: String = "", perspective: String = "", reflectionQuestion: String = "",
        elements: [String] = [], growsFrom: String? = nil
    ) {
        self.title = title
        self.invitation = invitation
        self.perspective = perspective
        self.reflectionQuestion = reflectionQuestion
        self.elements = elements
        self.growsFrom = growsFrom
    }

    static func trim(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    public func problems(existingTitles: Set<String> = []) -> [Problem] {
        var found: [Problem] = []
        let title = Self.trim(self.title)
        if title.isEmpty { found.append(.missingTitle) }
        if title.count > Self.titleLimit { found.append(.longTitle) }
        if existingTitles.contains(title) { found.append(.duplicateTitle) }
        let invitation = Self.trim(self.invitation)
        if invitation.isEmpty { found.append(.missingInvitation) }
        if invitation.count > Self.invitationLimit { found.append(.longInvitation) }
        if Self.trim(perspective).count > Self.perspectiveLimit { found.append(.longPerspective) }
        if Self.trim(reflectionQuestion).count > Self.questionLimit { found.append(.longQuestion) }
        if elements.isEmpty { found.append(.missingElement) }
        if elements.count > 3 { found.append(.tooManyElements) }
        return found
    }
}

/// 体験の樹の材料 (体験ライブラリ・体験帳・自分の樹) をまとめて持ち、いまの樹を組み立てる。
/// ホーム・樹の画面・送る内容の組み立てが、同じ樹を見るために使う。
@MainActor
public final class TreeSource {
    public let content: TaikenContent
    private let history: any HistoryRepository
    private let store: any GardenStore
    private let now: @Sendable () -> Date
    public private(set) var garden: Garden
    /// 自分の樹が変わるたびに増える (画面の描き直しの合図)
    public private(set) var revision = 0

    public init(
        content: TaikenContent = .shared, history: any HistoryRepository, store: any GardenStore,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.content = content
        self.history = history
        self.store = store
        self.now = now
        garden = store.load()
    }

    /// いまの樹 (体験帳の最新の記録から、毎回組み立てる。体験は100前後なので軽い)
    public func tree() -> ExperienceTree {
        TreeBuilder.build(content: content, garden: garden, entries: history.entries(since: nil, limit: nil))
    }

    /// 提案に添える樹のいま。何も灯っていなくても、根の芽は送る
    public func context() -> TreeContext? {
        let value = tree().context()
        return value.isEmpty ? nil : value
    }

    // MARK: - やってみる体験を樹に置く

    /// やってみることにした体験を、樹の上に置く。
    /// ライブラリや自分の樹にある体験ならその id を、無ければ「見つけた体験」として植えて、その id を付けて返す
    public func place(_ experience: Experience) -> Experience {
        let elements = ElementClassifier.elements(of: experience, content: content)
        let validParent = experience.growsFrom.flatMap { isKnown($0) ? $0 : nil }
        if let id = experience.nodeID, let item = content.experience(id) {
            return experience.placed(nodeID: id, elements: item.elements, growsFrom: validParent)
        }
        if let id = experience.nodeID, let node = garden.node(id) {
            return experience.placed(nodeID: id, elements: node.elements, growsFrom: validParent ?? node.growsFrom)
        }
        if let item = content.experience(titled: experience.title) {
            return experience.placed(nodeID: item.id, elements: item.elements, growsFrom: validParent)
        }
        if let node = garden.node(titled: experience.title) {
            return experience.placed(nodeID: node.id, elements: node.elements, growsFrom: validParent ?? node.growsFrom)
        }
        let node = PersonalNode(
            id: PersonalNode.makeID(kind: .found), kind: .found, title: experience.title, invitation: experience.invitation,
            perspective: experience.perspective, reflectionQuestion: experience.reflectionQuestion, elements: elements,
            tags: experience.tags, growsFrom: validParent, createdAt: now()
        )
        var next = garden
        next.nodes.append(node)
        guard commit(next) else {
            return experience.placed(nodeID: nil, elements: elements, growsFrom: validParent)
        }
        return experience.placed(nodeID: node.id, elements: elements, growsFrom: validParent)
    }

    /// 見つけた体験を、やめたときに片づける (ほかに記録が無ければ)
    public func discardFoundIfUnused(_ nodeID: String?) {
        guard let nodeID, let node = garden.node(nodeID), node.kind == .found else { return }
        let used = history.entries(since: nil, limit: nil).contains { $0.nodeID == nodeID && $0.wasChosen }
        guard !used else { return }
        var next = garden
        next.nodes.removeAll { $0.id == nodeID }
        next.ties.removeAll { $0.a == nodeID || $0.b == nodeID }
        _ = commit(next)
    }

    // MARK: - 編む・結ぶ

    /// 自分で体験を編んで、樹に植える
    @discardableResult
    public func weave(_ draft: WeaveDraft) throws -> PersonalNode {
        let titles = Set(content.experiences.map(\.title)).union(garden.nodes.map(\.title))
        let elements = Array(content.knownElements(draft.elements).prefix(3))
        var checked = draft
        checked.elements = elements
        if let problem = checked.problems(existingTitles: titles).first { throw WeaveError.invalid(problem) }
        let question = WeaveDraft.trim(draft.reflectionQuestion)
        let node = PersonalNode(
            id: PersonalNode.makeID(kind: .woven), kind: .woven, title: WeaveDraft.trim(draft.title),
            invitation: WeaveDraft.trim(draft.invitation), perspective: WeaveDraft.trim(draft.perspective),
            reflectionQuestion: question.isEmpty ? nil : question, elements: elements, tags: [],
            growsFrom: draft.growsFrom.flatMap { isKnown($0) ? $0 : nil }, createdAt: now()
        )
        var next = garden
        next.nodes.append(node)
        guard commit(next) else { throw AppError.storage }
        return node
    }

    /// 編んだ体験を書き直す (名前と要素も変えられる)
    public func revise(_ id: String, with draft: WeaveDraft) throws {
        guard let index = garden.nodes.firstIndex(where: { $0.id == id }), garden.nodes[index].kind == .woven else { return }
        let others = Set(content.experiences.map(\.title)).union(garden.nodes.filter { $0.id != id }.map(\.title))
        let elements = Array(content.knownElements(draft.elements).prefix(3))
        var checked = draft
        checked.elements = elements
        if let problem = checked.problems(existingTitles: others).first { throw WeaveError.invalid(problem) }
        var next = garden
        let question = WeaveDraft.trim(draft.reflectionQuestion)
        next.nodes[index].title = WeaveDraft.trim(draft.title)
        next.nodes[index].invitation = WeaveDraft.trim(draft.invitation)
        next.nodes[index].perspective = WeaveDraft.trim(draft.perspective)
        next.nodes[index].reflectionQuestion = question.isEmpty ? nil : question
        next.nodes[index].elements = elements
        next.nodes[index].growsFrom = draft.growsFrom.flatMap { isKnown($0) && $0 != id ? $0 : nil }
        guard commit(next) else { throw AppError.storage }
    }

    /// 編んだ・見つけた体験を手放す (体験帳の記録は残る。記録があれば、記録から樹に戻る)
    public func remove(_ id: String) throws {
        guard garden.node(id) != nil else { return }
        var next = garden
        next.nodes.removeAll { $0.id == id }
        next.ties.removeAll { $0.a == id || $0.b == id }
        for i in next.nodes.indices where next.nodes[i].growsFrom == id {
            next.nodes[i].growsFrom = nil
        }
        guard commit(next) else { throw AppError.storage }
    }

    /// 2つの体験を結ぶ。すでに結んであれば何もしない
    @discardableResult
    public func tie(_ first: String, _ second: String, note: String? = nil) throws -> Tie? {
        guard first != second, isKnown(first), isKnown(second) else { return nil }
        if garden.ties.contains(where: { $0.connects(first, second) }) { return nil }
        let tie = Tie(between: first, and: second, note: note, createdAt: now())
        var next = garden
        next.ties.append(tie)
        guard commit(next) else { throw AppError.storage }
        return tie
    }

    public func untie(_ id: UUID) throws {
        var next = garden
        next.ties.removeAll { $0.id == id }
        guard commit(next) else { throw AppError.storage }
    }

    /// 自分の樹を空にする (端末内のデータの削除)
    public func reset() throws {
        guard commit(.empty) else { throw AppError.storage }
    }

    // MARK: - 内部

    private func isKnown(_ id: String) -> Bool {
        content.experience(id) != nil || garden.node(id) != nil || tree().node(id) != nil
    }

    private func commit(_ next: Garden) -> Bool {
        do {
            try store.save(next)
            garden = next
            revision += 1
            return true
        } catch {
            return false
        }
    }
}

public enum WeaveError: LocalizedError, Equatable, Sendable {
    case invalid(WeaveDraft.Problem)

    public var errorDescription: String? {
        switch self {
        case .invalid(let problem): problem.message
        }
    }
}

// MARK: - 樹の上の位置 (カードに添える「枝」)

/// 提案や体験中の体験が、樹のどこにあるか
public struct Lineage: Equatable, Sendable {
    public let nodeID: String?
    /// 要素 (先頭が主な要素)
    public let elements: [ExperienceElement]
    /// 伸びてきた、灯った体験の名前
    public let parentTitle: String?
    /// 要素の根 (いちばん小さなかたち)
    public let isRoot: Bool
    /// 灯った体験の先の芽
    public let isBud: Bool
    /// まだ樹に無い (AIが新しく見つけた) 体験
    public let isNew: Bool

    public init(nodeID: String?, elements: [ExperienceElement], parentTitle: String?, isRoot: Bool, isBud: Bool, isNew: Bool) {
        self.nodeID = nodeID
        self.elements = elements
        self.parentTitle = parentTitle
        self.isRoot = isRoot
        self.isBud = isBud
        self.isNew = isNew
    }

    /// 「見る · 休む」
    public var elementText: String { elements.map(\.label).joined(separator: " · ") }

    /// カードに添える一行
    public var sentence: String {
        if let parentTitle { return "「\(parentTitle)」から伸びる枝" }
        if isRoot, let first = elements.first { return "「\(first.label)」の根 — いちばん小さなかたち" }
        if isNew { return "新しく見つけた体験 — やってみると樹に植わります" }
        if isBud { return "あなたの樹の芽" }
        return elements.first.map { "「\($0.label)」の枝" } ?? "体験の樹"
    }
}

extension TreeSource {
    /// 体験が樹のどこにあるか (まだ樹に無い体験も、要素だけは推し量って返す)
    public func lineage(of experience: Experience, in tree: ExperienceTree? = nil) -> Lineage {
        let tree = tree ?? self.tree()
        let elements = ElementClassifier.elements(of: experience, content: content).compactMap { content.element($0) }
        let id: String? = experience.nodeID.flatMap { tree.node($0) != nil ? $0 : nil }
            ?? content.experience(titled: experience.title)?.id
            ?? garden.node(titled: experience.title)?.id
        let parentID = experience.growsFrom.flatMap { tree.node($0) != nil ? $0 : nil } ?? id.flatMap { tree.budParents[$0] }
        return Lineage(
            nodeID: id, elements: elements, parentTitle: parentID.flatMap { tree.node($0)?.title },
            isRoot: id.map { content.isRoot($0) } ?? false, isBud: id.map { tree.isBud($0) } ?? false, isNew: id == nil
        )
    }
}
