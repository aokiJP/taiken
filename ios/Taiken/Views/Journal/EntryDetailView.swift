import SwiftUI
import TaikenCore

/// 体験帳の1ページ。押した印と、その時間と、残したひとこと。この記録で育った技と、技の樹へも渡れる
struct EntryDetailView: View {
    let entry: HistoryEntry
    /// この記録で育った技 (稽古から始めたもの・使ったと選んだもの)
    var skills: [HistoryViewModel.GrownSkill] = []
    /// 技の樹で、この記録に近い場所をひらく
    let openTree: @MainActor () -> Void
    let onDelete: @MainActor () -> Void

    /// 共有するカードに、ひとことも載せるか (ひとことは「この端末だけ」の約束なので、既定はオフ)
    @State private var includeNote = false
    @State private var card: Image?
    @State private var confirmsDeletion = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(entry.createdAt.formatted(.dateTime.year().month(.wide).day().weekday(.wide)))
                            .font(.footnote)
                            .foregroundStyle(Palette.ink3)
                        Text(entry.isSelfRecorded ? "「\(entry.title)」" : entry.title)
                            .font(entry.isSelfRecorded ? .sectionTitle : .displayTitle)
                            .foregroundStyle(Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text(entry.momentLine)
                            .font(Typeface.mincho(14, relativeTo: .subheadline))
                            .foregroundStyle(Palette.ink2)
                    }
                    Spacer(minLength: 12)
                    SealView(
                        character: entry.sealCharacter, size: 76,
                        style: entry.status == .completed ? .filled : .ghost, rotation: -6
                    )
                }

                if !entry.isSelfRecorded {
                    Text(entry.invitation)
                        .font(.invitation)
                        .lineSpacing(7)
                        .foregroundStyle(Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(entry.perspective)
                        .font(.footnote)
                        .lineSpacing(4)
                        .foregroundStyle(Palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let question = entry.reflectionQuestion {
                    LinedBox {
                        VStack(alignment: .leading, spacing: 6) {
                            MiniHead("問い")
                            Text(question)
                                .font(.question)
                                .foregroundStyle(Palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    MiniHead("記したこと")
                    if entry.status == .active {
                        Text("いま体験中です。終えたら、ホームから記せます。")
                            .font(.footnote)
                            .foregroundStyle(Palette.ink2)
                    } else if entry.isSelfRecorded {
                        Text(entry.elementLabels.isEmpty
                            ? "自分で見つけて、記した体験です。"
                            : "自分で見つけて、記した体験です。\(entry.elementLabels.joined(separator: "・"))に、経験が積もりました。")
                            .font(.footnote)
                            .foregroundStyle(Palette.ink2)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        if let rating = entry.rating {
                            Label(rating.label, systemImage: rating.symbolName)
                                .font(.callout)
                                .foregroundStyle(Palette.ink)
                        }
                        if let note = entry.note {
                            Text("「\(note)」")
                                .font(Typeface.mincho(17, relativeTo: .body))
                                .lineSpacing(4)
                                .foregroundStyle(Palette.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let finished = entry.finishedAt {
                            Text("\(finished.formatted(date: .omitted, time: .shortened))に記しました")
                                .font(.caption)
                                .foregroundStyle(Palette.ink3)
                        }
                    }
                }

                let labels = ExperienceTag.displayLabels(entry.tags)
                if !labels.isEmpty {
                    Text(labels.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(Palette.ink3)
                }

                if !skills.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        MiniHead("この記録で育った技")
                        ForEach(skills) { skill in
                            HStack(spacing: 10) {
                                SealView(
                                    character: skill.glyph, size: 26, style: skill.state == .learned ? .outlined : .ghost,
                                    rotation: -4
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(skill.node.title)
                                        .font(.experienceTitle)
                                        .foregroundStyle(Palette.ink)
                                    Text(Self.caption(of: skill.state))
                                        .font(.caption)
                                        .foregroundStyle(skill.state == .learned ? Palette.shu : Palette.ink3)
                                }
                                Spacer(minLength: 0)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }

                Button(action: openTree) {
                    HStack(spacing: 10) {
                        ForEach(entry.resolvedElements(), id: \.self) { id in
                            if let element = TaikenContent.shared.element(id) {
                                ElementMark(glyph: element.glyph, size: 20)
                            }
                        }
                        Text("技の樹で見る")
                            .font(.callout)
                            .foregroundStyle(Palette.ink)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.footnote)
                            .foregroundStyle(Palette.ink3)
                    }
                    .padding(14)
                    .background(Palette.wash, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("entry.tree")

                if entry.status == .completed {
                    shareSection
                }

                Button("この記録を削除", role: .destructive) { confirmsDeletion = true }
                    .font(.footnote)
                    .foregroundStyle(Palette.ink3)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 12)
        }
        .background(Palette.paper.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .task(id: includeNote) { card = renderCard() }
        .confirmationDialog("この記録を削除しますか？", isPresented: $confirmsDeletion, titleVisibility: .visible) {
            Button("削除", role: .destructive) {
                onDelete()
                dismiss()
            }
        } message: {
            Text("印と、ひとことが消えます。元に戻せません。")
        }
    }

    /// 育った技に添える一文
    static func caption(of state: NodeState) -> String {
        switch state {
        case .learned: "身についた技 · 記録がひとつ重なりました"
        case .ready: "育てられる技 · この記録が稽古になりました"
        case .sensed: "気配のある技 · この記録が稽古になりました"
        case .unknown: ""
        }
    }

    // MARK: - 印のカード

    @ViewBuilder
    private var shareSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            MiniHead("印のカード")
            StampCard(entry: entry, includeNote: includeNote)
                .scaleEffect(0.86, anchor: .topLeading)
                .frame(width: StampCard.size.width * 0.86, height: StampCard.size.height * 0.86, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: Palette.shadow.opacity(0.35), radius: 14, x: 0, y: 8)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("共有用のカードの見本")
            if entry.note != nil {
                Toggle("ひとことも載せる", isOn: $includeNote)
                    .font(.footnote)
                    .tint(Palette.toggle)
            }
            if let card {
                ShareLink(item: card, preview: SharePreview(entry.title, image: card)) {
                    Label("カードを共有", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(QuietButtonStyle())
            }
            Text("共有するのは、このカードの画像だけです。")
                .font(.caption)
                .foregroundStyle(Palette.ink3)
        }
    }

    @MainActor
    private func renderCard() -> Image? {
        let renderer = ImageRenderer(content: StampCard(entry: entry, includeNote: includeNote))
        renderer.scale = 3
        guard let image = renderer.uiImage else { return nil }
        return Image(uiImage: image)
    }
}

/// 共有用の印のカード。体験をした時刻の空の上に、誘いかけと印を置く
struct StampCard: View {
    static let size = CGSize(width: 360, height: 450)

    let entry: HistoryEntry
    let includeNote: Bool

    var body: some View {
        let palette = TimeOfDay.at(entry.createdAt, calendar: .current).sky(dark: false)
        ZStack {
            StillSky(palette: palette)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.createdAt.formatted(.dateTime.year().month(.wide).day()))
                            .font(.system(size: 11, weight: .medium))
                            .tracking(1)
                            .foregroundStyle(Palette.ink3)
                        Text(entry.elementLine)
                            .font(Typeface.fixedMincho(14))
                            .foregroundStyle(Palette.ink2)
                    }
                    Spacer()
                    SealView(character: entry.sealCharacter, size: 62, style: .filled, rotation: -6)
                }
                Spacer(minLength: 16)
                Text(entry.isSelfRecorded ? "「\(entry.title)」" : entry.invitation)
                    .font(Typeface.fixedMincho(19, bold: false))
                    .lineSpacing(7)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !entry.isSelfRecorded {
                    HStack(spacing: 10) {
                        Rectangle().fill(Palette.ink2.opacity(0.5)).frame(width: 22, height: 1)
                        Text(entry.title)
                            .font(Typeface.fixedMincho(14))
                            .foregroundStyle(Palette.ink2)
                    }
                    .padding(.top, 14)
                }
                if includeNote, let note = entry.note {
                    Text("「\(note)」")
                        .font(Typeface.fixedMincho(14, bold: false))
                        .foregroundStyle(Palette.ink)
                        .lineLimit(3)
                        .padding(.top, 14)
                }
                Spacer(minLength: 16)
                Text("体験帳より")
                    .font(.system(size: 10, weight: .medium))
                    .tracking(3)
                    .foregroundStyle(Palette.ink3)
            }
            .padding(24)
            .background(Color(hex: 0xFBFAF7, opacity: 0.93), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(20)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .environment(\.colorScheme, .light)
    }
}

extension HistoryEntry {
    /// 「夕方に始めた体験」「夜に記した体験」
    var momentLine: String {
        let label = TimeOfDay.at(createdAt, calendar: .current).label
        return isSelfRecorded ? "\(label)に記した体験" : "\(label)に始めた体験"
    }

    /// 「見る」「休む」(触れた要素の名前)
    var elementLabels: [String] {
        Array(resolvedElements().prefix(3)).compactMap { TaikenContent.shared.element($0)?.label }
    }

    /// 「見る · 休む の体験」(共有カードに添える)
    var elementLine: String {
        let labels = elementLabels
        return labels.isEmpty ? "体験帳より" : "\(labels.joined(separator: " · ")) の体験"
    }
}

#Preview {
    NavigationStack {
        EntryDetailView(entry: HistoryEntry.sampleJournal()[1], openTree: {}, onDelete: {})
    }
}
