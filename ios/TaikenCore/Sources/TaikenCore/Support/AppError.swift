import Foundation

public enum AppError: LocalizedError, Equatable, Sendable {
    case offline
    case notConfigured
    case unauthorized
    case rateLimited(retryAfter: Int?)
    case unavailable(message: String)
    case server(message: String)
    case invalidResponse
    case storage

    public var errorDescription: String? {
        switch self {
        case .offline:
            "ネットワークに接続できません。"
        case .notConfigured:
            "接続先が設定されていません。"
        case .unauthorized:
            "接続先に認証されませんでした。設定のトークンを確認してください。"
        case .rateLimited(let seconds):
            seconds.map { "少し時間をおいてから試してください (約\($0)秒)。" } ?? "少し時間をおいてから試してください。"
        case .unavailable(let message), .server(let message):
            message
        case .invalidResponse:
            "サーバーの応答を読み取れませんでした。"
        case .storage:
            "端末への保存に失敗しました。"
        }
    }

    /// もう一度試せば成功する見込みがあるか
    public var isTransient: Bool {
        switch self {
        case .offline, .rateLimited, .unavailable: true
        default: false
        }
    }
}

/// 診断ログ。ユーザーの内容 (予定・発言・体験文) は渡さない。
public protocol Diagnostics: Sendable {
    func record(_ event: String, _ fields: [String: String])
}

public struct NoopDiagnostics: Diagnostics {
    public init() {}
    public func record(_ event: String, _ fields: [String: String]) {}
}

extension Diagnostics {
    public func record(_ event: String) { record(event, [:]) }
}
