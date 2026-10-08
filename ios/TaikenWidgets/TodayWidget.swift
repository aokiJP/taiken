import SwiftUI
import TaikenCore
import WidgetKit

/// 今日の体験。アプリを開かなくても、今日の誘いかけを眺められる。
/// アプリが App Group に置いた状態を読むだけで、ウィジェットからは何も送らない
struct TodayWidget: Widget {
    static let kind = "TodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("今日の体験")
        .description("今日の誘いかけ。体験中は、その体験を。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
        .contentMarginsDisabled()
    }
}

struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), snapshot: .sample())
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        let now = Date()
        completion(TodayEntry(date: now, snapshot: context.isPreview ? .sample(now: now) : Self.current(now: now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date()
        let calendar = Calendar.current
        let snapshot = Self.current(now: now, calendar: calendar)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)

        // 空の色が変わる時刻ごとに描き直す。日付が変わったら読み直す (日付と提案が変わるため)
        var dates = [now]
        var cursor = now
        while true {
            let next = TimeOfDay.nextBoundary(after: cursor, calendar: calendar)
            guard next < tomorrow else { break }
            dates.append(next)
            cursor = next
        }
        completion(Timeline(entries: dates.map { TodayEntry(date: $0, snapshot: snapshot) }, policy: .after(tomorrow)))
    }

    /// App Group に置かれた状態。無いとき・古いときは、日付とひとことだけを出す
    static func current(now: Date, calendar: Calendar = .current) -> WidgetSnapshot {
        let empty = WidgetSnapshot(kind: .empty, updatedAt: now)
        guard let stored = AppGroup.widgetStore?.load() else { return empty }
        switch stored.kind {
        case .active:
            // 体験中の表示は半日まで (やめ忘れた体験を、いつまでも出さない)
            if let started = stored.startedAt, now.timeIntervalSince(started) < 12 * 3600 { return stored }
        case .proposal, .resting:
            if calendar.isDate(stored.updatedAt, inSameDayAs: now) { return stored }
        case .empty:
            break
        }
        return empty
    }
}

// MARK: - 表示

struct TodayWidgetView: View {
    let entry: TodayEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

    private var snapshot: WidgetSnapshot { entry.snapshot }
    private var palette: SkyPalette {
        TimeOfDay.at(entry.date, calendar: .current).sky(dark: colorScheme == .dark)
    }

