import SwiftUI
import TaikenCore
import UniformTypeIdentifiers

/// 体験帳 (指示書 §15, §16)。数を競わせない: 連続記録も「今日もやろう」も出さない。
/// いつ何をしたかを、月の暦に押された印と、日ごとの記録で見る。
/// 要素ごとの段と技は、技の樹で見る (記録からも樹へ渡れる)。
struct JournalView: View {
    let model: HistoryViewModel
    let goHome: @MainActor () -> Void
    /// 技の樹をひらく (技の id があれば、そこを中心に)
    let openTree: @MainActor (String?) -> Void

    @State private var exportData: Data?
    @State private var pendingDeletion: HistoryEntry?
    @Namespace private var zoom
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    header
                    RanksPanel(progress: model.progress, learnedCount: model.learnedCount) { id in
                        openTree(id.map { ExperienceTree.rootID($0) })
                    }
                    MonthCalendar(model: model) { day in
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) {
                            proxy.scrollTo(day, anchor: .top)
                        }
                    }
                    if !model.trends.isEmpty {
                        TrendsBox(trends: model.trends)
                    }
                    entries
                    if let message = model.errorMessage {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(Palette.shu)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
        }
        .background(JournalBackground())
        .navigationTitle("体験帳")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if let exportData {
                        ShareLink(
                            item: JournalExport(data: exportData),
                            preview: SharePreview("体験帳（JSON）", image: Image(systemName: "doc.text"))
                        ) {
                            Label("書き出す（JSON）", systemImage: "square.and.arrow.up")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(Palette.ink)
                }
                .accessibilityLabel("その他")
                .disabled(model.isEmpty)
            }
        }
        .navigationDestination(for: HistoryEntry.self) { entry in
            EntryDetailView(
                entry: entry,
                skills: model.grownSkills(of: entry),
                openTree: { openTree(model.treeFocus(of: entry)) },
                onDelete: { delete(entry) }
            )
            .navigationTransition(.zoom(sourceID: entry.id, in: zoom))
        }
        .onAppear { reload() }
        .confirmationDialog(
            "この記録を削除しますか？",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            titleVisibility: .visible,
            presenting: pendingDeletion
        ) { entry in
            Button("削除", role: .destructive) { delete(entry) }
        } message: { entry in
            Text("「\(entry.title)」の印と、ひとことが消えます。この記録で積もった経験も無くなります (身についた技は残ります)。元に戻せません。")
        }
    }

    // MARK: - 見出し

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Eyebrow(text: "この端末の中だけ")
            Text("体験帳")
                .font(.displayTitle)
                .foregroundStyle(Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Text(model.stats.selfRecorded > 0
                ? "記した体験 \(model.stats.lived) ・ 今月 \(model.stats.thisMonth) ・ 自分で見つけた \(model.stats.selfRecorded)"
                : "記した体験 \(model.stats.lived) ・ 今月 \(model.stats.thisMonth)")
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(Palette.ink2)
        }
        .padding(.top, 4)
    }

    // MARK: - 記録

    @ViewBuilder
    private var entries: some View {
        if model.isEmpty {
            VStack(spacing: 14) {
                SealView(character: "体", size: 56, style: .ghost, rotation: 0)
                Text("まだ印はありません。")
                    .font(.sectionTitle)
                    .foregroundStyle(Palette.ink)
                Text("いつもの一日で体験したことを、ホームの「体験を記す」から、ひとこと記してみてください。\n最初の印が、ここに押されます。")
                    .font(.footnote)
                    .foregroundStyle(Palette.ink2)
                    .multilineTextAlignment(.center)
                Button("ホームへ", action: goHome)
                    .buttonStyle(QuietButtonStyle())
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        } else {
            LazyVStack(alignment: .leading, spacing: 22) {
                ForEach(model.sections) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        DayHeader(day: section.day)
                        ForEach(section.entries) { entry in
                            NavigationLink(value: entry) {
                                EntryRow(entry: entry)
                                    .matchedTransitionSource(id: entry.id, in: zoom)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("journal.entry")
                            .contextMenu {
                                Button("削除", systemImage: "trash", role: .destructive) { pendingDeletion = entry }
                            }
                        }
                    }
                    .id(section.day)
                }
            }
        }
    }

    private func reload() {
        model.reload()
        exportData = try? model.exportJSON()
    }

    private func delete(_ entry: HistoryEntry) {
        model.delete(entry)
        exportData = try? model.exportJSON()
    }
}

