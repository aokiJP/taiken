import SwiftUI
import TaikenCore

// MARK: - 面

/// 障子のような半透明の面。体験はいつもこの上に置く
struct PaperCard<Content: View>: View {
    /// 体験中: 朱の縁と、ゆっくり呼吸する光
    var emphasized = false
    @ViewBuilder var content: Content
    @Environment(\.skyPalette) private var sky
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false

    private var fill: Color {
        // 夜の空にライト表示で置くときは、灯りの下の紙のように明るくする
        (sky?.isDark == true && colorScheme == .light) ? Palette.panelLamplight : Palette.panel
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        content
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(fill)
                }
            }
            .overlay {
                shape.strokeBorder(emphasized ? Palette.shu : Palette.line, lineWidth: emphasized ? 1.5 : 1)
            }
            .shadow(
                color: emphasized ? Palette.shu.opacity(breathing ? 0.42 : 0.24) : Palette.shadow.opacity(0.45),
                radius: emphasized ? (breathing ? 26 : 18) : 18, x: 0, y: 12
            )
            .onAppear {
                guard emphasized, !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { breathing = true }
            }
    }
}

/// シート・体験帳の中の、線だけで区切る面
struct LinedBox<Content: View>: View {
    var padding: CGFloat = 14
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
    }
}

// MARK: - ボタン

/// 朱のボタン。「やってみる」「記す」など、印に値する操作だけに使う
struct ShuButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        ShuButtonBody(configuration: configuration, compact: compact)
    }

    private struct ShuButtonBody: View {
        let configuration: ButtonStyleConfiguration
        let compact: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(compact ? .callout.weight(.bold) : .body.weight(.bold))
                .tracking(compact ? 0.8 : 1.5)
                .foregroundStyle(Palette.onShu)
                .frame(maxWidth: .infinity, minHeight: compact ? 44 : 52)
                .background(Palette.shu, in: RoundedRectangle(cornerRadius: compact ? 13 : 16, style: .continuous))
                .shadow(color: Palette.shu.opacity(isEnabled ? 0.35 : 0), radius: 12, x: 0, y: 8)
                .opacity(isEnabled ? 1 : 0.45)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
        }
    }
}

