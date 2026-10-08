import Foundation

/// 端末内で生成する提案 (Apple Intelligence など) を安全に使うための包み。
/// - 強い苦痛のサインがある会話は、生成させずに相談先の案内につなぐ
/// - 危険な提案は Backend と同じパターンで除き、ライブラリの提案に差し替える
/// - 生成に失敗したら、ライブラリの提案に切り替える (アプリを止めない)
public struct SafeguardedExperienceService: ExperienceService {
    private let primary: any ExperienceService
    private let fallback: any ExperienceService
    private let diagnostics: any Diagnostics

    public init(primary: any ExperienceService, fallback: any ExperienceService = LocalExperienceService(), diagnostics: any Diagnostics = NoopDiagnostics()) {
        self.primary = primary
        self.fallback = fallback
        self.diagnostics = diagnostics
    }

    public var isLocal: Bool { primary.isLocal }

    public func generateExperience(_ request: ExperienceRequest) async throws -> ExperienceResponse {
        let response: ExperienceResponse
        do {
            response = try await primary.generateExperience(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            diagnostics.record("safeguard.primary_failed", ["kind": "experience"])
            return try await fallback.generateExperience(request)
        }
        if let issue = SafetyCheck.issue(in: response.experience) {
            diagnostics.record("safeguard.unsafe", ["label": issue])
            return try await fallback.generateExperience(request)
        }
        return response
    }

    public func chat(_ request: ChatRequest) async throws -> ChatResponse {
        let recent = request.messages.filter { $0.role == .user }.suffix(3).map(\.text)
        if SafetyCheck.needsCare(Array(recent)) {
            return try await fallback.chat(request)
        }
        let response: ChatResponse
        do {
            response = try await primary.chat(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            diagnostics.record("safeguard.primary_failed", ["kind": "chat"])
            return try await fallback.chat(request)
        }
        if let experience = response.experience, let issue = SafetyCheck.issue(in: experience) {
            diagnostics.record("safeguard.unsafe", ["label": issue])
            return ChatResponse(
                reply: response.reply, observations: response.observations, suggestExperience: false, experience: nil,
                needsCare: response.needsCare, source: response.source, fallbackReason: response.fallbackReason
            )
        }
        return response
    }

    public func status() async throws -> ServiceStatus {
        try await primary.status()
    }
}