/// 体験帳の地: 紙に、ほんのり朝の光
private struct JournalBackground: View {
    var body: some View {
        ZStack(alignment: .top) {
            Palette.paper
            LinearGradient(colors: [Palette.shuSoft, .clear], startPoint: .top, endPoint: .center)
                .opacity(0.6)
        }
        .ignoresSafeArea()
    }
}

// MARK: - 月の暦

private struct MonthCalendar: View {
    let model: HistoryViewModel
    let jump: @MainActor (Date) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    model.showPreviousMonth()
                } label: {
                    Image(systemName: "chevron.left").frame(width: 40, height: 40)
                }
                .accessibilityLabel("前の月")
                Spacer()
                Text(model.displayedMonth.formatted(.dateTime.year().month(.wide)))
                    .font(Typeface.mincho(17, bold: true, relativeTo: .headline))
                    .foregroundStyle(Palette.ink)
                    .onTapGesture(count: 2) { model.showCurrentMonth() }
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityAction(named: "今月を表示") { model.showCurrentMonth() }
                Spacer()
                Button {
                    model.showNextMonth()
                } label: {
                    Image(systemName: "chevron.right").frame(width: 40, height: 40)
                }
                .disabled(!model.canShowNextMonth)
                .accessibilityLabel("次の月")
            }
            .foregroundStyle(Palette.ink2)
            .buttonStyle(.plain)

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(Self.weekdaySymbols.enumerated()), id: \.offset) { item in
                    Text(item.element)
                        .font(.caption2)
                        .foregroundStyle(Palette.ink3)
                        .frame(height: 18)
                }
                ForEach(model.monthGrid()) { mark in
                    DayCell(mark: mark) { jump(mark.date) }
                }
            }
        }
        .padding(16)
        .background(Palette.wash, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .animation(.easeInOut(duration: 0.25), value: model.displayedMonth)
    }

    /// 週の始まりを端末の設定に合わせる (HistoryViewModel.monthGrid と同じ Calendar.current)
    static var weekdaySymbols: [String] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }
}

private struct DayCell: View {
    let mark: HistoryViewModel.DayMark
    let tap: @MainActor () -> Void

