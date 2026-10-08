import Foundation

/// 自分で技を編むときの下書き (自分で名づけた技を、樹に植える)
public struct WeaveDraft: Sendable, Equatable {
    public enum Problem: String, Sendable, Equatable {
        case missingTitle, longTitle, missingAbility, longAbility, longPractice, missingElement, tooManyElements, duplicateTitle

        public var message: String {
            switch self {
            case .missingTitle: "技に名前をつけてください。"
            case .longTitle: "名前は\(WeaveDraft.titleLimit)文字までです。"
            case .missingAbility: "身につくと、何ができるようになるかを書いてください。"
            case .longAbility: "できるようになることは\(WeaveDraft.abilityLimit)文字までです。"
            case .longPractice: "稽古は\(WeaveDraft.practiceLimit)文字までです。"
            case .missingElement: "要素をひとつ選んでください。"
            case .tooManyElements: "要素は\(WeaveDraft.elementLimit)つまでです。"
            case .duplicateTitle: "同じ名前の技がすでにあります。"
            }
        }
    }

    public static let titleLimit = 12
    public static let abilityLimit = 40
    public static let practiceLimit = 120
    public static let elementLimit = 2

    /// 技の名前
    public var title: String
    /// 身につくと、できるようになること
    public var ability: String
    /// 自分の稽古 (この技の見方で過ごす入口。任意)
    public var practice: String
    /// 先頭が主な要素
    public var elements: [String]
    /// どの技から伸ばすか (無ければ要素の根から)
    public var growsFrom: String?

    public init(title: String = "", ability: String = "", practice: String = "", elements: [String] = [], growsFrom: String? = nil) {
        self.title = title
        self.ability = ability
        self.practice = practice
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
        let ability = Self.trim(self.ability)
        if ability.isEmpty { found.append(.missingAbility) }
        if ability.count > Self.abilityLimit { found.append(.longAbility) }
        if Self.trim(practice).count > Self.practiceLimit { found.append(.longPractice) }
        if elements.isEmpty { found.append(.missingElement) }
        if elements.count > Self.elementLimit { found.append(.tooManyElements) }
        return found
    }
}

/// 自分で記す体験の下書き (提案から始めたものでなくてよい)
public struct LivedDraft: Sendable, Equatable {
    public static let textLimit = 60

    /// 何を体験したか (自分の言葉で、ひとこと)
    public var text: String
    /// 触れた要素 (1〜3)
    public var elements: [String]
    /// 使った技 (身についた技から、自分で選ぶ)
    public var skills: [String]

    public init(text: String = "", elements: [String] = [], skills: [String] = []) {
        self.text = text
        self.elements = elements
        self.skills = skills
    }

    public var trimmedText: String { String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.textLimit)) }

    /// 記せる (言葉があり、要素を1〜3つ選んでいる)
    public var isReady: Bool { !trimmedText.isEmpty && (1...3).contains(elements.count) }
}

/// 技の樹の材料 (体験ライブラリ・技の樹・体験帳・自分の樹) をまとめて持ち、いまの樹を組み立てる。
/// ホーム・樹の画面・送る内容の組み立てが、同じ樹を見るために使う。
@MainActor
public final class TreeSource {
    public let content: TaikenContent
    public let book: SkillBook
    private let history: any HistoryRepository
    private let store: any GardenStore
    private let now: @Sendable () -> Date
    private let calendar: Calendar
    public private(set) var garden: Garden
    /// 自分の樹が変わるたびに増える (画面の描き直しの合図)
    public private(set) var revision = 0

    public init(
        content: TaikenContent = .shared, book: SkillBook = .shared, history: any HistoryRepository, store: any GardenStore,
        calendar: Calendar = .current, now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.content = content
        self.book = book
        self.history = history
        self.store = store
        self.calendar = calendar
        self.now = now
        garden = store.load()
    }

    /// いまの樹 (体験帳の最新の記録から、毎回組み立てる。技と記録は百前後なので軽い)
    public func tree() -> ExperienceTree {
        TreeBuilder.build(
            content: content, book: book, garden: garden, entries: history.entries(since: nil, limit: nil), calendar: calendar
        )
    }

