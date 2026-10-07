import Foundation
import Synchronization

/// 体験生成の窓口。UIはこのプロトコル越しにしか通信しない。
public protocol ExperienceService: Sendable {
    func generateExperience(_ request: ExperienceRequest) async throws -> ExperienceResponse
    func chat(_ request: ChatRequest) async throws -> ChatResponse
    /// 接続テスト。端末内モードでは .notConfigured を投げる
    func status() async throws -> ServiceStatus
    /// 端末内の簡易生成か (Backend未設定)
    var isLocal: Bool { get }
}

extension ExperienceService {
    public var isLocal: Bool { false }
}

/// 接続先の設定変更に合わせて、中身 (Backend / 端末内) を差し替えられるサービス。
public final class RoutingExperienceService: ExperienceService {
    private let current: Mutex<any ExperienceService>

    public init(_ initial: any ExperienceService) {
        current = Mutex(initial)
    }

    public func replace(with service: any ExperienceService) {
        current.withLock { $0 = service }
    }

    private var target: any ExperienceService { current.withLock { $0 } }

    public var isLocal: Bool { target.isLocal }

    public func generateExperience(_ request: ExperienceRequest) async throws -> ExperienceResponse {
        try await target.generateExperience(request)
    }

    public func chat(_ request: ChatRequest) async throws -> ChatResponse {
        try await target.chat(request)
    }

    public func status() async throws -> ServiceStatus {
        try await target.status()
    }
}
