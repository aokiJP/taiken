#if canImport(ActivityKit)
import ActivityKit
import SwiftUI
import WidgetKit

/// 体験中の Live Activity。ロック画面と Dynamic Island に、誘いかけと問いを静かに置いておく。
/// 経過時間は数えない (急かさない)。始めた時刻と、体験の要素だけを添える
struct ExperienceLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ExperienceActivityAttributes.self) { context in
            ExperienceLockScreenView(attributes: context.attributes, state: context.state)
                .activityBackgroundTint(Palette.paper.opacity(0.92))
                .activitySystemActionForegroundColor(Palette.ink)
                .widgetURL(DeepLink.today.url)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    SealView(character: context.attributes.sealCharacter, size: 34, style: .filled, rotation: -6)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.elementLabel)
                        .font(Typeface.fixedMincho(13))
                        .foregroundStyle(.white.opacity(0.75))
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.title)
                        .font(Typeface.fixedMincho(14))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.attributes.invitation)
                            .font(Typeface.fixedMincho(14, bold: false))
                            .foregroundStyle(.white)
                            .lineLimit(3)
                        if let question = context.state.reflectionQuestion {
                            Text(question)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Text(context.attributes.sealCharacter)
                    .font(Typeface.fixedMincho(15))
                    .foregroundStyle(Palette.shu)
            } compactTrailing: {
                Text(context.attributes.elementLabel)
                    .font(Typeface.fixedMincho(12))
                    .foregroundStyle(.white.opacity(0.8))
            } minimal: {
                Text(context.attributes.sealCharacter)
                    .font(Typeface.fixedMincho(14))
                    .foregroundStyle(Palette.shu)
            }
            .keylineTint(Palette.shu)
            .widgetURL(DeepLink.today.url)
        }
    }
}

struct ExperienceLockScreenView: View {
    let attributes: ExperienceActivityAttributes
    let state: ExperienceActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            SealView(character: attributes.sealCharacter, size: 40, style: .filled, rotation: -6)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("体験中")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Palette.shu)
                    Text("\(attributes.startedAt.formatted(date: .omitted, time: .shortened))から")
                        .font(.caption)
                        .foregroundStyle(Palette.ink3)
                    Spacer(minLength: 4)
                    Text(attributes.elementLabel)
                        .font(Typeface.fixedMincho(12))
                        .foregroundStyle(Palette.ink3)
                }
                Text(attributes.invitation)
                    .font(Typeface.fixedMincho(15, bold: false))
                    .lineSpacing(3)
                    .foregroundStyle(Palette.ink)
                    .lineLimit(3)
                if let question = state.reflectionQuestion {
                    Text(question)
                        .font(.caption)
                        .foregroundStyle(Palette.ink2)
                        .lineLimit(1)
                }
            }
        }
        .padding(16)
    }
}

#Preview("ロック画面", as: .content, using: ExperienceActivityAttributes(
    title: "いちばん遠くを見る",
    invitation: "少し手を止めて、窓の外のいちばん遠くにあるものを眺めてみませんか？",
    sealCharacter: "見",
    startedAt: Date(),
    elementLabel: "見る"
)) {
    ExperienceLiveActivity()
} contentStates: {
    ExperienceActivityAttributes.ContentState(reflectionQuestion: "いちばん遠くに、何が見えましたか？")
}
#endif
