import Foundation

/// 技の樹の1つの節。根 (要素) と、技 (身につく感覚や力)。
/// 節は「やること」ではない。自分で記した体験から段が上がり、芽を使って伸ばすと身につく。
public struct TreeNode: Identifiable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// 要素の根 (段がここに刻まれる)
        case root
        /// 一の技・二の技
        case art
        /// 奥義
        case secret
        /// 渡り技 (ふたつの要素のあいだ)
        case cross
        /// 閃き (身につくまで樹に出ない)
        case flash
        /// 自分で名づけて編んだ技
        case woven
    }

    public let id: String
    public let kind: Kind
    public let title: String
    /// 名前の読み (無ければ空)
    public let reading: String
    /// 身につくと、できるようになること
    public let ability: String
    /// 閃き: 閃いたときのこと
    public let found: String?
    /// 要素の id (先頭が主な要素。必ず1つ以上)
    public let elements: [String]
    /// 先にあるとよい技
    public let after: [String]
    /// after のうち、いくつ身についていればよいか
    public let needs: Int
    /// 要素ごとに要る段
    public let rank: [String: Int]
    /// 稽古 (体験ライブラリの id)
    public let practice: [String]
    /// 編んだ技の、自分で書いた稽古
    public let practiceText: String?
    /// 記した言葉から、この技を使ったかもしれないと推し量る手がかり
    public let keywords: [String]

    public init(
        id: String, kind: Kind, title: String, reading: String = "", ability: String, found: String? = nil,
        elements: [String], after: [String] = [], needs: Int = 0, rank: [String: Int] = [:], practice: [String] = [],
        practiceText: String? = nil, keywords: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.reading = reading
        self.ability = ability
        self.found = found
        self.elements = elements
        self.after = after
        self.needs = needs
        self.rank = rank
        self.practice = practice
        self.practiceText = practiceText
        self.keywords = keywords
    }

    public var primaryElement: String { elements.first ?? "see" }
    public var isRoot: Bool { kind == .root }
    public var isPersonal: Bool { kind == .woven }
    /// 芽を使って伸ばす技か (根と閃きは伸ばさない)
    public var isGrowable: Bool { kind != .root && kind != .flash }

    /// 「奥義」「渡り技」「閃き」「編んだ技」のような小さな札 (一の技・二の技は札なし)
    public var kindLabel: String? {
        switch kind {
        case .secret: "奥義"
        case .cross: "渡り技"
        case .flash: "閃き"
        case .woven: "編んだ技"
        case .root, .art: nil
        }
    }

    /// 編んだ技の稽古を、きっかけとして始めるときの形
    public func ownPractice() -> Experience? {
        guard let text = practiceText?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return Experience(
            title: title, perspective: ability, invitation: text, reason: "自分で編んだ技「\(title)」の稽古です。",
            difficulty: .low, tags: [], reflectionQuestion: nil, nodeID: id, elements: elements
        )
    }
}

/// 節から節へのつながり
public struct TreeLink: Hashable, Sendable {
    public enum Kind: String, Sendable {
        /// 同じ要素の中で伸びる (根から一の技、一の技から二の技 …)
        case branch
        /// 別の要素の技から渡る
        case cross
        /// 閃き (根から、ふっと現れる)
        case spark
        /// 自分で結んだ糸
        case tie