    /// 提案に添える樹のいま。何も身についていなくても、根の稽古は送る
    public func context() -> TreeContext? {
        let value = tree().context(entries: history.entries(since: nil, limit: 200))
        return value.isEmpty ? nil : value
    }

    /// この要素に経験を積もらせた記録 (記した体験だけ。新しい順)
    public func entries(touching elementID: String, limit: Int = 30) -> [HistoryEntry] {
        let touching = history.entries(since: nil, limit: nil).filter { entry in
            entry.status == .completed && entry.resolvedElements(content: content).prefix(3).contains(elementID)
        }
        return Array(touching.sorted { $0.createdAt > $1.createdAt }.prefix(max(0, limit)))
    }

    // MARK: - 伸ばす

    public enum LearnError: LocalizedError, Equatable, Sendable {
        case locked(String)
        case noSprout(String)
        case unavailable

        public var errorDescription: String? {
            switch self {
            case .locked(let sentence): "まだ届きません。\(sentence)"
            case .noSprout(let element): "\(element)の芽がありません。\(element)の段が上がると、芽が出ます。"
            case .unavailable: "この技は伸ばせません。"
            }
        }
    }

    /// 芽をひとつ使って、技を伸ばす。新しく閃いた技があれば、その id も返す
    @discardableResult
    public func learn(_ id: String) throws -> [String] {
        let current = tree()
        switch current.check(id) {
        case .available(let charge):
            var next = garden
            next.learned.append(LearnedSkill(id: id, element: charge, learnedAt: now()))
            guard commit(next) else { throw AppError.storage }
            return settle()
        case .needsSprout(let elements):
            let label = elements.first.flatMap { content.element($0)?.label } ?? "その要素"
            throw LearnError.noSprout(label)
        case .locked(let requirement):
            throw LearnError.locked(requirement.sentence)
        case .learned, .notGrowable:
            throw LearnError.unavailable
        }
    }

    /// 閃きの条件を確かめて、新しく閃いた技を自分の樹に残す (体験帳を消しても、閃きは消えない)。新しく閃いた id を返す
    @discardableResult
    public func settle() -> [String] {
        let current = tree()
        let fresh = current.nodes.filter { $0.kind == .flash && !garden.isLearned($0.id) }
        guard !fresh.isEmpty else { return [] }
        var next = garden
        for node in fresh {
            next.learned.append(LearnedSkill(id: node.id, element: nil, learnedAt: current.learnedAt(node.id) ?? now()))
        }
        return commit(next) ? fresh.map(\.id) : []
    }

    // MARK: - 記録と技

    /// 記した体験で使った技を、記録に結ぶ (身についた技だけ。空なら外す)
    public func link(entry entryID: UUID, skills ids: [String]) {
        let current = tree()
        var unique: [String] = []
        for id in ids where current.node(id)?.isGrowable == true && current.state(of: id) == .learned && !unique.contains(id) {
            unique.append(id)
        }
        var next = garden
        next.uses.removeAll { $0.entryID == entryID }
        if !unique.isEmpty { next.uses.append(SkillUse(entryID: entryID, skills: unique)) }
        guard next != garden else { return }
        _ = commit(next)
    }

    /// 体験帳から記録を消したとき、その記録と技の結びも外す
    public func forget(entry entryID: UUID) {
        guard garden.uses.contains(where: { $0.entryID == entryID }) else { return }
        var next = garden
        next.uses.removeAll { $0.entryID == entryID }
        _ = commit(next)
    }

    // MARK: - はじめて 4.0 を開いたとき

    /// 3.0 から来たときに一度だけ見せる「これまでの体験から育っていたもの」。見せるものが無ければ nil
    public func welcome() -> GrowthReport? {
        guard !garden.seen else { return nil }
        let report = GrowthReport.since(nothing: tree())
        return report.rankUps.isEmpty && report.flashes.isEmpty ? nil : report
    }

    /// 見届けた (次からは「これまでの体験から」を見せない)
    public func markSeen() {
        guard !garden.seen else { return }
        var next = garden
        next.seen = true
        _ = commit(next)
    }

