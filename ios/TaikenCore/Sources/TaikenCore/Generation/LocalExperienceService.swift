import Foundation

/// 端末内だけで動く提案。Backend未設定・オフライン時・Apple Intelligence が使えないときに使う。
/// 体験ライブラリから、予定・気分・時間帯・最近の反応・体験の樹の芽に合うものを選ぶ。
/// AIの代わりを装わず、何を手がかりに選んだかを正直に書く。
public struct LocalExperienceService: ExperienceService {
    private let content: TaikenContent

    public init(content: TaikenContent = .shared) {
        self.content = content
    }

    public var isLocal: Bool { true }

    public func generateExperience(_ request: ExperienceRequest) async throws -> ExperienceResponse {
        LocalGenerator(content: content).response(for: request)
    }

    public func chat(_ request: ChatRequest) async throws -> ChatResponse {
        LocalCompanion(content: content).reply(to: request)
    }

    public func status() async throws -> ServiceStatus {
        throw AppError.notConfigured
    }
}

/// リクエストの時刻・タイムゾーンから、選ぶための手がかりを取り出す
struct LocalClock {
    let date: Date
    let calendar: Calendar

    init(currentTime: String, timeZone: String) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZone) ?? .current
        self.calendar = calendar
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]
        date = parser.date(from: currentTime) ?? Date()
    }

    var timeOfDay: TimeOfDay { TimeOfDay.at(date, calendar: calendar) }
    var day: Int { LibrarySelector.dayNumber(of: date, calendar: calendar) }
}

struct LocalGenerator {
    let content: TaikenContent

    func response(for request: ExperienceRequest) -> ExperienceResponse {
        let clock = LocalClock(currentTime: request.currentTime, timeZone: request.timeZone)
        let selector = LibrarySelector(content: content)
        let next = request.calendarContext.first { !$0.isAllDay && $0.day == .today }
        let choice = selector.choose(LibrarySelector.Input(
            day: clock.day,
            timeOfDay: clock.timeOfDay,
            eventTitle: next?.title,
            messages: request.recentUserMessages,
            mood: request.mood,
            feedback: request.userFeedback,
            recentTitles: Set(request.recentExperiences.map(\.title)),
            excludeTitles: Set(request.excludeTitles),
            buds: Set(request.tree?.buds ?? [])
        ))
        let picked = choice.experience
        let parent = Self.parent(of: picked, tree: request.tree, content: content)

        var observations: [SituationNote] = []
        var actions: [DetectedAction] = []
        if let next {
            let label = next.title.map { "「\($0)」の予定" } ?? "内容不明の予定"
            observations.append(SituationNote(text: "\(Self.clockText(next.start))から\(label)がある", basis: .calendar))
            actions.append(DetectedAction(label: next.title ?? "予定", basis: .calendar))
        }
        if let mood = request.mood {
            observations.append(SituationNote(text: "いまの気分に「\(mood.label)」を選んでいた", basis: .stated))
        } else if choice.mood == .tired {
            observations.append(SituationNote(text: "疲れや面倒さを口にしていた", basis: .stated))
            observations.append(SituationNote(text: "今日は負担の少ない提案が合うかもしれない", basis: .inferred))
        }
        if let parent {
            observations.append(SituationNote(text: "体験帳に「\(parent.title)」が記されている", basis: .stated))
        }

        let obligations = choice.themesFromEvent.intersection(["study", "work", "housework"])
        let obligationLabel = content.themes.first { obligations.contains($0.id) }?.label
        let summary: String = {
            let part = clock.timeOfDay.label
            guard let next else { return "目立った予定は見当たらない\(part)。" }
            return next.title.map { "「\($0)」が控えている\(part)。" } ?? "予定が控えている\(part)。"
        }()

        return ExperienceResponse(
            situation: Situation(summary: summary, observations: observations),
            detectedActions: actions,
            possibleObligations: obligationLabel.map { [PossibleObligation(label: "\($0)に取り組む必要がある可能性", likelihood: 0.6)] } ?? [],
            experienceOpportunities: [picked.perspective],
            isObligation: !obligations.isEmpty,
            confidence: next == nil ? 0.4 : 0.6,
            experience: Experience(
                title: picked.title,
                perspective: picked.perspective,
                invitation: picked.invitation,
                reason: Self.reason(for: choice, next: next, parent: parent, content: content),
                difficulty: picked.effort == "medium" ? .medium : .low,
                tags: picked.tags,
                reflectionQuestion: picked.reflectionQuestion,
                nodeID: picked.id,
                elements: picked.elements,
                growsFrom: parent?.id
            ),
            shouldNotify: false,
            notification: nil,
            source: .local
        )
    }

    /// 選んだ体験が伸びている、灯った体験 (樹のいまの「灯った体験」の順に、つながりを探す)
    static func parent(of picked: TaikenContent.LibraryExperience, tree: TreeContext?, content: TaikenContent) -> TreeContext.LivedNode? {
        guard let tree else { return nil }
        return tree.lived.first { lived in
            content.experience(lived.id)?.opens.contains { $0.to == picked.id } ?? false
        }
    }

    /// 何を手がかりに選んだかを正直に書く
    static func reason(
        for choice: LibrarySelector.Choice, next: CalendarItem?, parent: TreeContext.LivedNode?, content: TaikenContent
    ) -> String {
        if choice.moodWasChosen, let mood = choice.mood {
            let detail = switch mood {
            case .tired: "負担の少ないものを選びました。"
            case .bored: "小さな遊び心のあるものを選びました。"
            case .focus: "取り組んでいることを、少し違う角度から見るものにしました。"
            case .refresh: "感覚や視点を少し切り替えるものを選びました。"
            }
            return "「\(mood.label)」とのことなので、\(detail)"
        }
        if choice.matchesEvent {
            return next?.title.map { "「\($0)」の予定があるので、その時間の見方を少し変える提案にしました。" }
                ?? "このあとの予定に合わせて選びました。"
        }
        if choice.mood == .tired {
            return "疲れていると話していたので、負担の少ないものを選びました。"
        }
        if choice.matchesMessages {
            return "話していたことから選びました。"
        }
        if choice.isBud {
            if let parent {
                return "前に記した「\(parent.title)」の先にある体験です。"
            }
            if content.isRoot(choice.experience.id), let element = choice.experience.elements.first.flatMap(content.element) {
                return "「\(element.label)」の根にある、いちばん小さなかたちの体験です。"
            }
            return "あなたの体験の樹の、芽のひとつです。"
        }
        return "特別な予定がなくても、いつもの時間の中に体験は見つけられます。"
    }

    /// "2026-10-08T19:00:00+09:00" → "19:00"
    static func clockText(_ iso: String) -> String {
        guard let t = iso.firstIndex(of: "T") else { return iso }
        let start = iso.index(after: t)
        return String(iso[start...].prefix(5))
    }
}
