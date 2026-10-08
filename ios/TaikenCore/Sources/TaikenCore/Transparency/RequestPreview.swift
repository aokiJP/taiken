import Foundation

/// 「次にAIへ渡す内容」を、人が読める形にする (設定画面と「AIが見たこと」から確かめられるように)。
/// 送るものを増やしたら、ここにも必ず表示を足す (テストで項目の網羅を確かめている)。
public enum RequestPreview {
    public struct Section: Sendable, Equatable, Identifiable {
        public let title: String
        public let items: [String]
        public var id: String { title }
    }

    public static let notSent = "送りません"

    public static func sections(for request: ExperienceRequest) -> [Section] {
        var sections: [Section] = [
            Section(title: "時刻", items: ["\(dateText(request.currentTime)) (\(request.timeZone))"]),
        ]
        sections.append(Section(title: "いまの気分", items: [request.mood?.label ?? "選んでいません"]))
        sections.append(Section(
            title: "予定",
            items: request.calendarContext.isEmpty ? [notSent] : request.calendarContext.map(calendarLine)
        ))
        sections.append(Section(
            title: "最近の発言",
            items: request.recentUserMessages.isEmpty ? [notSent] : request.recentUserMessages.map { "「\($0)」" }
        ))
        sections.append(Section(
            title: "最近の体験",
            items: request.recentExperiences.isEmpty ? [notSent] : request.recentExperiences.map(experienceLine)
        ))
        sections.append(Section(
            title: "反応の傾向",
            items: request.userFeedback.isEmpty ? [notSent] : request.userFeedback.map(feedbackLine)
        ))
        sections.append(Section(title: "技の樹", items: treeLines(request.tree)))
        sections.append(Section(title: "おおよその地域", items: [areaLine(request.area)]))
        sections.append(Section(title: "Web検索", items: [request.allowWebSearch ? "必要なときだけ使ってよい" : "使わない"]))
        if !request.excludeTitles.isEmpty {
            sections.append(Section(title: "今回は避ける体験", items: request.excludeTitles))
        }
        return sections
    }

    /// 実際に送る JSON (キーの順番を固定)
    public static func json(for request: ExperienceRequest) -> String {
        let encoder = APICoding.encoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(request) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: - 行の形

    static func dateText(_ iso: String) -> String {
        // 2026-10-08T18:10:00+09:00 → 2026-10-08 18:10
        guard let t = iso.firstIndex(of: "T") else { return iso }
        let date = iso[..<t]
        let time = iso[iso.index(after: t)...].prefix(5)
        return "\(date) \(time)"
    }

    static func calendarLine(_ item: CalendarItem) -> String {
        let day = item.day == .today ? "今日" : "明日"
        let when = item.isAllDay ? "終日" : "\(LocalGenerator.clockText(item.start))〜"
        let title = item.title ?? "(タイトルは送りません)"
        return "\(day) \(when) \(title)"
    }

    static func experienceLine(_ ref: ExperienceRef) -> String {
        let reaction: String = switch ref.reaction {
        case .accepted: "やってみた"
        case .completed: "終えた"
        case .declined: "今はやらない"
        case .alternative: "別の提案へ"
        case nil: "反応なし"
        }
        let rating = ref.rating.map { " · \($0.label)" } ?? ""
        return "\(ref.title) — \(reaction)\(rating)"
    }

    static func feedbackLine(_ signal: FeedbackSignal) -> String {
        let direction = signal.rating == .positive ? "良い反応が多め" : signal.rating == .negative ? "合わないことが多め" : "半々"
        return "\(ExperienceTag.label(signal.tag)): \(direction) (強さ \(String(format: "%.2f", signal.weight)))"
    }

    static func treeLines(_ tree: TreeContext?, content: TaikenContent = .shared) -> [String] {
        guard let tree, !tree.isEmpty else { return [notSent] }
        var lines: [String] = []
        if !tree.lived.isEmpty {
            let titles = tree.lived.prefix(5).map(\.title)
            let more = tree.lived.count > 5 ? " ほか\(tree.lived.count - 5)" : ""
            lines.append("記した体験: \(titles.joined(separator: "、"))\(more)")
        }
        if !tree.buds.isEmpty {
            let titles = tree.buds.prefix(5).map { content.experience($0)?.title ?? $0 }
            let more = tree.buds.count > 5 ? " ほか\(tree.buds.count - 5)" : ""
            lines.append("技の稽古: \(titles.joined(separator: "、"))\(more)")
        }
        return lines
    }

    static func areaLine(_ area: Area?) -> String {
        guard let area, let name = area.displayName else { return notSent }
        if let prefecture = area.administrativeArea, prefecture != name { return "\(name) (\(prefecture))" }
        return name
    }
}
