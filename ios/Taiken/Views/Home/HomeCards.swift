import SwiftUI
import TaikenCore

// MARK: - 眺めているあいだ

/// きっかけを待つあいだ: 朱の三つの雫と、移り変わる一行
struct LoadingCard: View {
    @State private var line = 0
    private let lines = ["いつもの一日を眺めています…", "予定のすき間を探しています…", "きっかけをひとつ選んでいます…"]

    var body: some View {
        PaperCard {
            VStack(spacing: 16) {
                InkDrops()
                Text(lines[line % lines.count])
                    .font(Typeface.mincho(15))
                    .foregroundStyle(Palette.ink2)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.4), value: line)
            }
            .frame(maxWidth: .infinity, minHeight: 240)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.6))
                line += 1
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("きっかけを選んでいます")
    }
}

struct InkDrops: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 9) {
            ForEach(0..<3, id: \.self) { index in
                PhaseAnimator([false, true]) { on in
                    Circle()
                        .fill(Palette.shu)
                        .frame(width: 9, height: 9)
                        .scaleEffect(on ? 1 : 0.55)
                        .opacity(on ? 1 : 0.35)
                } animation: { _ in
                    reduceMotion ? nil : .easeInOut(duration: 0.6).delay(Double(index) * 0.18)
                }
            }
        }
    }
}

// MARK: - きっかけ (求められたときだけ)

/// きっかけ: AIや体験ライブラリからの、ひとつの提案。やらなくても何も減らない
struct ProposalCard: View {
    let response: ExperienceResponse
    /// このきっかけが、樹のどこにつながっているか
    let lineage: Lineage?
    let isLoading: Bool
    let openBranch: @MainActor (String?) -> Void
    let tryIt: @MainActor () -> Void
    let another: @MainActor () -> Void
    let notNow: @MainActor () -> Void
    let showInsight: @MainActor () -> Void
    @State private var showsReason = false

    private var experience: Experience { response.experience }

    var body: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Eyebrow(text: "きっかけ")
                    if let source = sourceLabel {
                        Text(source)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .foregroundStyle(Palette.ink2)
                            .background(Palette.line, in: Capsule())
                    }
                    Spacer()
                    Button(action: showInsight) {
                        Image(systemName: "info.circle")
                            .font(.body)
                            .foregroundStyle(Palette.ink3)
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(response.source.isGenerative ? "AIが見たこと" : "きっかけの手がかり")
                }

                Text(experience.invitation)
                    .font(.invitation)
                    .lineSpacing(7)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                    .inkReveal(delay: 0.05)

                Signature(title: experience.title)
                    .padding(.top, 14)
                    .inkReveal(delay: 0.28)

                Text(experience.perspective)
                    .font(.footnote)
                    .lineSpacing(4)
                    .foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                    .inkReveal(delay: 0.42)

                if let lineage {
                    BranchLine(lineage: lineage, open: openBranch)
                        .padding(.top, 12)
                        .inkReveal(delay: 0.5)
                }

                VStack(alignment: .leading, spacing: 0) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) { showsReason.toggle() }
                    } label: {
                        HStack {
                            Text("なぜ今？")
                            Spacer()
                            Image(systemName: "chevron.down")
                                .font(.caption.weight(.semibold))
                                .rotationEffect(.degrees(showsReason ? 180 : 0))
                        }
                        .font(.footnote)
                        .foregroundStyle(Palette.ink3)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(showsReason ? "開いています" : "閉じています")

                    if showsReason {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(experience.reason)
                                .font(.footnote)
                                .foregroundStyle(Palette.ink2)
                                .fixedSize(horizontal: false, vertical: true)
                            let labels = ExperienceTag.displayLabels(experience.tags)
                            if !labels.isEmpty {
                                HStack(spacing: 6) {
                                    ForEach(labels, id: \.self) { label in
                                        Text(label)
                                            .font(.caption2)
                                            .foregroundStyle(Palette.ink2)
                                            .padding(.horizontal, 9)
                                            .padding(.vertical, 4)
                                            .overlay(Capsule().strokeBorder(Palette.line, lineWidth: 1))
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                }
                .padding(.top, 8)

                VStack(spacing: 10) {
                    Button("やってみる", action: tryIt)
                        .buttonStyle(ShuButtonStyle())
                    HStack(spacing: 10) {
                        Button(action: another) {
                            HStack(spacing: 6) {
                                if isLoading {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "shuffle")
                                }
                                Text("別の視点")
                            }
                        }
                        .buttonStyle(QuietButtonStyle())
                        Button("今はやらない", action: notNow)
                            .buttonStyle(QuietButtonStyle())
                    }
                }
                .padding(.top, 16)
                .disabled(isLoading)
            }
        }
        .opacity(isLoading ? 0.6 : 1)
        .animation(.easeInOut(duration: 0.25), value: isLoading)
    }

    /// AIが生成したものではないときだけ、出所を小さく添える
    private var sourceLabel: String? {
        switch response.source {
        case .local, .fallback: "体験ライブラリ"
        case .onDevice: "端末内のAI"
        case .ai, .mock: nil
        }
    }
}

