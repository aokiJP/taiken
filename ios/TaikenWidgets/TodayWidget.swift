import SwiftUI
import TaikenCore
import WidgetKit

/// 今日の体験。アプリを開かなくても、今日の誘いかけと七十二候を眺められる。
/// アプリが App Group に置いた状態を読むだけで、ウィジェットからは何も送らない
struct TodayWidget: Widget {
    static let kind = "TodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: Self.kind, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("今日の体験")
        .description("今日の誘いかけと、七十二候。体験中は、その体験を。")
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

        // 空の色が変わる時刻ごとに描き直す。日付が変わったら読み直す (七十二候と提案が変わるため)
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

    /// App Group に置かれた状態。無いとき・古いときは、今日の季節だけを出す
    static func current(now: Date, calendar: Calendar = .current) -> WidgetSnapshot {
        let empty = WidgetSnapshot(kind: .empty, season: MicroSeason.at(now, calendar: calendar), updatedAt: now)
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

    @ViewBuilder
    private var small: some View {
        if let invitation = snapshot.invitation, snapshot.kind == .proposal || snapshot.kind == .active {
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
            HStack(alignment: .top, spacing: 10) {
                TanzakuView(text: snapshot.microSeason, size: 17, foreground: palette.onSky, border: palette.onSky.opacity(0.28))
                VStack(alignment: .trailing, spacing: 4) {
                    Text(snapshot.solarTerm)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.onSkySecondary)
                    Spacer(minLength: 4)
                    Text(snapshot.microSeasonMeaning)
                        .font(Typeface.fixedMincho(13, bold: false))
                        .foregroundStyle(palette.onSky)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(4)
                    Text(snapshot.kind == .resting ? "今はひと休み" : "今日の体験をひらく")
                        .font(.system(size: 10))
                        .foregroundStyle(palette.onSkySecondary)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    // MARK: 中

    private var medium: some View {
        HStack(alignment: .top, spacing: 16) {
            TanzakuView(text: snapshot.microSeason, size: 18, foreground: palette.onSky, border: palette.onSky.opacity(0.28))
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 8) {
                    Text(eyebrow)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(snapshot.kind == .active ? Palette.shu : palette.onSkySecondary)
                    Spacer(minLength: 4)
                    if let seal = snapshot.sealCharacter, snapshot.kind != .empty {
                        SealView(character: seal, size: 28, style: snapshot.kind == .active ? .filled : .outlined)
                    }
                }
                Spacer(minLength: 6)
                if let invitation = snapshot.invitation, snapshot.kind == .proposal || snapshot.kind == .active {
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
                    Text(snapshot.microSeasonMeaning)
                        .font(Typeface.fixedMincho(16, bold: false))
                        .foregroundStyle(palette.onSky)
                        .lineLimit(2)
                    Text(snapshot.kind == .resting ? "今はひと休み。次の提案は、気が向いたときに。" : "今日の体験を受け取りにいく")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.onSkySecondary)
                        .padding(.top, 6)
                }
            }
        }
    }

    // MARK: ロック画面

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(snapshot.kind == .active ? "体験中 · \(snapshot.microSeason)" : "\(snapshot.solarTerm) · \(snapshot.microSeason)")
                .font(.caption2.weight(.semibold))
                .widgetAccentable()
                .lineLimit(1)
            if let invitation = snapshot.invitation, snapshot.kind == .proposal || snapshot.kind == .active {
                Text(invitation)
                    .font(.caption)
                    .lineLimit(3)
            } else {
                Text(snapshot.microSeasonMeaning)
                    .font(.caption)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var inline: some View {
        if let title = snapshot.title, snapshot.kind == .proposal || snapshot.kind == .active {
            Text("\(snapshot.microSeason) · \(title)")
        } else {
            Text("\(snapshot.solarTerm) · \(snapshot.microSeason)")
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
            return "今日の体験 · \(snapshot.microSeason)"
        case .resting, .empty:
            return "\(snapshot.solarTerm) · \(snapshot.microSeason)"
        }
    }
}

#Preview(as: .systemSmall) {
    TodayWidget()
} timeline: {
    TodayEntry(date: Date(), snapshot: .sample())
    TodayEntry(date: Date(), snapshot: WidgetSnapshot(kind: .empty, season: MicroSeason.entry(48), updatedAt: Date()))
}

#Preview(as: .systemMedium) {
    TodayWidget()
} timeline: {
    TodayEntry(date: Date(), snapshot: .sample())
}