    // MARK: - 編む・結ぶ

    /// 自分で名づけた技を、樹に植える (伸ばすには、ほかの技と同じく芽を使う)
    @discardableResult
    public func weave(_ draft: WeaveDraft) throws -> PersonalNode {
        let elements = Array(content.knownElements(draft.elements).prefix(WeaveDraft.elementLimit + 1))
        var checked = draft
        checked.elements = elements
        if let problem = checked.problems(existingTitles: existingTitles()).first { throw WeaveError.invalid(problem) }
        let node = PersonalNode(
            id: PersonalNode.makeID(kind: .woven), kind: .woven, title: WeaveDraft.trim(draft.title),
            invitation: WeaveDraft.trim(draft.practice), perspective: WeaveDraft.trim(draft.ability), elements: elements,
            growsFrom: validParent(draft.growsFrom, excluding: nil), createdAt: now()
        )
        var next = garden
        next.nodes.append(node)
        guard commit(next) else { throw AppError.storage }
        return node
    }

    /// 編んだ技を書き直す
    public func revise(_ id: String, with draft: WeaveDraft) throws {
        guard let index = garden.nodes.firstIndex(where: { $0.id == id }), garden.nodes[index].kind == .woven else { return }
        let elements = Array(content.knownElements(draft.elements).prefix(WeaveDraft.elementLimit + 1))
        var checked = draft
        checked.elements = elements
        if let problem = checked.problems(existingTitles: existingTitles(excluding: id)).first { throw WeaveError.invalid(problem) }
        var next = garden
        next.nodes[index].title = WeaveDraft.trim(draft.title)
        next.nodes[index].perspective = WeaveDraft.trim(draft.ability)
        next.nodes[index].invitation = WeaveDraft.trim(draft.practice)
        next.nodes[index].elements = elements
        next.nodes[index].growsFrom = validParent(draft.growsFrom, excluding: id)
        guard commit(next) else { throw AppError.storage }
    }

    /// 編んだ技を手放す (使った芽は戻る。体験帳の記録は残る)
    public func remove(_ id: String) throws {
        guard garden.node(id) != nil else { return }
        var next = garden
        next.nodes.removeAll { $0.id == id }
        next.ties.removeAll { $0.a == id || $0.b == id }
        next.learned.removeAll { $0.id == id }
        for i in next.uses.indices { next.uses[i].skills.removeAll { $0 == id } }
        next.uses.removeAll { $0.skills.isEmpty }
        for i in next.nodes.indices where next.nodes[i].growsFrom == id {
            next.nodes[i].growsFrom = nil
        }
        guard commit(next) else { throw AppError.storage }
    }