// MARK: - 体験中

struct ActiveCard: View {
    let entry: HistoryEntry
    let lineage: Lineage?
    let openBranch: @MainActor (String?) -> Void
    let finish: @MainActor () -> Void
    let abandon: @MainActor () -> Void
    let presenceChanged: @MainActor (Bool) -> Void
    @AppStorage(PresenceKey.enabled) private var presenceEnabled = true
    @State private var confirmsAbandon = false

    var body: some View {
        PaperCard(emphasized: true) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    SealView(character: entry.sealCharacter, size: 22, style: .filled, rotation: -6)
                    Eyebrow(text: "体験中", color: Palette.shu)
                    Spacer()
                    Text("\(entry.createdAt.formatted(date: .omitted, time: .shortened))に始めました")
                        .font(.caption)
                        .foregroundStyle(Palette.ink3)
                }

                Text(entry.invitation)
                    .font(.invitation)
                    .lineSpacing(7)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)

                Signature(title: entry.title)
                    .padding(.top, 14)

                if let lineage {
                    BranchLine(lineage: lineage, open: openBranch)
                        .padding(.top, 12)
                }

                if let question = entry.reflectionQuestion {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("終わったら、思い出してみてください")
                            .font(.caption2)
                            .tracking(1)
                            .foregroundStyle(Palette.ink3)
                        Text(question)
                            .font(.question)
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.shuSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .padding(.top, 16)
                }

                Toggle(isOn: $presenceEnabled) {
                    Text("ロック画面に置いておく")
                        .font(.footnote)
                        .foregroundStyle(Palette.ink2)
                }
                .tint(Palette.toggle)
                .padding(.top, 14)
                .onChange(of: presenceEnabled) { _, enabled in presenceChanged(enabled) }

                VStack(spacing: 6) {
                    Button(action: finish) {
                        Text("終えた — 記す")
                    }
                    .buttonStyle(ShuButtonStyle())
                    Button("この体験をやめる") { confirmsAbandon = true }
                        .font(.footnote)
                        .foregroundStyle(Palette.ink3)
                        .padding(.vertical, 8)
                }
                .padding(.top, 16)
            }
        }
        .confirmationDialog("この体験をやめますか？", isPresented: $confirmsAbandon, titleVisibility: .visible) {
            Button("やめる", role: .destructive, action: abandon)
        } message: {
            Text("評価はせずに終わります。体験帳には残りません。")
        }
    }
}


// MARK: - ふだん: 自分の樹のいまと「体験を記す」

/// ふだんのホームの真ん中。十の要素の段と、芽と、「体験を記す」。
/// きっかけは、求めたときだけ (ここから、もらいにいける)
struct TreeStatusCard: View {
    let tree: ExperienceTree
    let record: @MainActor () -> Void
    let requestPrompt: @MainActor () -> Void
    let openTree: @MainActor (String?) -> Void

    var body: some View {
        PaperCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Eyebrow(text: "技の樹")
                    Spacer()
                    if tree.totalRank > 0 {
                        Text("年輪 \(Ranks.kanji(tree.totalRank))")
                            .font(Typeface.mincho(13, relativeTo: .footnote))
                            .foregroundStyle(Palette.ink2)
                            .accessibilityLabel("年輪 \(tree.totalRank)")
                    }
                }