    var body: some View {
        content
            .widgetURL(DeepLink.today.url)
            .containerBackground(for: .widget) {
                switch family {
                case .accessoryInline, .accessoryRectangular, .accessoryCircular:
                    Color.clear
                default:
                    StillSky(palette: palette)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            inline
        case .accessoryRectangular:
            rectangular
        case .systemMedium:
            medium
                .padding(16)
        default:
            small
                .padding(14)
        }
    }

    // MARK: 小

    private var hasExperience: Bool {
        snapshot.invitation != nil && (snapshot.kind == .proposal || snapshot.kind == .active)
    }

    @ViewBuilder
    private var small: some View {
        if let invitation = snapshot.invitation, hasExperience {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text(eyebrow)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(snapshot.kind == .active ? Palette.shu : palette.onSkySecondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    SealView(character: snapshot.sealCharacter ?? "体", size: 26, style: snapshot.kind == .active ? .filled : .outlined)
                }
                Spacer(minLength: 6)
                Text(invitation)
                    .font(Typeface.fixedMincho(14, bold: false))
                    .lineSpacing(3)
                    .foregroundStyle(palette.onSky)
                    .lineLimit(5)
                    .minimumScaleFactor(0.8)
                if let title = snapshot.title {
                    Text("— \(title)")
                        .font(Typeface.fixedMincho(11))
                        .foregroundStyle(palette.onSkySecondary)
                        .lineLimit(1)
                        .padding(.top, 6)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text(dateLine)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.onSkySecondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    SealView(character: "体", size: 26, style: .outlined, color: palette.onSky.opacity(0.7))
                }
                Spacer(minLength: 6)
                Text(restLine)
                    .font(Typeface.fixedMincho(15, bold: false))
                    .lineSpacing(3)
                    .foregroundStyle(palette.onSky)
                    .lineLimit(4)
                    .minimumScaleFactor(0.85)
                Text(snapshot.kind == .resting ? "今はひと休み" : "今日の体験をひらく")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.onSkySecondary)
                    .padding(.top, 6)
            }
        }
    }

    // MARK: 中

    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 6) {
                SealView(
                    character: hasExperience ? (snapshot.sealCharacter ?? "体") : "体", size: 46,
                    style: snapshot.kind == .active ? .filled : .outlined,
                    color: hasExperience ? Palette.shu : palette.onSky.opacity(0.7)
                )
                if let label = snapshot.elementLabel, hasExperience {
                    Text(label)
                        .font(Typeface.fixedMincho(11))
                        .foregroundStyle(palette.onSkySecondary)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(hasExperience ? eyebrow : dateLine)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(snapshot.kind == .active ? Palette.shu : palette.onSkySecondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                if let invitation = snapshot.invitation, hasExperience {
                    Text(invitation)
                        .font(Typeface.fixedMincho(15, bold: false))
                        .lineSpacing(4)
                        .foregroundStyle(palette.onSky)
                        .lineLimit(3)
                        .minimumScaleFactor(0.85)
                    if let title = snapshot.title {
                        Text("— \(title)")
                            .font(Typeface.fixedMincho(12))
                            .foregroundStyle(palette.onSkySecondary)
                            .padding(.top, 6)
                    }
                } else {
                    Text(restLine)
                        .font(Typeface.fixedMincho(16, bold: false))
                        .foregroundStyle(palette.onSky)
                        .lineLimit(2)
                    Text(snapshot.kind == .resting ? "今はひと休み。次の提案は、気が向いたときに。" : "今日の体験を受け取りにいく")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.onSkySecondary)
                        .padding(.top, 6)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: ロック画面

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(hasExperience ? eyebrow : "体験")
                .font(.caption2.weight(.semibold))
                .widgetAccentable()
                .lineLimit(1)
            if let invitation = snapshot.invitation, hasExperience {
                Text(invitation)
                    .font(.caption)
                    .lineLimit(3)
            } else {
                Text(snapshot.kind == .resting ? "今はひと休み" : "今日、何を体験できるか")
                    .font(.caption)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var inline: some View {
        if let title = snapshot.title, hasExperience {
            Text(snapshot.kind == .active ? "体験中 · \(title)" : title)
        } else {
            Text("今日の体験をひらく")
        }
    }

    /// 「10月8日 木曜日」
    private var dateLine: String {
        entry.date.formatted(.dateTime.month().day().weekday(.wide))
    }

    /// 提案の無いときのひとこと (時間帯で変える)
    private var restLine: String {
        switch TimeOfDay.at(entry.date, calendar: .current) {
        case .dawn, .morning: "いつもの朝に、まだ見ていない体験がある。"
        case .daytime: "いつもの昼に、まだ見ていない体験がある。"
        case .evening: "いつもの夕方に、まだ見ていない体験がある。"
        case .night, .lateNight: "いつもの夜に、まだ見ていない体験がある。"
        }
    }

    private var eyebrow: String {
        switch snapshot.kind {
        case .active:
            if let started = snapshot.startedAt {
                return "体験中 · \(started.formatted(date: .omitted, time: .shortened))から"
            }
            return "体験中"
        case .proposal:
            if let label = snapshot.elementLabel { return "今日の体験 · \(label)" }
            return "今日の体験"
        case .resting, .empty:
            return dateLine
        }
    }
}

#Preview(as: .systemSmall) {
    TodayWidget()
} timeline: {
    TodayEntry(date: Date(), snapshot: .sample())
    TodayEntry(date: Date(), snapshot: WidgetSnapshot(kind: .empty, updatedAt: Date()))
}

#Preview(as: .systemMedium) {
    TodayWidget()
} timeline: {
    TodayEntry(date: Date(), snapshot: .sample())
}
