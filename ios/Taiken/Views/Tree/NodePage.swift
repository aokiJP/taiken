import SwiftUI
import TaikenCore

/// 技のページへの道しるべ
struct NodeRoute: Identifiable, Hashable {
    let id: String
}

/// 技のページをシートで開く。中で、となりの技へ渡っていける (ノートからノートへ渡るように)
struct NodePageSheet: View {
    let model: TreeViewModel
    let route: NodeRoute
    let start: @MainActor (Experience) -> Void
    let showOnTree: @MainActor (String) -> Void
    let close: @MainActor () -> Void

    var body: some View {
        NavigationStack {
            NodePage(model: model, id: route.id, start: start, showOnTree: showOnTree, close: close)
                .navigationDestination(for: NodeRoute.self) { next in
                    NodePage(model: model, id: next.id, start: start, showOnTree: showOnTree, close: close)
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Palette.paper)
    }
}

/// 技の1ページ (根なら、要素の1ページ)
struct NodePage: View {
    let model: TreeViewModel
    let id: String
    let start: @MainActor (Experience) -> Void
    let showOnTree: @MainActor (String) -> Void
    let close: @MainActor () -> Void

    @State private var weaving: WeaveRoute?
    @State private var tying = false
    @State private var confirmsRemoval = false
    @State private var confirmsLearn = false
    @State private var learnedNow = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let node = model.node(id) {
                if node.isRoot {
                    elementPage(node)
                } else {
                    skillPage(node)
                }
            } else {
                ContentUnavailableView(
                    "この技は、樹から外れました",
                    systemImage: "leaf",
                    description: Text("体験帳の記録は残っています。")
                )
            }
        }
        .background(Palette.paper.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("閉じる", action: close)
                    .tint(Palette.ink)
            }
        }
        .sheet(item: $weaving) { route in
            WeaveSheet(model: model, route: route)
        }
        .sheet(isPresented: $tying) {
            TieSheet(model: model, nodeID: id)
        }
        .sensoryFeedback(.impact(weight: .heavy, intensity: 0.9), trigger: learnedNow)
    }

    // MARK: - 技のページ

    private func skillPage(_ node: TreeNode) -> some View {
        let state = model.state(of: node.id)
        let glyph = model.tree.glyph(of: node)
        let check = model.tree.check(node.id)
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                skillHeader(node, state: state, glyph: glyph)
                lineage(node)

                if state == .unknown {
                    LinedBox {
                        Text(fogText(node))
                            .font(Typeface.mincho(16))
                            .lineSpacing(5)
                            .foregroundStyle(Palette.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text(node.ability)
                        .font(.invitation)
                        .lineSpacing(7)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if node.kind == .flash, let found = node.found {
                    LinedBox {
                        VStack(alignment: .leading, spacing: 6) {
                            MiniHead("閃いたとき")
                            Text(found)
                                .font(Typeface.mincho(16))
                                .foregroundStyle(Palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if state != .learned, state != .unknown, let requirement = model.tree.requirement(of: node.id) {
                    RequirementBox(requirement: requirement)
                }

                if state == .learned, let mastery = model.tree.mastery(of: node.id) {
                    MasteryBox(mastery: mastery, uses: model.tree.life(of: node.id)?.uses ?? 0, steps: model.tree.book.mastery)
                }

                actions(node, state: state, check: check)
                practices(node)
                relations("ここから伸びる", model.opens(from: node.id))
                relations("ここから来た", model.leadsHere(to: node.id))
                ties(node)
                records(node, glyph: glyph)
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .navigationTitle(model.displayTitle(of: node))
        .confirmationDialog("「\(node.title)」を樹から手放しますか？", isPresented: $confirmsRemoval, titleVisibility: .visible) {
            Button("手放す", role: .destructive) {
                model.remove(node.id)
                close()
            }
        } message: {
            Text("使った芽は戻ります。結んだ糸はほどけます。体験帳の記録は残ります。")
        }
        .confirmationDialog("「\(node.title)」へ伸ばしますか？", isPresented: $confirmsLearn, titleVisibility: .visible) {
            Button(learnTitle(check)) {
                if model.learn(node.id) {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.55)) { learnedNow.toggle() }
                }
            }
        } message: {
            Text(node.ability)
        }
    }

    private func skillHeader(_ node: TreeNode, state: NodeState, glyph: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    ForEach(node.elements, id: \.self) { elementID in
                        if let element = model.tree.element(elementID) {
                            HStack(spacing: 5) {
                                ElementMark(glyph: element.glyph, size: 18)
                                Text(element.label)
                                    .font(.caption)
                                    .foregroundStyle(Palette.ink2)
                            }
                        }
                    }
                    if let kind = node.kindLabel, state != .unknown {
                        KindTag(text: kind)
                    }
                }
                .accessibilityElement(children: .combine)
                Text(model.displayTitle(of: node))
                    .font(.displayTitle)
                    .foregroundStyle(state == .unknown ? Palette.ink3 : Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if state != .unknown, !node.reading.isEmpty, node.reading != node.title {
                    Text(node.reading)
                        .font(.caption)
                        .foregroundStyle(Palette.ink3)
                }
                Text(model.caption(of: node.id))
                    .font(.footnote)
                    .foregroundStyle(state == .learned ? Palette.shu : Palette.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Group {
                if state == .learned {
                    SealView(character: glyph, size: 64, style: .filled, rotation: node.kind == .flash ? 45 : -6)
                        .scaleEffect(learnedNow && !reduceMotion ? 1.06 : 1)
                } else if state == .unknown {
                    SealView(character: "？", size: 56, style: .ghost, rotation: 0)
                } else {
                    SealView(character: glyph, size: 56, style: .ghost, rotation: 0)
                }
            }
        }
    }

    /// 霧の中の技: どこにあるかだけを書く
    private func fogText(_ node: TreeNode) -> String {
        let near = node.after.compactMap { model.node($0) }.filter { model.state(of: $0.id) != .unknown }
        if let first = near.first {
            return "この技は、まだ霧の中にあります。「\(first.title)」が身につくと、名前と条件が見えてきます。"
        }
        return "この技は、まだ霧の中にあります。近くの技が身につくと、名前と条件が見えてきます。"
    }

    /// 要素の根から、この技までの道すじ
    @ViewBuilder
    private func lineage(_ node: TreeNode) -> some View {
        let path = Array(model.path(to: node.id).dropLast())
        if !path.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(path) { step in
                        NavigationLink(value: NodeRoute(id: step.id)) {
                            Text(model.displayTitle(of: step))
                                .font(.caption)
                                .foregroundStyle(Palette.ink2)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Palette.wash, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        Image(systemName: "chevron.compact.right")
                            .font(.caption2)
                            .foregroundStyle(Palette.ink3)
                            .accessibilityHidden(true)
                    }
                    Text(model.displayTitle(of: node))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.ink)
                }
            }
            .scrollIndicators(.hidden)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("根からの道すじ")
        }
    }

    // MARK: - すること

    private func actions(_ node: TreeNode, state: NodeState, check: LearnCheck) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            switch check {
            case .available:
                Button("伸ばす") { confirmsLearn = true }
                    .buttonStyle(ShuButtonStyle())
                    .accessibilityIdentifier("node.learn")
            case .needsSprout(let elements):
                Label(sproutHint(elements), systemImage: "leaf")
                    .font(.footnote)
                    .foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            default:
                EmptyView()
            }
            HStack(spacing: 10) {
                if state == .learned, node.isGrowable {
                    Button {
                        weaving = WeaveRoute(growsFrom: node.id, elements: [node.primaryElement])
                    } label: {
                        Label("ここから技を編む", systemImage: "arrow.up.right")
                    }
                    .buttonStyle(QuietButtonStyle(compact: true))
                }
                if state == .learned, !model.tieCandidates(for: node.id).isEmpty {
                    Button {
                        tying = true
                    } label: {
                        Label("結ぶ", systemImage: "link")
                    }
                    .buttonStyle(QuietButtonStyle(compact: true))
                    .accessibilityIdentifier("node.tie")
                }
            }
            HStack(spacing: 18) {
                Button {
                    showOnTree(node.id)
                } label: {
                    Label("樹の上で見る", systemImage: "scope")
                }
                if node.kind == .woven {
                    Button("書き直す") {
                        weaving = WeaveRoute(revising: node.id)
                    }
                    Button("手放す") { confirmsRemoval = true }
                }
                Spacer(minLength: 0)
            }
            .font(.footnote)
            .foregroundStyle(Palette.ink2)
            .buttonStyle(.plain)
            .padding(.top, 2)
            if let message = model.errorMessage {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(Palette.shu)
            }
        }
    }

    private func learnTitle(_ check: LearnCheck) -> String {
        if case .available(let charge) = check, let element = model.tree.element(charge) {
            return "\(element.quoted)の芽を使って伸ばす"
        }
        return "伸ばす"
    }

    private func sproutHint(_ elements: [String]) -> String {
        let names = elements.compactMap { model.tree.element($0)?.quoted }.joined(separator: "か")
        return "条件はそろっています。\(names)の段が上がると芽が出て、伸ばせます。"
    }

    // MARK: - 稽古

    @ViewBuilder
    private func practices(_ node: TreeNode) -> some View {
        let items = model.practices(of: node.id)
        if !items.isEmpty || node.practiceText != nil {
            VStack(alignment: .leading, spacing: 10) {
                MiniHead("稽古")
                Text("この技の見方で、いつもの一日を過ごす入口です。やってもやらなくても、技は減りません。")
                    .font(.caption)
                    .foregroundStyle(Palette.ink3)
                    .fixedSize(horizontal: false, vertical: true)
                if let own = node.practiceText {
                    PracticeRow(title: "自分の稽古", invitation: own) {
                        if let experience = node.ownPractice() { start(experience) }
                    }
                }
                ForEach(items) { item in
                    PracticeRow(title: item.title, invitation: item.invitation) {
                        start(item.asExperience(reason: "技「\(node.title)」の稽古です。"))
                    }
                }
            }
        }
    }

    // MARK: - となりの技

    @ViewBuilder
    private func relations(_ title: String, _ items: [TreeViewModel.Relation]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                MiniHead(title)
                    .padding(.bottom, 4)
                ForEach(items) { item in
                    NavigationLink(value: NodeRoute(id: item.node.id)) {
                        NodeRow(model: model, node: item.node, detail: item.kind.label)
                    }
                    .buttonStyle(.plain)
                    Rectangle().fill(Palette.line).frame(height: 1)
                }
            }
        }
    }

    @ViewBuilder
    private func ties(_ node: TreeNode) -> some View {
        let items = model.tied(to: node.id)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                MiniHead("結んだ技")
                    .padding(.bottom, 4)
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 0) {
                        NavigationLink(value: NodeRoute(id: item.node.id)) {
                            NodeRow(model: model, node: item.node, detail: "結び")
                        }
                        .buttonStyle(.plain)
                        if let note = item.note {
                            HStack(spacing: 8) {
                                Rectangle().fill(Palette.shu).frame(width: 14, height: 1.5)
                                Text(note)
                                    .font(Typeface.mincho(14))
                                    .foregroundStyle(Palette.ink)
                            }
                            .padding(.bottom, 10)
                        }
                    }
                    .contextMenu {
                        Button("糸をほどく", systemImage: "scissors", role: .destructive) { model.untie(item.link) }
                    }
                    .accessibilityAction(named: "糸をほどく") { model.untie(item.link) }
                    Rectangle().fill(Palette.line).frame(height: 1)
                }
                Text("長押しで、糸をほどけます。")
                    .font(.caption2)
                    .foregroundStyle(Palette.ink3)
                    .padding(.top, 6)
            }
        }
    }

    /// この技とともにあった体験 (稽古から始めたもの・自分で「使った」と選んだもの)
    @ViewBuilder
    private func records(_ node: TreeNode, glyph: String) -> some View {
        if let life = model.tree.life(of: node.id), !life.entries.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                MiniHead("この技とともにあった体験")
                ForEach(life.entries) { entry in
                    EntryLine(entry: entry, glyph: glyph)
                }
            }
        }
    }

    // MARK: - 要素のページ (根)

    private func elementPage(_ node: TreeNode) -> some View {
        let progress = model.tree.progress(of: node.primaryElement)
        let element = model.tree.element(node.primaryElement)
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(text: "要素の根")
                        Text(node.title)
                            .font(.displayTitle)
                            .foregroundStyle(Palette.ink)
                            .accessibilityAddTraits(.isHeader)
                        Text(element?.hint ?? node.ability)
                            .font(.footnote)
                            .foregroundStyle(Palette.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    ElementMark(glyph: element?.glyph ?? "", size: 58, color: Palette.ink)
                }

                RankPanel(progress: progress)

                let skills = model.tree.nodes(inElement: node.primaryElement)
                if !skills.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        MiniHead("この要素の技")
                            .padding(.bottom, 4)
                        ForEach(skills) { skill in
                            NavigationLink(value: NodeRoute(id: skill.id)) {
                                NodeRow(model: model, node: skill, depth: max(0, model.depth(of: skill.id) - 1))
                            }
                            .buttonStyle(.plain)
                            Rectangle().fill(Palette.line).frame(height: 1)
                        }
                    }
                }

                practices(node)

                let entries = model.entries(touching: node.primaryElement)
                if !entries.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        MiniHead("この要素に触れた体験")
                        ForEach(entries) { entry in
                            EntryLine(entry: entry, glyph: element?.glyph ?? entry.sealCharacter)
                        }
                    }
                }

                Button {
                    showOnTree(node.id)
                } label: {
                    Label("樹の上で見る", systemImage: "scope")
                        .font(.footnote)
                        .foregroundStyle(Palette.ink2)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .navigationTitle(node.title)
    }
}