                Text(headline)
                    .font(.invitation)
                    .lineSpacing(7)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                    .accessibilityIdentifier("home.status")
                Text(detail)
                    .font(.footnote)
                    .lineSpacing(4)
                    .foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)

                RankGrid(tree: tree) { id in openTree(ExperienceTree.rootID(id)) }
                    .padding(.top, 16)

                if let element = tree.sproutingElements.first {
                    Button {
                        openTree(ExperienceTree.rootID(element.id))
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "leaf.fill")
                            Text("芽を使って、技を伸ばす")
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                        }
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Palette.shu)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(Palette.shuSoft, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 14)
                    .accessibilityIdentifier("home.sprouts")
                }

                VStack(spacing: 10) {
                    Button("体験を記す", action: record)
                        .buttonStyle(ShuButtonStyle())
                        .accessibilityIdentifier("home.record")
                        .accessibilityHint("いつもの一日で体験したことを、ひとこと記します")
                    Button(action: requestPrompt) {
                        Label("きっかけをもらう", systemImage: "sparkles")
                    }
                    .buttonStyle(QuietButtonStyle())
                    .accessibilityIdentifier("home.prompt")
                    Text("きっかけは、AIや体験ライブラリからのひとつの提案です。やらなくても、何も減りません。")
                        .font(.caption)
                        .foregroundStyle(Palette.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 18)
            }
        }
    }

    private var headline: String {
        let sprouting = tree.sproutingElements
        if !sprouting.isEmpty {
            return "\(sprouting.map(\.label).joined(separator: "・"))に、芽が出ています。"
        }
        if tree.totalRank == 0 {
            return "体験は、もう一日の中にある。"
        }
        if let latest = tree.learnedNodes.first {
            return "「\(latest.title)」が、身についています。"
        }
        return "段が上がると、芽が出ます。"
    }

    private var detail: String {
        if !tree.sproutingElements.isEmpty {
            return "どの技へ伸ばすかは、あなたが選びます。急がなくても、芽は消えません。"
        }
        if tree.totalRank == 0 {
            return "ふと足が止まったこと、いつもと違って見えたこと。自分の言葉でひとこと記すと、触れた要素に経験が積もり、段が上がります。"
        }
        if let nearest {
            let label = tree.element(nearest.element)?.label ?? ""
            return "次の段にいちばん近いのは「\(label)」。あと\(nearest.remaining)で\(Ranks.label(nearest.rank + 1))です。"
        }
        return "記した体験が触れた要素に、経験が積もります。"
    }

    /// 次の段にいちばん近い要素 (段のあるものから)
    private var nearest: ElementProgress? {
        tree.elements
            .map { tree.progress(of: $0.id) }
            .filter { $0.rank > 0 }
            .min { $0.remaining < $1.remaining }
    }
}

/// 十の要素の段を、五つずつ二段に (いまの自分の様子)。押すと、その要素の根をひらく
struct RankGrid: View {
    let tree: ExperienceTree
    let open: @MainActor (String) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(tree.elements) { element in
                let progress = tree.progress(of: element.id)
                let sprouting = tree.hasLearnable(inElement: element.id)
                Button {
                    open(element.id)
                } label: {
                    VStack(spacing: 5) {
                        Text(element.glyph)
                            .font(Typeface.fixedMincho(17))
                            .foregroundStyle(progress.rank > 0 ? Palette.ink : Palette.ink3)
                            .frame(width: 36, height: 36)
                            .background(progress.rank > 0 ? Palette.wash : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(sprouting ? Palette.shu : Palette.line, lineWidth: sprouting ? 1.4 : 1)
                            )
                            .overlay(alignment: .topTrailing) {
                                if sprouting {
                                    Circle()
                                        .fill(Palette.shu)
                                        .frame(width: 7, height: 7)
                                        .offset(x: 3, y: -3)
                                }
                            }
                        Text(progress.rank > 0 ? "\(element.label) \(Ranks.kanji(progress.rank))" : element.label)
                            .font(.caption2)
                            .foregroundStyle(progress.rank > 0 ? Palette.ink2 : Palette.ink3)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        ExperienceGauge(gained: progress.gained, span: progress.span, height: 2.5)
                            .frame(width: 40)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(element.label)、\(Ranks.label(progress.rank))")
                .accessibilityValue(value(progress, sprouting: sprouting))
                .accessibilityHint("技の樹で、この要素の根をひらきます")
                .accessibilityAddTraits(.isButton)
            }
        }
    }

    private func value(_ progress: ElementProgress, sprouting: Bool) -> String {
        var parts = ["経験 \(progress.experience)", "次の段まで あと\(progress.remaining)"]
        if sprouting { parts.append("芽が出ています") }
        return parts.joined(separator: "、")
    }
}

