import Foundation
import Observation

public struct ChatMessage: Identifiable, Hashable, Sendable {
    public enum Role: Sendable { case user, assistant }

    public let id: UUID
    public let role: Role
    public let text: String
    public var observations: [SituationNote]
    public var suggestion: Experience?
    public var suggestionHandled: Bool
    /// 強い苦痛のサインがあった返答。画面に相談先の案内を出す
    public var needsCare: Bool
    /// 送信に失敗したユーザーの発言
    public var failed: Bool

    public init(id: UUID = UUID(), role: Role, text: String, observations: [SituationNote] = [], suggestion: Experience? = nil, needsCare: Bool = false) {
        self.id = id
        self.role = role
        self.text = text
        self.observations = observations
        self.suggestion = suggestion
        self.suggestionHandled = false
        self.needsCare = needsCare
        self.failed = false
    }
}

/// AIチャット (指示書 §7)。会話は端末にも保存しない。
@MainActor
@Observable
public final class ChatViewModel {
    /// 話しはじめのきっかけ (タップするとそのまま送る)
    public static let quickReplies = ["ちょっと疲れた", "ひまだな", "これから勉強する", "気分を変えたい", "何か提案して"]

    public static func greeting(for time: TimeOfDay) -> String {
        switch time {
        case .dawn, .morning: "おはようございます。今日はどんな一日になりそうですか？"
        case .daytime: "こんにちは。いま、どんな感じですか？ 疲れた、ひま、面倒…なんでも大丈夫です。"
        case .evening: "こんばんは。今日はどんな一日でしたか？"
        case .night: "おつかれさまです。今日のこと、少し話していきますか？"
        case .lateNight: "静かな夜ですね。少しだけ話してから、休みますか？"
        }
    }

    public private(set) var greeting: String
    public private(set) var messages: [ChatMessage]
    public var draft = ""
    public private(set) var isSending = false
    public private(set) var errorMessage: String?

    private let service: any ExperienceService
    private let assembler: ContextAssembler
    private let history: any HistoryRepository
    private let diagnostics: any Diagnostics
    private let onAdopt: @MainActor (Experience) -> Void

    public init(
        service: any ExperienceService,
        assembler: ContextAssembler,
        history: any HistoryRepository,
        diagnostics: any Diagnostics = NoopDiagnostics(),
        onAdopt: @escaping @MainActor (Experience) -> Void
    ) {
        self.service = service
        self.assembler = assembler
        self.history = history
        self.diagnostics = diagnostics
        self.onAdopt = onAdopt
        let greeting = Self.greeting(for: TimeOfDay.at(assembler.currentDate, calendar: assembler.calendar))
        self.greeting = greeting
        messages = [ChatMessage(role: .assistant, text: greeting)]
    }

    public var canSend: Bool {
        !isSending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// まだ何も話していないときだけ、きっかけの言葉を出す
    public var showsQuickReplies: Bool {
        !isSending && !messages.contains { $0.role == .user }
    }

    public func send(quickReply text: String) async {
        guard !isSending else { return }
        draft = text
        await send()
    }

    /// 直近の返答で苦痛のサインがあったか (画面上部に相談先を出し続ける)
    public var showsCareResources: Bool {
        messages.contains { $0.needsCare }
    }

    public func send() async {
        let text = String(draft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        guard !text.isEmpty, !isSending else { return }
        draft = ""
        messages.append(ChatMessage(role: .user, text: text))
        await deliver(text)
    }

    /// 送信に失敗した発言をもう一度送る
    public func retry(_ message: ChatMessage) async {
        guard message.failed, !isSending, let index = messages.firstIndex(where: { $0.id == message.id }) else { return }
        messages[index].failed = false
        await deliver(message.text)
    }

    private func deliver(_ text: String) async {
        errorMessage = nil
        isSending = true
        defer { isSending = false }
        assembler.rememberUtterance(text)

        let turns = messages
            .filter { !$0.failed }
            .map { ChatTurn(role: $0.role == .user ? .user : .assistant, text: $0.text) }
        do {
            let response = try await service.chat(assembler.chatRequest(turns: turns))
            messages.append(ChatMessage(
                role: .assistant,
                text: response.reply,
                observations: response.observations,
                suggestion: response.suggestExperience ? response.experience : nil,
                needsCare: response.needsCare
            ))
        } catch is CancellationError {
            return
        } catch {
            diagnostics.record("chat.failed", ["error": String(describing: error)])
            if let index = messages.lastIndex(where: { $0.role == .user && $0.text == text }) {
                messages[index].failed = true
            }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? "送信できませんでした。"
        }
    }

    public func adopt(_ message: ChatMessage) {
        guard let experience = message.suggestion, markHandled(message) else { return }
        onAdopt(experience)
        messages.append(ChatMessage(role: .assistant, text: "ホームの「体験中」に置いておきました。終わったら、体験帳に記してみてください。"))
    }

    public func dismissSuggestion(_ message: ChatMessage) {
        guard let experience = message.suggestion, markHandled(message) else { return }
        do {
            try history.record(experience, theme: nil, status: .declined, at: assembler.currentDate)
        } catch {
            diagnostics.record("chat.persist_failed")
        }
    }

    /// 会話を最初からにする (端末に残っている会話は無い)
    public func reset() {
        greeting = Self.greeting(for: TimeOfDay.at(assembler.currentDate, calendar: assembler.calendar))
        messages = [ChatMessage(role: .assistant, text: greeting)]
        draft = ""
        errorMessage = nil
    }

    @discardableResult
    private func markHandled(_ message: ChatMessage) -> Bool {
        guard let index = messages.firstIndex(where: { $0.id == message.id }), !messages[index].suggestionHandled else { return false }
        messages[index].suggestionHandled = true
        return true
    }
}
