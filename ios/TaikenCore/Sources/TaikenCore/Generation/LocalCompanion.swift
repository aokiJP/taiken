import Foundation

/// 端末内のかんたんな話し相手 (Backend未設定・Apple Intelligence が使えないとき)。
/// 気持ちを受け止めて短く返し、提案を求められたときだけライブラリから体験を1つ添える。
/// 強い苦痛のサインがあれば、提案はせず相談先の案内につなぐ。
struct LocalCompanion {
    let content: TaikenContent

    static let tiredReplies = [
        "そうなんですね。今は無理に何かしなくても大丈夫です。気が向いたら「何か提案して」と声をかけてください。",
        "おつかれさまです。休むのも、立派な過ごし方です。また話したくなったら、いつでもどうぞ。",
    ]
    static let listeningReplies = [
        "聞かせてくれてありがとうございます。このあと、何か予定していることはありますか？",
        "なるほど。今日はこのあと、どんな時間になりそうですか？",
        "そうなんですね。よければ、もう少し聞かせてください。",
    ]
    static let ideaReplies = [
        "それなら、いつもの時間を少し違う角度から見る提案をひとつ。合わなければ流してください。",
        "こんな見方はどうでしょう。気が向いたらで大丈夫です。",
    ]
    /// 提案を求めている言い方
    static let askingPattern = "暇|ひま|何か|なにか|何したら|何しよう|どうしよう|提案|おすすめ|アイデア|退屈"

    func reply(to request: ChatRequest) -> ChatResponse {
        let userTexts = request.messages.filter { $0.role == .user }.map(\.text)
        let last = userTexts.last ?? ""
        if SafetyCheck.needsCare(Array(userTexts.suffix(3))) {
            return ChatResponse(reply: CareMessage.reply, observations: [], suggestExperience: false, experience: nil, needsCare: true, source: .local)
        }

        let observations = last.isEmpty ? [] : [SituationNote(text: Self.truncated(last, 60), basis: .stated)]
        let selector = LibrarySelector(content: content)
        let mood = selector.detectMood([last])
        let themes = selector.detectThemes([last])
        let asks = !themes.isEmpty || SafetyCheck.matches(last, Self.askingPattern)
        let pick = Int(LibrarySelector.fnv1a(last) % 997)

        guard asks else {
            let pool = mood == .tired ? Self.tiredReplies : Self.listeningReplies
            return ChatResponse(reply: pool[pick % pool.count], observations: observations, suggestExperience: false, experience: nil, source: .local)
        }

        let clock = LocalClock(currentTime: request.currentTime, timeZone: request.timeZone)
        let next = request.calendarContext.first { !$0.isAllDay && $0.day == .today }
        let choice = selector.choose(LibrarySelector.Input(
            day: clock.day,
            timeOfDay: clock.timeOfDay,
            eventTitle: themes.isEmpty ? next?.title : nil,
            messages: [last],
            mood: mood,
            excludeTitles: Set([request.currentExperience?.title].compactMap { $0 })
        ))
        let picked = choice.experience
        let experience = Experience(
            title: picked.title,
            perspective: picked.perspective,
            invitation: picked.invitation,
            reason: "会話の中で話していたことから、小さく試せる視点を選びました。",
            difficulty: picked.effort == "medium" ? .medium : .low,
            tags: picked.tags,
            reflectionQuestion: picked.reflectionQuestion,
            nodeID: picked.id,
            elements: picked.elements
        )
        return ChatResponse(
            reply: Self.ideaReplies[pick % Self.ideaReplies.count],
            observations: observations,
            suggestExperience: true,
            experience: experience,
            source: .local
        )
    }

    static func truncated(_ text: String, _ limit: Int) -> String {
        text.count > limit ? "\(text.prefix(limit))…" : text
    }
}