        public var label: String {
            switch self {
            case .branch: "伸びる"
            case .cross: "渡る"
            case .spark: "閃き"
            case .tie: "結び"
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

/// 樹の上での技の様子
public enum NodeState: String, Sendable, Equatable {
    /// 霧の中 (名前もまだ見えない)
    case unknown
    /// 気配 (名前と条件が見える。まだ届かない)
    case sensed
    /// 育てられる (条件がそろった。芽があれば伸ばせる)
    case ready
    /// 身についた
    case learned
}

/// その技とともにあった記録
public struct SkillLife: Sendable, Equatable {
    /// 稽古から始めた記録と、自分で「この技を使った」と選んだ記録 (新しい順)
    public let entries: [HistoryEntry]
    /// 身についた時刻
    public let learnedAt: Date?

    public init(entries: [HistoryEntry], learnedAt: Date?) {
        self.entries = entries
        self.learnedAt = learnedAt
    }

    public var uses: Int { entries.count }
}

/// 技に届くための条件 (いまの段・身についた技と並べて見せる)
public struct Requirement: Sendable, Equatable {
    public struct RankNeed: Sendable, Equatable {
        public let element: ExperienceElement
        public let need: Int
        public let have: Int
        public var isMet: Bool { have >= need }
    }

    public let ranks: [RankNeed]
    /// 先にあるとよい技
    public let after: [TreeNode]
    /// after のうち、いくつ身についていればよいか
    public let needs: Int
    /// after のうち、身についている数
    public let afterMet: Int

    public var ranksMet: Bool { ranks.allSatisfy(\.isMet) }
    public var afterEnough: Bool { afterMet >= needs }
    public var isMet: Bool { ranksMet && afterEnough }

    /// 「見る 三段」「考える 二段」
    public var rankText: String {
        ranks.map { "\($0.element.label) \(Ranks.label($0.need))" }.joined(separator: "・")
    }

    /// 「『遠目』『棚の外』『色を拾う』のうち2つ」「『目を留める』」
    public var afterText: String? {
        guard !after.isEmpty, needs > 0 else { return nil }
        let names = after.map { "「\($0.title)」" }.joined()
        if needs >= after.count { return names }
        if needs == 1 { return "\(names)のどれか" }
        return "\(names)のうち\(Ranks.kanji(needs))つ"
    }

    /// 樹の上に添える一文
    public var sentence: String {
        var parts: [String] = []
        if !ranks.isEmpty { parts.append(rankText) }
        if let afterText { parts.append(afterText + "が身についていること") }
        return parts.joined(separator: "、")
    }
}

/// 技を伸ばせるか
public enum LearnCheck: Sendable, Equatable {
    /// 伸ばせる (どの要素の芽を使うか)
    case available(charge: String)
    /// 条件はそろっているが、芽が無い (どの要素に段が上がれば芽が出るか)
    case needsSprout([String])
    /// まだ届かない
    case locked(Requirement)
    /// もう身についている
    case learned
    /// 根・閃きは伸ばさない
    case notGrowable
}

/// 技の樹。要素の根から、技が伸びていく。
/// 自分で記した体験が触れた要素に経験として積もり、段が上がるたびに芽が出る。どの技へ伸ばすかは自分で選ぶ。
public struct ExperienceTree: Sendable {
    public let content: TaikenContent
    public let book: SkillBook
    public let nodes: [TreeNode]
    public let links: [TreeLink]
    /// 技ごとの記録 (使った記録があるか、身についた技だけ)
    public let lives: [String: SkillLife]
    /// 要素の中での親 (根からたどった道。表示の配置と道すじに使う)
    public let parents: [String: String]
    /// 要素の根からの深さ (根 = 0)。閃きは持たない
    public let depths: [String: Int]
    /// 要素の中での子
    public let children: [String: [String]]
    /// 記録ごとの、その記録で育った技
    public let entrySkills: [UUID: [String]]
    /// まだ閃いていない閃きの数 (画面には数を出さない)
    public let hiddenFlashes: Int

    private let progressByElement: [String: ElementProgress]
    private let stateByID: [String: NodeState]
    private let learnedAtByID: [String: Date]
    private let index: [String: Int]
    private let outgoingIndex: [String: [Int]]
    private let incomingIndex: [String: [Int]]

    init(
        content: TaikenContent, book: SkillBook, nodes: [TreeNode], links: [TreeLink], lives: [String: SkillLife],
        parents: [String: String], depths: [String: Int], children: [String: [String]], entrySkills: [UUID: [String]],
        hiddenFlashes: Int, progress: [String: ElementProgress], states: [String: NodeState], learnedAt: [String: Date]
    ) {
        self.content = content
        self.book = book
        self.nodes = nodes
        self.links = links
        self.lives = lives
        self.parents = parents
        self.depths = depths
        self.children = children
        self.entrySkills = entrySkills
        self.hiddenFlashes = hiddenFlashes
        progressByElement = progress
        stateByID = states
        learnedAtByID = learnedAt
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
    }

    // MARK: - 引く

    /// 要素の根の id
    public static func rootID(_ elementID: String) -> String { "el-" + elementID }

    public func node(_ id: String) -> TreeNode? { index[id].map { nodes[$0] } }

    public var elements: [ExperienceElement] { content.elements }

    public func element(_ id: String) -> ExperienceElement? { content.element(id) }

    public func root(of elementID: String) -> TreeNode? { node(Self.rootID(elementID)) }

    /// 印の字 (主な要素の字。閃きは「閃」)
    public func glyph(of node: TreeNode) -> String {
        node.kind == .flash ? "閃" : ElementClassifier.glyph(for: node.elements, content: content)
    }

    public func state(of id: String) -> NodeState { stateByID[id] ?? .unknown }

    /// 要素の段と経験と芽
    public func progress(of elementID: String) -> ElementProgress {
        progressByElement[elementID] ?? ElementProgress(element: elementID, experience: 0, rank: 0, sprouts: 0)
    }

    /// すべての要素の段の合計 (樹の年輪)
    public var totalRank: Int { elements.reduce(0) { $0 + progress(of: $1.id).rank } }

    /// まだ使っていない芽の合計
    public var totalSprouts: Int { elements.reduce(0) { $0 + progress(of: $1.id).sprouts } }

    public func learnedAt(_ id: String) -> Date? { learnedAtByID[id] }

    public func life(of id: String) -> SkillLife? { lives[id] }

    /// 身についた技の深まり (根・閃き・まだ身についていない技は nil)
    public func mastery(of id: String) -> Mastery? {
        guard let node = node(id), node.isGrowable, state(of: id) == .learned else { return nil }
        return Mastery.of(uses: lives[id]?.uses ?? 0, steps: book.mastery)
    }

    /// 身についた技 (根を除く。最近身についたものから)
    public var learnedNodes: [TreeNode] {
        nodes.filter { !$0.isRoot && state(of: $0.id) == .learned }.sorted {
            (learnedAtByID[$0.id] ?? .distantPast) > (learnedAtByID[$1.id] ?? .distantPast)
        }
    }

    /// この要素の技 (主な要素がその要素のもの。根は除く)。浅いものから
    public func nodes(inElement elementID: String) -> [TreeNode] {
        nodes.filter { !$0.isRoot && $0.primaryElement == elementID }.sorted { lhs, rhs in
            (depth(of: lhs), index[lhs.id] ?? 0) < (depth(of: rhs), index[rhs.id] ?? 0)
        }
    }

    /// 根からの深さ (閃きはいちばん外)
    public func depth(of node: TreeNode) -> Int {
        if node.kind == .flash { return 9 }
        return depths[node.id] ?? 1
    }

    /// 技に届くための条件 (根・閃きは nil)
    public func requirement(of id: String) -> Requirement? {
        guard let node = node(id), node.isGrowable else { return nil }
        let ranks = node.rank.compactMap { key, need -> Requirement.RankNeed? in
            guard let element = content.element(key) else { return nil }
            return Requirement.RankNeed(element: element, need: need, have: progress(of: key).rank)
        }.sorted { (content.elementOrder($0.element.id) ?? 0) < (content.elementOrder($1.element.id) ?? 0) }
        let after = node.after.compactMap { self.node($0) }
        let met = after.filter { state(of: $0.id) == .learned }.count
        return Requirement(ranks: ranks, after: after, needs: min(node.needs, after.count), afterMet: met)
    }

    /// 伸ばせるか (伸ばせるなら、どの要素の芽を使うか)
    public func check(_ id: String) -> LearnCheck {
        guard let node = node(id) else { return .notGrowable }
        guard node.isGrowable else { return .notGrowable }
        if state(of: id) == .learned { return .learned }
        guard let requirement = requirement(of: id) else { return .notGrowable }
        guard requirement.isMet else { return .locked(requirement) }
        let candidates = content.knownElements(node.elements)
        if let charge = candidates.first(where: { progress(of: $0).sprouts > 0 }) { return .available(charge: charge) }
        return .needsSprout(candidates)
    }

    /// この要素の芽で、いま伸ばせる技
    public func learnable(inElement elementID: String) -> [TreeNode] {
        guard progress(of: elementID).sprouts > 0 else { return [] }
        return nodes.filter { node in
            node.isGrowable && node.elements.contains(elementID) && state(of: node.id) == .ready
        }
    }

    public func hasLearnable(inElement elementID: String) -> Bool { !learnable(inElement: elementID).isEmpty }

    /// 芽があって、伸ばせる技がある要素
    public var sproutingElements: [ExperienceElement] { elements.filter { hasLearnable(inElement: $0.id) } }

    /// この節から伸びる技 (結びは含まない)
    public func outgoing(from id: String) -> [TreeLink] {
        (outgoingIndex[id] ?? []).map { links[$0] }.filter { $0.kind != .tie }
    }

    /// この節へ至る節 (結びは含まない)
    public func incoming(to id: String) -> [TreeLink] {
        (incomingIndex[id] ?? []).map { links[$0] }.filter { $0.kind != .tie }
    }

    /// この技と結んだ糸
    public func ties(of id: String) -> [TreeLink] {
        let out = (outgoingIndex[id] ?? []).map { links[$0] }
        let into = (incomingIndex[id] ?? []).map { links[$0] }
        return (out + into).filter { $0.kind == .tie }
    }

    /// 根から、この技までの道すじ (根が先頭)
    public func path(to id: String) -> [TreeNode] {
        guard let target = node(id) else { return [] }
        if target.kind == .flash { return [root(of: target.primaryElement), target].compactMap { $0 } }
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

    /// この記録で育った技
    public func skills(usedIn entryID: UUID) -> [TreeNode] {
        (entrySkills[entryID] ?? []).compactMap { node($0) }
    }

    /// この体験 (ライブラリの id や、編んだ技の id) を稽古にしている技 (身についたもの → 育てられるもの → ほか)
    public func skills(practicing experienceID: String) -> [TreeNode] {
        var found = book.skills(practicing: experienceID).compactMap { node($0.id) }
        if let woven = node(experienceID), woven.kind == .woven { found.insert(woven, at: 0) }
        func order(_ node: TreeNode) -> Int {
            switch state(of: node.id) {
            case .learned: 0
            case .ready: 1
            case .sensed: 2
            case .unknown: 3
            }
        }
        return found.enumerated().sorted { (order($0.element), $0.offset) < (order($1.element), $1.offset) }.map(\.element)
    }

    /// 身についた技のうち、この要素に触れるもの (記すときに「使った技」として選ぶ)
    public func learnedSkills(touching elementIDs: [String]) -> [TreeNode] {
        let wanted = Set(elementIDs)
        return learnedNodes.filter { $0.isGrowable && !wanted.isDisjoint(with: $0.elements) }
    }

    /// 記した言葉と要素から、使ったかもしれない身についた技 (手がかりの言葉が入っているもの)
    public func suggestedSkills(for text: String, elements elementIDs: [String]) -> [TreeNode] {
        let words = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return [] }
        return learnedSkills(touching: elementIDs).filter { node in
            node.keywords.contains { !$0.isEmpty && words.contains($0) } || words.contains(node.title)
        }
    }

    /// 提案に添えて送る、樹のいま。
    /// lived = 記したことのある体験ライブラリの体験 (最近のものから)、buds = 身についた・育てられる技の稽古
    public func context(entries: [HistoryEntry], maxLived: Int = 12, maxBuds: Int = 16) -> TreeContext {
        var lived: [TreeContext.LivedNode] = []
        var seen = Set<String>()
        for entry in entries.sorted(by: { $0.createdAt > $1.createdAt }) where entry.status == .completed {
            guard let id = entry.nodeID, let item = content.experience(id), seen.insert(id).inserted else { continue }
            lived.append(TreeContext.LivedNode(id: id, title: item.title, elements: item.elements))
            if lived.count >= maxLived { break }
        }
        var buds: [String] = []
        var taken = Set<String>()
        let ready = nodes.filter { $0.isGrowable && state(of: $0.id) == .ready }
        for node in learnedNodes + ready {
            for id in node.practice where content.experience(id) != nil && taken.insert(id).inserted {
                buds.append(id)
            }
        }
        if buds.isEmpty {
            // まだ何も身についていなければ、要素の根にいちばん近い体験 (一の技の稽古) を少しずつ
            for element in elements {
                if let id = content.experience(element.root)?.id, taken.insert(id).inserted { buds.append(id) }
            }
        }
        return TreeContext(lived: lived, buds: Array(buds.prefix(maxBuds)))
    }
}

// MARK: - 組み立て

public enum TreeBuilder {
    /// 体験ライブラリ・技の樹・自分の樹 (身についた技・編んだ技・結び)・体験帳から、いまの樹を組み立てる
    public static func build(
        content: TaikenContent = .shared, book: SkillBook = .shared, garden: Garden, entries: [HistoryEntry],
        calendar: Calendar = .current
    ) -> ExperienceTree {
        // 1. 記した体験 (古い順) と、触れた要素
        let completed = entries.filter { $0.status == .completed }.sorted {
            ($0.finishedAt ?? $0.createdAt) < ($1.finishedAt ?? $1.createdAt)
        }
        let resolved: [(entry: HistoryEntry, elements: [String])] = completed.map {
            ($0, Array($0.resolvedElements(content: content).prefix(3)))
        }
        var experience: [String: Int] = [:]
        for item in resolved {
            for element in item.elements { experience[element, default: 0] += 1 }
        }

        // 2. 節: 要素の根 → 技の樹の技 → 自分で編んだ技
        var nodes: [TreeNode] = []
        var known = Set<String>()
        for element in content.elements {
            let id = ExperienceTree.rootID(element.id)
            known.insert(id)
            nodes.append(TreeNode(id: id, kind: .root, title: element.label, ability: element.hint, elements: [element.id]))
        }
        for skill in book.skills where skill.kind != .flash && content.element(skill.element) != nil {
            guard known.insert(skill.id).inserted else { continue }
            let kind: TreeNode.Kind = switch skill.kind {
            case .secret: .secret
            case .cross: .cross
            case .art, .flash: .art
            }
            nodes.append(TreeNode(
                id: skill.id, kind: kind, title: skill.name, reading: skill.reading, ability: skill.ability,
                elements: [skill.element] + content.knownElements(skill.also), after: skill.after, needs: skill.needs,
                rank: skill.rank, practice: skill.practice, keywords: skill.keywords
            ))
        }
        let skillIDs = known
        for woven in garden.wovenNodes where !known.contains(woven.id) {
            let elements = Array(content.knownElements(woven.elements).prefix(2))
            guard let primary = elements.first else { continue }
            known.insert(woven.id)
            let parent = woven.growsFrom.flatMap { id -> String? in
                guard id != woven.id, skillIDs.contains(id) || garden.node(id)?.kind == .woven else { return nil }
                return id.hasPrefix("el-") ? nil : id
            }
            nodes.append(TreeNode(
                id: woven.id, kind: .woven, title: woven.title, ability: woven.ability, elements: elements,
                after: parent.map { [$0] } ?? [], needs: parent == nil ? 0 : 1, rank: [primary: 1],
                practiceText: woven.invitation.isEmpty ? nil : woven.invitation
            ))
        }
        // 3.0 で編んだ技が、まだ知らない技から伸びていたら、根から伸ばす
        nodes = nodes.map { node in
            guard node.kind == .woven, let parent = node.after.first, !known.contains(parent) else { return node }
            return TreeNode(
                id: node.id, kind: .woven, title: node.title, ability: node.ability, elements: node.elements, rank: node.rank,
                practiceText: node.practiceText
            )
        }

        // 3. 身についた技 (芽を使った要素) と、記録と技
        var learnedAt: [String: Date] = [:]
        var charged: [String: Int] = [:]
        for record in garden.learned where known.contains(record.id) && learnedAt[record.id] == nil {
            learnedAt[record.id] = record.learnedAt
            if let element = record.element { charged[element, default: 0] += 1 }
        }
        let wovenIDs = Set(nodes.filter { $0.kind == .woven }.map(\.id))
        var useEntries: [String: [HistoryEntry]] = [:]
        var entrySkills: [UUID: [String]] = [:]
        for item in resolved {
            var ids = garden.skills(usedIn: item.entry.id).filter { known.contains($0) && !$0.hasPrefix("el-") }
            if let nodeID = item.entry.nodeID {
                for skill in book.skills(practicing: nodeID) where known.contains(skill.id) && !ids.contains(skill.id) {
                    ids.append(skill.id)
                }
                if wovenIDs.contains(nodeID) && !ids.contains(nodeID) { ids.append(nodeID) }
            }
            for id in ids { useEntries[id, default: []].append(item.entry) }
            if !ids.isEmpty { entrySkills[item.entry.id] = ids }
        }

        // 4. 段と芽
        var progress: [String: ElementProgress] = [:]
        var ranks: [String: Int] = [:]
        for element in content.elements {
            let value = experience[element.id] ?? 0
            let rank = Ranks.rank(for: value)
            ranks[element.id] = rank
            progress[element.id] = ElementProgress(
                element: element.id, experience: value, rank: rank, sprouts: max(0, rank - (charged[element.id] ?? 0))
            )
        }

        // 5. 離に届いた技と、その時刻 (閃きの条件に使う)
        var masteredAt: [Date] = []
        for (id, learned) in learnedAt {
            let uses = (useEntries[id] ?? []).map { $0.finishedAt ?? $0.createdAt }.sorted()
            guard uses.count >= book.mastery.ri else { continue }
            masteredAt.append(max(learned, uses[book.mastery.ri - 1]))
        }

        // 6. 閃き: 前に閃いたもの + いまの体験帳で条件を満たすもの
        let inputs = FlashEvaluator.Inputs(
            entries: resolved, ranks: ranks, elementIDs: content.elements.map(\.id), ties: garden.ties,
            masteredAt: masteredAt, calendar: calendar
        )
        var hidden = 0
        for flash in book.flashes where content.element(flash.element) != nil {
            let date: Date?
            if let record = garden.learned(flash.id) {
                date = record.learnedAt
            } else if let rule = flash.flash {
                date = FlashEvaluator.satisfied(rule, inputs: inputs)
            } else {
                date = nil
            }
            guard let date, known.insert(flash.id).inserted else {
                hidden += 1
                continue
            }
            learnedAt[flash.id] = date
            nodes.append(TreeNode(
                id: flash.id, kind: .flash, title: flash.name, reading: flash.reading, ability: flash.ability,
                found: flash.found, elements: [flash.element]
            ))
        }

        // 7. 様子
        var states: [String: NodeState] = [:]
        for node in nodes {
            switch node.kind {
            case .root:
                states[node.id] = (ranks[node.primaryElement] ?? 0) > 0 ? .learned : .ready
            case .flash:
                states[node.id] = .learned
            default:
                if learnedAt[node.id] != nil {
                    states[node.id] = .learned
                    continue
                }
                let ranksMet = node.rank.allSatisfy { (ranks[$0.key] ?? 0) >= $0.value }
                let met = node.after.filter { learnedAt[$0] != nil }.count
                let enough = met >= min(node.needs, node.after.filter { known.contains($0) }.count)
                if ranksMet && enough {
                    states[node.id] = .ready
                } else if node.after.isEmpty || met > 0 {
                    states[node.id] = .sensed
                } else {
                    states[node.id] = .unknown
                }
            }
        }

        // 8. つながり
        var primary: [String: String] = [:]
        for node in nodes { primary[node.id] = node.primaryElement }
        var links: [TreeLink] = []
        for node in nodes where node.kind != .root {
            let root = ExperienceTree.rootID(node.primaryElement)
            if node.kind == .flash {
                links.append(TreeLink(from: root, to: node.id, kind: .spark))
                continue
            }
            let parents = node.after.filter { known.contains($0) && $0 != node.id }
            if parents.isEmpty {
                links.append(TreeLink(from: root, to: node.id, kind: .branch))
                continue
            }
            for parent in parents {
                let kind: TreeLink.Kind = primary[parent] == node.primaryElement ? .branch : .cross
                links.append(TreeLink(from: parent, to: node.id, kind: kind))
            }
        }
        for tie in garden.ties where known.contains(tie.a) && known.contains(tie.b) && tie.a != tie.b {
            links.append(TreeLink(from: tie.a, to: tie.b, kind: .tie, note: tie.note, tieID: tie.id))
        }

        // 9. 配置のための木 (要素ごとに、根から同じ要素の枝だけをたどる)
        let (parents, depths, children) = spanning(content: content, nodes: nodes, links: links)

        // 10. 技ごとの記録
        var lives: [String: SkillLife] = [:]
        for node in nodes where node.kind != .root {
            let used = useEntries[node.id] ?? []
            guard !used.isEmpty || learnedAt[node.id] != nil else { continue }
            lives[node.id] = SkillLife(entries: used.sorted { $0.createdAt > $1.createdAt }, learnedAt: learnedAt[node.id])
        }

        return ExperienceTree(
            content: content, book: book, nodes: nodes, links: links, lives: lives, parents: parents, depths: depths,
            children: children, entrySkills: entrySkills, hiddenFlashes: hidden, progress: progress, states: states,
            learnedAt: learnedAt
        )
    }

    /// 要素ごとに、根から同じ要素の枝をたどった木。たどり着けない技は根に直接つなぐ。閃きは木に入れない
    static func spanning(content: TaikenContent, nodes: [TreeNode], links: [TreeLink]) -> ([String: String], [String: Int], [String: [String]]) {
        var parents: [String: String] = [:]
        var depths: [String: Int] = [:]
        var children: [String: [String]] = [:]
        var primary: [String: String] = [:]
        var kinds: [String: TreeNode.Kind] = [:]
        for node in nodes {
            primary[node.id] = node.primaryElement
            kinds[node.id] = node.kind
        }
        var outgoing: [String: [String]] = [:]
        for link in links where link.kind == .branch {
            outgoing[link.from, default: []].append(link.to)
        }

        for element in content.elements {
            let root = ExperienceTree.rootID(element.id)
            guard primary[root] != nil else { continue }
            depths[root] = 0
            var queue = [root]
            var head = 0
            while head < queue.count {
                let current = queue[head]
                head += 1
                for next in outgoing[current] ?? [] where primary[next] == element.id && depths[next] == nil && kinds[next] != .flash {
                    depths[next] = (depths[current] ?? 0) + 1
                    parents[next] = current
                    children[current, default: []].append(next)
                    queue.append(next)
                }
            }
        }
        for node in nodes where depths[node.id] == nil && node.kind != .flash {
            let root = ExperienceTree.rootID(node.primaryElement)
            guard depths[root] != nil, root != node.id else {
                depths[node.id] = 0
                continue
            }
            depths[node.id] = 1
            parents[node.id] = root
            children[root, default: []].append(node.id)
        }
        return (parents, depths, children)
    }
}