// MARK: - 部品

/// 段と、次の段までの経験と、芽
struct RankPanel: View {
    let progress: ElementProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(Ranks.label(progress.rank))
                    .font(Typeface.mincho(26, bold: true, relativeTo: .title))
                    .foregroundStyle(Palette.ink)
                Text("経験 \(progress.experience)")
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Palette.ink2)
                Spacer(minLength: 0)
                if progress.sprouts > 0 {
                    Label("芽 \(progress.sprouts)", systemImage: "leaf.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.shu)
                }
            }
            ExperienceGauge(gained: progress.gained, span: progress.span)
            Text(progress.rank == 0
                ? "記した体験がこの要素に触れると、経験が積もります。一つで一段です。"
                : "次の段まで、あと\(progress.remaining)。段が上がるたびに、芽がひとつ出ます。")
                .font(.caption)
                .foregroundStyle(Palette.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Palette.wash, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// 次の段までの経験を、小さな升目で (数を競うためではなく、いまの位置を知るため)
struct ExperienceGauge: View {
    let gained: Int
    let span: Int
    var height: CGFloat = 6

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<max(span, 1), id: \.self) { index in
                Capsule()
                    .fill(index < gained ? Palette.ink : Palette.line)
                    .frame(height: height)
            }
        }
        .accessibilityHidden(true)
    }
}

