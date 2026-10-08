import SwiftUI
import TaikenCore

/// はじめの案内。四枚だけ: 何のアプリか → AIの立ち位置 → 体験の樹 → 使う情報はあなたが選ぶ。
/// 許可は最後のページで、理由と一緒に、オフのままでも進めるように聞く。
struct OnboardingView: View {
    let dependencies: AppDependencies
    let complete: @MainActor () -> Void

    @State private var page = 0
    @State private var useCalendar = true
    @State private var morningLetter = false
    @State private var isFinishing = false
    @Environment(\.colorScheme) private var colorScheme

    private let pageCount = 4
    /// 案内の挿絵の樹 (見本の体験帳から組み立てる)
    private let sampleScene: TreeScene = {
        let tree = TreeBuilder.build(garden: .empty, entries: HistoryEntry.sampleJournal())
        return TreeScene.make(tree: tree, layout: TreeLayout.make(tree: tree))
    }()

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            let time = TimeOfDay.at(timeline.date, calendar: .current)
            let palette = time.sky(dark: colorScheme == .dark)
            ZStack {
                SkyBackground(time: time)
                VStack(spacing: 0) {
                    TabView(selection: $page) {
                        welcome(palette: palette).tag(0)
                        stance(palette: palette).tag(1)
                        treePage(palette: palette).tag(2)
                        permissions(palette: palette).tag(3)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    footer(palette: palette)
                }
                .environment(\.skyPalette, palette)
            }
        }
        .sensoryFeedback(.selection, trigger: page)
    }

    // MARK: - 1. いつもの一日に

    private func welcome(palette: SkyPalette) -> some View {
        OnboardingPage {
            SealView(character: "体", size: 52, style: .filled, rotation: -6)
                .inkReveal()
                .padding(.bottom, 12)

            Text("いつもの一日に、\nまだ見ていない\n体験がある。")
                .font(.displayTitle)
                .lineSpacing(6)
                .foregroundStyle(palette.onSky)
                .inkReveal(delay: 0.2)
                .accessibilityAddTraits(.isHeader)

            Text("体験は特別な場所ではなく、予定や移動や食事の中にあります。見る、聴く、味わう、休む。いつもしていることが、そのまま入り口です。")
                .font(Typeface.mincho(16))
                .lineSpacing(6)
                .foregroundStyle(palette.onSkySecondary)
                .inkReveal(delay: 0.4)
        }
    }

    // MARK: - 2. AIの立ち位置

    private func stance(palette: SkyPalette) -> some View {
        OnboardingPage {
            Text("AIは、視点を\nひとつ差し出すだけ。")
                .font(.displayTitle)
                .lineSpacing(6)
                .foregroundStyle(palette.onSky)
                .accessibilityAddTraits(.isHeader)

            Text("予定や気分から、いつもの行動を少し違う角度で見る提案をひとつ。やるかどうか、どう感じるかは、あなたが決めます。")
                .font(Typeface.mincho(16))
                .lineSpacing(6)
                .foregroundStyle(palette.onSkySecondary)

            HStack(spacing: 8) {
                Pill(text: "やってみる", emphasized: true)
                Pill(text: "別の視点", emphasized: false)
                Pill(text: "今はやらない", emphasized: false)
            }
            .padding(.top, 6)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("選べるのは、やってみる・別の視点・今はやらない の三つ")

            Text("断っても、何も減りません。断ったあとは、しばらく提案を控えます。連続記録やバッジもありません。")
                .font(.footnote)
                .foregroundStyle(palette.onSkySecondary)
        }
    }

    // MARK: - 3. 体験の樹

    private func treePage(palette: SkyPalette) -> some View {
        OnboardingPage {
            TreeCanvas(
                scene: sampleScene, viewport: TreeViewport(), palette: palette, selected: nil, highlighted: nil,
                time: 0, labels: false
            )
            .frame(height: 230)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)

            Text("やった体験が、\n樹になる。")
                .font(.displayTitle)
                .lineSpacing(6)
                .foregroundStyle(palette.onSky)
                .accessibilityAddTraits(.isHeader)

            Text("体験は「見る」「聴く」「味わう」など、10の要素の根から伸びています。記した体験は朱の印として灯り、その先に次の芽が出ます。自分で体験を編んだり、響き合った体験どうしを糸で結んだりもできます。")
                .font(Typeface.mincho(16))
                .lineSpacing(6)
                .foregroundStyle(palette.onSkySecondary)

            Text("点数やレベルはありません。どの体験も、いつでも始められます。")
                .font(.footnote)
                .foregroundStyle(palette.onSkySecondary)
        }
    }

    // MARK: - 4. 使う情報

    private func permissions(palette: SkyPalette) -> some View {
        OnboardingPage {
            Text("使う情報は、\nあなたが選ぶ。")
                .font(.displayTitle)
                .lineSpacing(6)
                .foregroundStyle(palette.onSky)
                .accessibilityAddTraits(.isHeader)

            PaperCard {
                VStack(spacing: 14) {
                    PermissionRow(
                        title: "カレンダー", detail: "今日と明日の予定の、時間とタイトルだけ", isOn: $useCalendar
                    )
                    Divider().overlay(Palette.line)
                    PermissionRow(
                        title: "朝の便り", detail: "朝に一度だけ。その日の小さな体験のきっかけを", isOn: $morningLetter
                    )
                }
            }

            Text("どちらもあとから設定で変えられます。会話は保存しません。体験帳はこの端末の中だけにあります。")
                .font(.footnote)
                .foregroundStyle(palette.onSkySecondary)
        }
    }

    // MARK: - 下の帯

    private func footer(palette: SkyPalette) -> some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Capsule()
                        .fill(index == page ? palette.onSky : palette.onSky.opacity(0.3))
                        .frame(width: index == page ? 22 : 7, height: 7)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: page)
            .accessibilityHidden(true)

            Group {
                if page == pageCount - 1 {
                    Button {
                        Task { await finish() }
                    } label: {
                        HStack(spacing: 8) {
                            if isFinishing { ProgressView().tint(Palette.onShu) }
                            Text("最初の体験を受け取る")
                        }
                    }
                    .buttonStyle(ShuButtonStyle())
                    .disabled(isFinishing)
                } else {
                    Button(page == 0 ? "はじめる" : "つぎへ") {
                        withAnimation(.easeInOut(duration: 0.35)) { page += 1 }
                    }
                    .buttonStyle(QuietButtonStyle())
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.bottom, 20)
    }

    /// 選んだ許可だけを、理由を見せたあとで求める。断られても先へ進む
    private func finish() async {
        guard !isFinishing else { return }
        isFinishing = true
        dependencies.defaults.defaults.set(useCalendar, forKey: ConsentKey.useCalendar)
        if useCalendar {
            await dependencies.home.requestCalendarAccess()
        }
        if morningLetter {
            await dependencies.settings.setDailyLetterEnabled(true)
        }
        isFinishing = false
        complete()
    }
}

/// 1ページの枠: 下寄せで、文字は左揃え
private struct OnboardingPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Spacer(minLength: 40)
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(.bottom)
    }
}

private struct Pill: View {
    let text: String
    let emphasized: Bool

    var body: some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(emphasized ? Palette.onShu : Palette.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background {
                if emphasized {
                    Capsule().fill(Palette.shu)
                } else {
                    ZStack {
                        Capsule().fill(.ultraThinMaterial)
                        Capsule().fill(Palette.panel)
                    }
                }
            }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Palette.ink)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Palette.toggle)
    }
}

#Preview {
    OnboardingView(dependencies: .preview(), complete: {})
}