/// 4.0 にしてはじめて開いたとき (一度だけ): これまでの体験から、樹が育っていたこと
struct WelcomeCard: View {
    let report: GrowthReport
    let open: @MainActor () -> Void
    let dismiss: @MainActor () -> Void

    var body: some View {
        PaperCard(emphasized: true) {
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow(text: "技の樹", color: Palette.shu)
                Text("これまでの体験が、樹になっていました。")
                    .font(.sectionTitle)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("記してきた体験が、触れた要素の経験になりました。段が上がった要素には芽が出ています。どの技へ伸ばすかは、あなたが選びます。")
                    .font(.footnote)
                    .lineSpacing(4)
                    .foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                if !report.rankUps.isEmpty {
                    FlowLayout(spacing: 8) {
                        ForEach(report.rankUps) { up in
                            HStack(spacing: 6) {
                                ElementMark(glyph: up.element.glyph, size: 18, color: Palette.ink)
                                Text("\(up.element.label) \(Ranks.label(up.to))")
                            }
                            .font(.footnote)
                            .foregroundStyle(Palette.ink)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Palette.wash, in: Capsule())
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                ForEach(report.flashes) { node in
                    FlashLine(node: node)
                }
                HStack(spacing: 10) {
                    Button("樹を見る", action: open)
                        .buttonStyle(ShuButtonStyle(compact: true))
                        .accessibilityIdentifier("welcome.open")
                    Button("あとで", action: dismiss)
                        .buttonStyle(QuietButtonStyle(compact: true))
                }
                .padding(.top, 4)
            }
        }
    }
}

/// 閃いた技の1行 (傾けた朱の印「閃」と、閃いたときのこと)
struct FlashLine: View {
    let node: TreeNode

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SealView(character: "閃", size: 24, style: .filled, rotation: 45)
            VStack(alignment: .leading, spacing: 2) {
                Text("閃き — 「\(node.title)」")
                    .font(.experienceTitle)
                    .foregroundStyle(Palette.ink)
                Text(node.found ?? node.ability)
                    .font(.caption)
                    .foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 記したところ

/// 印が押される瞬間。重さのある動きと触覚で、記したことを確かめる。
/// 触れた要素に経験が積もり、段が上がれば芽が出る。閃きや深まりがあれば、ここで知らせる
struct CompletedCard: View {
    let entry: HistoryEntry
    /// 記したことで、樹がどう伸びたか
    let growth: GrowthReport
    /// この体験で使った技 (身についたもの)
    let skills: [TreeNode]
    let openTree: @MainActor (String?) -> Void
    let openJournal: @MainActor () -> Void
    let close: @MainActor () -> Void
    @State private var stamped = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        PaperCard {
            VStack(spacing: 0) {
                SealView(character: entry.sealCharacter, size: 96, style: .filled, rotation: stamped ? -6 : -16)
                    .scaleEffect(stamped ? 1 : 2.1)
                    .opacity(stamped ? 1 : 0)
                    .padding(.top, 8)
                    .accessibilityHidden(true)

                Text("体験帳に記しました")
                    .font(.sectionTitle)
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 18)
                Text(entry.isSelfRecorded ? "「\(entry.title)」" : entry.title)
                    .font(Typeface.mincho(15))
                    .foregroundStyle(Palette.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                if let note = entry.note {
                    Text("「\(note)」")
                        .font(Typeface.mincho(15))
                        .foregroundStyle(Palette.ink)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 10)
                }

                growthView
                    .padding(.top, 18)
                    .opacity(stamped ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.6).delay(0.5), value: stamped)

                VStack(spacing: 6) {
                    if let element = sproutToUse {
                        Button("\(element.label)の芽を使って、技を伸ばす") {
                            openTree(ExperienceTree.rootID(element.id))
                        }
                        .buttonStyle(ShuButtonStyle(compact: true))
                        .accessibilityIdentifier("completed.sprout")
                    }
                    HStack(spacing: 10) {
                        Button("樹で見る") { openTree(focus) }
                            .buttonStyle(QuietButtonStyle())
                            .accessibilityIdentifier("completed.tree")
                        Button("閉じる", action: close)
                            .buttonStyle(QuietButtonStyle())
                            .accessibilityIdentifier("completed.close")
                    }
                    Button("体験帳をひらく", action: openJournal)
                        .font(.footnote)
                        .foregroundStyle(Palette.ink3)
                        .padding(.vertical, 8)
                }
                .padding(.top, 18)
            }
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.55)) {
                stamped = true
            }
        }
        .accessibilityElement(children: .contain)
    }

    /// 経験・段・閃き・深まり・使った技
    private var growthView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !growth.gains.isEmpty {
                HStack(spacing: 8) {
                    Text("経験")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Palette.ink3)
                    FlowLayout(spacing: 6) {
                        ForEach(growth.gains) { element in
                            HStack(spacing: 4) {
                                ElementMark(glyph: element.glyph, size: 16)
                                Text("\(element.label) +1")
                            }
                            .font(.caption)
                            .foregroundStyle(Palette.ink2)
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
            ForEach(growth.rankUps) { up in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    ElementMark(glyph: up.element.glyph, size: 22, color: Palette.shu)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(up.element.label)が\(Ranks.label(up.to))に")
                            .font(.experienceTitle)
                            .foregroundStyle(Palette.ink)
                        Text(up.to - up.from > 1 ? "芽が\(Ranks.kanji(up.to - up.from))つ出ました。" : "芽がひとつ出ました。")
                            .font(.caption)
                            .foregroundStyle(Palette.shu)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
            ForEach(growth.flashes) { node in
                FlashLine(node: node)
            }
            ForEach(growth.deepened) { item in
                HStack(alignment: .top, spacing: 10) {
                    SealView(character: item.mastery.glyph, size: 24, style: .filled, rotation: -4)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("「\(item.node.title)」が\(item.mastery.glyph)に")
                            .font(.experienceTitle)
                            .foregroundStyle(Palette.ink)
                        Text(item.mastery.meaning)
                            .font(.caption)
                            .foregroundStyle(Palette.ink2)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
            if !skills.isEmpty {
                Text("使った技: \(skills.map { "「\($0.title)」" }.joined())")
                    .font(.caption)
                    .foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if growth.isEmpty && skills.isEmpty {
                Text("この記録は、体験帳に残りました。")
                    .font(.footnote)
                    .foregroundStyle(Palette.ink2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 段が上がって芽が出た要素 (伸ばせる技があるもの)
    private var sproutToUse: ExperienceElement? {
        let raised = Set(growth.rankUps.map(\.element.id))
        return growth.sproutElements.first { raised.contains($0.id) }
    }

    /// 「樹で見る」で寄るところ
    private var focus: String? {
        if let flash = growth.flashes.first { return flash.id }
        if let element = sproutToUse ?? growth.sproutElements.first { return ExperienceTree.rootID(element.id) }
        if let deep = growth.deepened.first { return deep.node.id }
        if let skill = skills.first { return skill.id }
        return growth.gains.first.map { ExperienceTree.rootID($0.id) }
    }
}

// MARK: - 樹の上の位置

/// きっかけや体験中のカードに添える「枝」: 要素の字と、どの技の稽古になるか。押すと樹の上でひらく
struct BranchLine: View {
    let lineage: Lineage
    let open: @MainActor (String?) -> Void

    var body: some View {
        if let nodeID = lineage.nodeID {
            Button {
                open(nodeID)
            } label: {
                face(showsChevron: true)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("技の樹の上で、\(lineage.sentence)")
            .accessibilityHint("技の樹で、つながっている技をひらきます")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier("card.branch")
        } else {
            face(showsChevron: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(lineage.sentence)
        }
    }

    private func face(showsChevron: Bool) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                ForEach(lineage.elements) { element in
                    ElementMark(glyph: element.glyph, size: 18)
                }
            }
            Text(lineage.sentence)
                .font(.caption)
                .foregroundStyle(Palette.ink2)
                .lineLimit(2)
            Spacer(minLength: 0)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Palette.ink3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Palette.wash, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - きっかけを作れなかったとき

struct FailedCard: View {
    let message: String
    let retry: @MainActor () -> Void
    let close: @MainActor () -> Void

    var body: some View {
        PaperCard {
            VStack(spacing: 0) {
                Text("きっかけを作れませんでした")
                    .font(.sectionTitle)
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 6)
                Text(message)
                    .font(.footnote)
                    .lineSpacing(4)
                    .foregroundStyle(Palette.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                HStack(spacing: 10) {
                    Button("もう一度", action: retry)
                        .buttonStyle(QuietButtonStyle())
                    Button("閉じる", action: close)
                        .buttonStyle(QuietButtonStyle())
                }
                .padding(.top, 16)
            }
            .frame(maxWidth: .infinity)
        }
    }
}