/// 届く条件: 段と、先にあるとよい技。そろったものに印
struct RequirementBox: View {
    let requirement: Requirement

    var body: some View {
        LinedBox {
            VStack(alignment: .leading, spacing: 8) {
                MiniHead("届く条件")
                ForEach(requirement.ranks, id: \.element.id) { need in
                    conditionRow(
                        met: need.isMet,
                        text: "\(need.element.label) \(Ranks.label(need.need))",
                        detail: "いま\(Ranks.label(need.have))"
                    )
                }
                if let after = requirement.afterText {
                    conditionRow(
                        met: requirement.afterEnough,
                        text: after + "が身についていること",
                        detail: requirement.needs > 1 ? "いま\(Ranks.kanji(requirement.afterMet))つ" : nil
                    )
                }
            }
        }
    }

    private func conditionRow(met: Bool, text: String, detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(met ? Palette.ink : Palette.ink3)
                .font(.footnote)
            Text(text)
                .font(.footnote)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Palette.ink3)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(met ? "そろっています" : "まだです")
    }
}

/// 身についた技の深まり: 守 → 破 → 離
struct MasteryBox: View {
    let mastery: Mastery
    let uses: Int
    let steps: SkillBook.MasterySteps

    var body: some View {
        LinedBox {
            VStack(alignment: .leading, spacing: 10) {
                MiniHead("深まり")
                HStack(spacing: 14) {
                    ForEach(Mastery.allCases, id: \.self) { stage in
                        VStack(spacing: 4) {
                            SealView(
                                character: stage.glyph, size: 30, style: stage <= mastery ? .filled : .ghost,
                                rotation: stage <= mastery ? -4 : 0
                            )
                            Text(stage.meaning)
                                .font(.system(size: 9))
                                .foregroundStyle(stage == mastery ? Palette.ink : Palette.ink3)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .frame(width: 72)
                        }
                    }
                }
                Text(nextText)
                    .font(.caption)
                    .foregroundStyle(Palette.ink3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("深まり \(mastery.glyph)、\(mastery.meaning)")
    }

    private var nextText: String {
        switch mastery {
        case .shu: "稽古や、使った体験が\(steps.ha)つになると「破」に。いまは\(uses)つ。"
        case .ha: "稽古や、使った体験が\(steps.ri)つになると「離」に。いまは\(uses)つ。"
        case .ri: "もう、あなたのもの。これからも、使うたびに記録が重なります (いま\(uses)つ)。"
        }
    }
}

/// 稽古の1行: 名前・誘いかけ・やってみる
struct PracticeRow: View {
    let title: String
    let invitation: String
    let start: @MainActor () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.experienceTitle)
                    .foregroundStyle(Palette.ink)
                Text(invitation)
                    .font(.caption)
                    .foregroundStyle(Palette.ink2)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Button("やってみる", action: start)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Palette.shu)
                .buttonStyle(.plain)
                .accessibilityIdentifier("node.practice")
        }
        .padding(12)
        .background(Palette.wash, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// 記録の1行 (日付・名前・ひとこと)
struct EntryLine: View {
    let entry: HistoryEntry
    let glyph: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SealView(
                character: glyph, size: 26, style: entry.status == .completed ? .outlined : .ghost,
                rotation: Double(Calendar.current.component(.day, from: entry.createdAt) % 5) - 3
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.createdAt.formatted(.dateTime.year().month().day().weekday(.abbreviated)))
                    .font(.caption)
                    .foregroundStyle(Palette.ink3)
                Text(entry.title)
                    .font(Typeface.mincho(15))
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let note = entry.note {
                    Text("「\(note)」")
                        .font(Typeface.mincho(14))
                        .foregroundStyle(Palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 行

/// 一覧・つながりの1行: 様子の印・名前・できるようになること
struct NodeRow: View {
    let model: TreeViewModel
    let node: TreeNode
    var depth: Int = 0
    /// 右に添える言葉 (つながりの種類など)。無ければ様子
    var detail: String?

    var body: some View {
        let state = model.state(of: node.id)
        let growable: Bool = {
            if case .available = model.tree.check(node.id) { return true }
            return false
        }()
        return HStack(alignment: .center, spacing: 12) {
            NodeStateMark(
                state: state, kind: node.kind, glyph: model.tree.glyph(of: node), mastery: model.tree.mastery(of: node.id),
                growable: growable, size: 24
            )
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(model.displayTitle(of: node))
                        .font(.experienceTitle)
                        .foregroundStyle(state == .unknown ? Palette.ink3 : Palette.ink)
                        .lineLimit(1)
                    if let kind = node.kindLabel, state != .unknown {
                        KindTag(text: kind)
                    }
                }
                if state != .unknown {
                    Text(node.ability)
                        .font(.caption)
                        .foregroundStyle(Palette.ink2)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if let text = detail ?? (growable ? "伸ばせる" : (state.label.isEmpty ? nil : state.label)) {
                Text(text)
                    .font(.caption2)
                    .foregroundStyle(state == .learned || growable ? Palette.shu : Palette.ink3)
            }
            Image(systemName: "chevron.right")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Palette.ink3)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .padding(.leading, CGFloat(min(depth, 3)) * 14)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("技のページをひらきます")
    }
}

/// 「奥義」「渡り技」「閃き」「編んだ技」の小さな札
struct KindTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(Palette.ink2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 1))
    }
}