    /// 2つの技を結ぶ。すでに結んであれば何もしない。新しく閃いた技の id を返す
    @discardableResult
    public func tie(_ first: String, _ second: String, note: String? = nil) throws -> [String] {
        let current = tree()
        guard first != second, let a = current.node(first), let b = current.node(second), !a.isRoot, !b.isRoot else { return [] }
        if garden.ties.contains(where: { $0.connects(first, second) }) { return [] }
        var next = garden
        next.ties.append(Tie(between: first, and: second, note: note, createdAt: now()))
        guard commit(next) else { throw AppError.storage }
        return settle()
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

    /// 見本の体験帳と自分の樹を植える (プレビュー・UIテスト用。いまの体験帳に見本の記録を足す)
    public func plantSamples() {
        let date = now()
        let samples = HistoryEntry.sampleJournal(now: date, calendar: calendar)
            + HistoryEntry.sampleLived(now: date, calendar: calendar, content: content)
        for entry in samples { try? history.add(entry) }
        let entries = history.entries(since: nil, limit: nil)
        _ = commit(Garden.sample(entries: entries, content: content, book: book, now: date, calendar: calendar))
        settle()
    }

    // MARK: - きっかけを、樹の上に置く

    /// きっかけ (提案) として始める体験に、要素を補う。
    /// ライブラリの体験と、編んだ技の稽古はその id を残す (記すと、その体験を稽古にしている技に数える)
    public func place(_ experience: Experience) -> Experience {
        let elements = ElementClassifier.elements(of: experience, content: content)
        if let id = experience.nodeID, let item = content.experience(id) {
            return experience.placed(nodeID: id, elements: item.elements, growsFrom: experience.growsFrom)
        }
        if let id = experience.nodeID, let node = garden.node(id), node.kind == .woven {
            return experience.placed(nodeID: id, elements: content.knownElements(node.elements), growsFrom: nil)
        }
        if let item = content.experience(titled: experience.title) {
            return experience.placed(nodeID: item.id, elements: item.elements, growsFrom: experience.growsFrom)
        }
        return experience.placed(nodeID: nil, elements: elements, growsFrom: nil)
    }

    // MARK: - 内部

    /// 編む技に使えない名前 (技の樹の技・閃き・ほかの編んだ技)
    func existingTitles(excluding id: String? = nil) -> Set<String> {
        Set(book.skills.map(\.name)).union(garden.wovenNodes.filter { $0.id != id }.map(\.title))
    }

    /// 伸ばす元として使える技 (根・自分自身・閃きは除く)
    private func validParent(_ id: String?, excluding own: String?) -> String? {
        guard let id, id != own else { return nil }
        if let skill = book.skill(id), skill.kind != .flash { return id }
        if garden.node(id)?.kind == .woven { return id }
        return nil
    }

    private func commit(_ next: Garden) -> Bool {
        var value = next
        value.version = Garden.currentVersion
        do {
            try store.save(value)
            garden = value
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

/// きっかけや体験中の体験が、樹のどこにつながっているか
public struct Lineage: Equatable, Sendable {
    /// 樹の上でひらく節 (稽古のもとになる技。名前を明かせないときは要素の根)
    public let nodeID: String?
    /// 要素 (先頭が主な要素)
    public let elements: [ExperienceElement]
    /// 稽古のもとになる技の名前 (霧の中の技なら nil)
    public let skillTitle: String?
    /// 稽古のもとになる技の様子
    public let skillState: NodeState?
    /// ライブラリに無い (AIが新しく作った) 体験
    public let isNew: Bool

    public init(nodeID: String?, elements: [ExperienceElement], skillTitle: String?, skillState: NodeState?, isNew: Bool) {
        self.nodeID = nodeID
        self.elements = elements
        self.skillTitle = skillTitle
        self.skillState = skillState
        self.isNew = isNew
    }

    /// 「見る · 休む」
    public var elementText: String { elements.map(\.label).joined(separator: " · ") }

    /// カードに添える一行
    public var sentence: String {
        if let skillTitle {
            switch skillState {
            case .learned: return "身についた技「\(skillTitle)」の稽古"
            case .ready: return "育てられる技「\(skillTitle)」の稽古"
            default: return "技「\(skillTitle)」の稽古"
            }
        }
        if isNew { return "新しい体験 — 記すと、触れた要素に経験が積もります" }
        return elements.first.map { "「\($0.label)」の稽古" } ?? "体験"
    }
}

extension TreeSource {
    /// 体験が樹のどこにつながっているか (霧の中の技の名前は明かさない)
    public func lineage(of experience: Experience, in tree: ExperienceTree? = nil) -> Lineage {
        let tree = tree ?? self.tree()
        let elementIDs = ElementClassifier.elements(of: experience, content: content)
        let elements = elementIDs.compactMap { content.element($0) }
        let id = experience.nodeID ?? content.experience(titled: experience.title)?.id
        let owner = id.flatMap { tree.skills(practicing: $0).first }
        let visible = owner.flatMap { tree.state(of: $0.id) == .unknown ? nil : $0 }
        let isLibrary = id.map { content.experience($0) != nil || tree.node($0)?.kind == .woven } ?? false
        return Lineage(
            nodeID: visible?.id ?? elementIDs.first.map { ExperienceTree.rootID($0) },
            elements: elements,
            skillTitle: visible?.title,
            skillState: visible.map { tree.state(of: $0.id) },
            isNew: !isLibrary
        )
    }
}