/// 静かなボタン。「別の視点」「今はやらない」など、同じ重さで並べる選択肢
struct QuietButtonStyle: ButtonStyle {
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .foregroundStyle(Palette.ink)
            .frame(maxWidth: .infinity, minHeight: compact ? 44 : 48)
            .padding(.horizontal, 8)
            .background(Palette.wash, in: RoundedRectangle(cornerRadius: compact ? 13 : 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: compact ? 13 : 16, style: .continuous).strokeBorder(Palette.line, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// 札を折り返して並べる (話しかけのきっかけなど)
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            widest = max(widest, x + size.width)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

/// 気分・話しかけのきっかけなどの丸い札
struct ChipButtonStyle: ButtonStyle {
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote)
            .foregroundStyle(selected ? Palette.paper : Palette.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background {
                if selected {
                    Capsule().fill(Palette.ink)
                } else {
                    ZStack {
                        Capsule().fill(.ultraThinMaterial)
                        Capsule().fill(Palette.panel)
                    }
                }
            }
            .overlay(Capsule().strokeBorder(selected ? Color.clear : Palette.line, lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// 空の上に浮かぶ丸いボタン (体験帳・設定)
struct FloatingIconButton: View {
    let systemImage: String
    let label: String
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            if #available(iOS 26.0, *) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Palette.ink)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(Palette.ink)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay(Circle().strokeBorder(Palette.line, lineWidth: 1))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - 文字の部品

/// 小さな見出し (今日の体験・体験中 など)
struct Eyebrow: View {
    let text: String
    var color: Color = Palette.ink3

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .tracking(1.6)
            .foregroundStyle(color)
    }
}

/// 体験の名前を、手紙の署名のように添える
struct Signature: View {
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Palette.ink2.opacity(0.5)).frame(width: 22, height: 1)
            Text(title).font(.experienceTitle).foregroundStyle(Palette.ink2)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("体験の名前 \(title)")
    }
}

/// 事実と推測を見た目で区別する (指示書 §7, §9)
struct SituationNoteRow: View {
    let note: SituationNote

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(note.basis.label)
                .font(.caption2.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .foregroundStyle(note.basis.isFact ? Palette.shu : Palette.ink2)
                .background(note.basis.isFact ? Palette.shuSoft : Palette.line, in: Capsule())
            Text(note.text)
                .font(.footnote)
                .italic(!note.basis.isFact)
                .foregroundStyle(note.basis.isFact ? Palette.ink : Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 強いつらさのサインがあったときの相談先の案内
struct SupportCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("ひとりで抱えないでください", systemImage: "heart.text.square")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.ink)
            Text(SupportResources.description)
                .font(.footnote)
                .foregroundStyle(Palette.ink2)
                .fixedSize(horizontal: false, vertical: true)
            Link(destination: SupportResources.url) {
                Label(SupportResources.title, systemImage: "arrow.up.right.square")
                    .font(.footnote.weight(.semibold))
            }
            .tint(Palette.shu)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.shuSoft, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityElement(children: .contain)
    }
}

// MARK: - シートの部品

/// シートの見出し: 明朝の題と、ひとことの説明と、閉じるボタン
struct SheetHeader: View {
    let title: String
    var lead: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.sectionTitle)
                    .foregroundStyle(Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let lead {
                    Text(lead)
                        .font(.footnote)
                        .foregroundStyle(Palette.ink3)
                }
            }
            Spacer(minLength: 0)
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.ink2)
                    .frame(width: 32, height: 32)
                    .background(Palette.wash, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("閉じる")
        }
    }
}

/// シートの中の小見出し
struct MiniHead: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .tracking(1.4)
            .foregroundStyle(Palette.ink3)
            .accessibilityAddTraits(.isHeader)
    }
}

/// 「項目 — 値」の行 (シートの中の表)
struct KeyValueRow: View {
    let key: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key)
                .font(.footnote)
                .foregroundStyle(Palette.ink3)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.footnote)
                .foregroundStyle(Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - 動き

/// 墨がにじむように現れる (ぼかし → くっきり)。視差効果を減らす設定ではすぐに表示する
struct InkReveal: ViewModifier {
    var delay: Double = 0
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .blur(radius: shown || reduceMotion ? 0 : 7)
            .offset(y: shown || reduceMotion ? 0 : 8)
            .onAppear {
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.8).delay(delay)) {
                    shown = true
                }
            }
    }
}

extension View {
    func inkReveal(delay: Double = 0) -> some View {
        modifier(InkReveal(delay: delay))
    }
}

// MARK: - 表示名

extension Basis {
    var label: String {
        switch self {
        case .calendar: "予定"
        case .stated: "あなたの言葉"
        case .inferred: "推測"
        }
    }
}

extension Rating {
    /// 振り返りの選択肢に添える記号 (絵文字ではなく、静かな形で)
    var symbolName: String {
        switch self {
        case .positive: "sun.max"
        case .neutral: "circle"
        case .negative: "cloud"
        }
    }
}

extension ResultSource {
    /// きっかけをつくったしくみ (「きっかけの手がかり」に正直に出す)
    var engineLabel: String {
        switch self {
        case .ai: "自分のサーバーのAI"
        case .mock: "サーバーの開発用モック"
        case .onDevice: "Apple Intelligence（端末内）"
        case .local: "体験ライブラリ（端末内）"
        case .fallback: "体験ライブラリ（サーバーの代替）"
        }
    }
}

extension Mood {
    var symbolName: String {
        switch self {
        case .tired: "moon.zzz"
        case .bored: "sparkles"
        case .focus: "scope"
        case .refresh: "wind"
        }
    }
}