    var body: some View {
        // 印のある日だけ押せる (その日の記録へ移る)
        Group {
            if mark.entries.isEmpty {
                face
            } else {
                Button(action: tap) { face }
                    .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAddTraits(mark.entries.isEmpty ? [] : .isButton)
    }

    private var face: some View {
        VStack(spacing: 3) {
            Text("\(mark.day)")
                .font(.caption2.weight(mark.isToday ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(mark.isToday ? Palette.ink : Palette.ink3)
            if let first = mark.entries.first {
                SealView(character: first.sealCharacter, size: 22, style: .outlined, rotation: Double(mark.day % 5) - 3)
            } else {
                Color.clear.frame(width: 22, height: 22)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 50)
        .background {
            if mark.isToday {
                RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.ink.opacity(0.35), lineWidth: 1)
            }
        }
        .opacity(mark.isInMonth ? 1 : 0.32)
        .contentShape(Rectangle())
    }

    private var accessibilityText: String {
        let date = mark.date.formatted(.dateTime.month(.wide).day())
        guard !mark.entries.isEmpty else { return date }
        return "\(date)、\(mark.entries.map(\.title).joined(separator: "、"))"
    }
}

// MARK: - 最近の傾向

private struct TrendsBox: View {
    let trends: [PreferenceTrends.Summary]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            MiniHead("最近の傾向")
            ForEach(trends) { trend in
                Label {
                    Text(trend.sentence)
                        .font(.footnote)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: icon(for: trend.direction))
                        .foregroundStyle(Palette.ink3)
                }
            }
            Text("最近の反応から計算した目安です。あなたがどんな人かを決めつけるものではなく、古い反応ほど影響は小さくなります。")
                .font(.caption)
                .foregroundStyle(Palette.ink3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
    }

    private func icon(for direction: PreferenceTrends.Direction) -> String {
        switch direction {
        case .positive: "sun.max"
        case .negative: "cloud"
        case .mixed: "circle.lefthalf.filled"
        }
    }
}

// MARK: - 1日ぶん

private struct DayHeader: View {
    let day: Date

    var body: some View {
        Text(day.formatted(.dateTime.month(.wide).day().weekday(.wide)))
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Palette.ink2)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - 要素の段

/// 十の要素の段と、身についた技の数。押すと技の樹がひらく (要素を押すと、その要素の根へ)
private struct RanksPanel: View {
    let progress: [ElementProgress]
    let learnedCount: Int
    let openTree: @MainActor (String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                openTree(nil)
            } label: {
                HStack {
                    MiniHead("要素の段")
                    Spacer()
                    HStack(spacing: 4) {
                        Text(learnedCount > 0 ? "身についた技 \(learnedCount) ・ 技の樹をひらく" : "技の樹をひらく")
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                    }
                    .font(.caption)
                    .foregroundStyle(Palette.ink2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(learnedCount > 0 ? "技の樹をひらく。身についた技 \(learnedCount)" : "技の樹をひらく")
            .accessibilityIdentifier("journal.tree")

            HStack(spacing: 0) {
                ForEach(TaikenContent.shared.elements) { element in
                    let rank = progress.first { $0.element == element.id }?.rank ?? 0
                    Button {
                        openTree(element.id)
                    } label: {
                        VStack(spacing: 5) {
                            SealView(
                                character: element.glyph, size: 26,
                                style: rank > 0 ? .outlined : .ghost, rotation: 0
                            )
                            Text(element.label)
                                .font(.system(size: 9))
                                .foregroundStyle(rank > 0 ? Palette.ink2 : Palette.ink3)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(rank > 0 ? Ranks.kanji(rank) : "・")
                                .font(Typeface.fixedMincho(11))
                                .foregroundStyle(rank > 0 ? Palette.ink : Palette.ink3)
                        }
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(element.label)、\(Ranks.label(rank))")
                    .accessibilityHint("技の樹で、この要素の根をひらきます")
                }
            }
        }
        .padding(16)
        .background(Palette.wash, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

struct EntryRow: View {
    let entry: HistoryEntry

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            SealView(
                character: entry.sealCharacter, size: 40,
                style: entry.status == .completed ? .outlined : .ghost,
                rotation: Double(Calendar.current.component(.day, from: entry.createdAt) % 5) - 3
            )
            .padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.isSelfRecorded ? "「\(entry.title)」" : entry.title)
                    .font(.experienceTitle)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !entry.isSelfRecorded {
                    Text(entry.invitation)
                        .font(.footnote)
                        .foregroundStyle(Palette.ink2)
                        .lineLimit(2)
                }
                if let note = entry.note {
                    Text("「\(note)」")
                        .font(Typeface.mincho(14))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(3)
                }
                HStack(spacing: 8) {
                    Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
                    if entry.status == .active {
                        Text("体験中").foregroundStyle(Palette.shu)
                    } else if entry.isSelfRecorded {
                        Text("自分で記した")
                    } else if let rating = entry.rating {
                        Label(rating.label, systemImage: rating.symbolName)
                    }
                }
                .font(.caption)
                .foregroundStyle(Palette.ink3)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.panel)
        }
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("記録をひらきます")
    }
}

// MARK: - 書き出し

/// 体験帳の JSON。共有するときに初めてファイルになる (一時ファイルを残さない)
struct JournalExport: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { export in export.data }
            .suggestedFileName("taiken-journal.json")
    }
}

#Preview {
    NavigationStack {
        JournalView(model: AppDependencies.preview().history, goHome: {}, openTree: { _ in })
    }
}
