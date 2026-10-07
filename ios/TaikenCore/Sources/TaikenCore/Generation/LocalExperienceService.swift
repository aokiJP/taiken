import Foundation

/// 端末内だけで動く簡易生成。Backend未設定・オフライン時・プレビューで使う。
/// AIの代わりではなく「最低限UIが成り立つ」ためのもの。
public struct LocalExperienceService: ExperienceService {
    struct Idea: Sendable {
        let title: String
        let perspective: String
        let invitation: String
        let tags: [String]
    }

    public init() {}

    public var isLocal: Bool { true }

    static let themes: [(theme: String, words: [String])] = [
        ("勉強", ["課題", "宿題", "勉強", "授業", "試験", "テスト", "レポート", "講義"]),
        ("仕事", ["会議", "ミーティング", "MTG", "打ち合わせ", "仕事", "作業", "資料"]),
        ("移動", ["移動", "通勤", "通学", "電車", "バス", "出発"]),
        ("食事", ["ランチ", "昼食", "夕食", "朝食", "ご飯", "ごはん", "食事"]),
    ]

    static let ideas: [String: [Idea]] = [
        "勉強": [Idea(title: "つまずきの観察",
                      perspective: "「終わらせる作業」ではなく、自分がどこで手を止めるかを観察する時間として見てみる。",
                      invitation: "今日の勉強で、いちばん手が止まった瞬間を1つだけ覚えておいてみませんか？",
                      tags: ["new_perspective", "observation", "short"])],
        "仕事": [Idea(title: "一つの問いを持ち込む",
                      perspective: "予定をこなす場ではなく、ひとつの疑問の答えを探しに行く場として見てみる。",
                      invitation: "この予定に「今日これだけは知りたい」という問いを1つだけ持って臨んでみませんか？",
                      tags: ["question", "new_perspective"])],
        "移動": [Idea(title: "移動の中の変化",
                      perspective: "移動を「空白の時間」ではなく、いつもと違うものを見つける時間として捉える。",
                      invitation: "次の移動で、昨日までは気づかなかったものを1つ見つけてみませんか？",
                      tags: ["observation", "sensory", "short"])],
        "食事": [Idea(title: "ひと口目の観察",
                      perspective: "食事を「済ませるもの」ではなく、味や食感に気づく時間として見てみる。",
                      invitation: "次の食事で、ひと口目にどんな味がしたかを少しだけ意識してみませんか？",
                      tags: ["sensory", "short"])],
        "日常": [
            Idea(title: "いつもの中の違い",
                 perspective: "何気ない時間を、昨日との小さな違いを見つける時間として捉える。",
                 invitation: "今日のどこかで、昨日とは少し違うことを1つ見つけてみませんか？",
                 tags: ["observation", "short"]),
            Idea(title: "手を止める一瞬",
                 perspective: "次から次へ進む一日の中に、自分が何を感じているかに気づく間をつくる。",
                 invitation: "次の切り替わりの前に、今の自分の感覚を一度だけ確かめてみませんか？",
                 tags: ["reflection", "short"]),
        ],
    ]

    static func theme(of text: String?) -> String? {
        guard let text else { return nil }
        return themes.first { entry in entry.words.contains { text.contains($0) } }?.theme
    }

    static func idea(theme: String, excluding: [String]) -> Idea {
        let pool = (ideas[theme] ?? []) + (ideas["日常"] ?? [])
        return pool.first { !excluding.contains($0.title) } ?? pool[0]
    }

    public func generateExperience(_ request: ExperienceRequest) async throws -> ExperienceResponse {
        let next = request.calendarContext.first { !$0.isAllDay && $0.day == .today }
        let theme = Self.theme(of: next?.title) ?? "日常"
        let idea = Self.idea(theme: theme, excluding: request.excludeTitles)

        var observations: [SituationNote] = []
        var actions: [DetectedAction] = []
        if let next {
            let label = next.title.map { "「\($0)」の予定" } ?? "内容不明の予定"
            observations.append(SituationNote(text: "\(label)がある", basis: .calendar))
            actions.append(DetectedAction(label: next.title ?? "予定", basis: .calendar))
        }

        return ExperienceResponse(
            situation: Situation(summary: next == nil ? "目立った予定は見当たらない時間帯。" : "予定が控えている時間帯。", observations: observations),
            detectedActions: actions,
            possibleObligations: theme == "日常" ? [] : [PossibleObligation(label: "\(theme)に取り組む必要がある可能性", likelihood: 0.5)],
            experienceOpportunities: [idea.perspective],
            isObligation: theme == "勉強" || theme == "仕事",
            confidence: next == nil ? 0.3 : 0.5,
            experience: Experience(
                title: idea.title,
                perspective: idea.perspective,
                invitation: idea.invitation,
                reason: "端末内の簡易提案です。特別な予定がなくても、いつもの時間の中に体験は見つけられます。",
                difficulty: .low,
                tags: idea.tags
            ),
            shouldNotify: false,
            notification: nil,
            source: .local
        )
    }

    public func chat(_ request: ChatRequest) async throws -> ChatResponse {
        let said = request.messages.last?.text ?? ""
        return ChatResponse(
            reply: "今はサーバーに繋がっていないため、ちゃんとした返事ができません。接続が戻ったら、もう一度話しかけてください。",
            observations: said.isEmpty ? [] : [SituationNote(text: said, basis: .stated)],
            suggestExperience: false,
            experience: nil,
            source: .local
        )
    }

    public func status() async throws -> ServiceStatus {
        throw AppError.notConfigured
    }
}
