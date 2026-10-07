import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 接続先。URLはユーザー設定、トークンはKeychainに保存する (アプリ本体には埋め込まない)。
public struct BackendEndpoint: Sendable, Equatable {
    public var baseURL: URL
    public var token: String?

    public init(baseURL: URL, token: String?) {
        self.baseURL = baseURL
        self.token = token?.isEmpty == true ? nil : token
    }
}

/// HTTP送受信の抽象 (テストで差し替える)
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral // Cookie・キャッシュを残さない
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        session = URLSession(configuration: configuration)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AppError.invalidResponse }
        return (data, http)
    }
}

/// 一時的な失敗だけを1回だけ再試行する (サーバー側でもAI APIへの再試行をしているため控えめに)
public struct RetryPolicy: Sendable {
    public var maxRetries: Int
    public var baseDelay: Duration
    public var maxDelay: Duration

    public init(maxRetries: Int = 1, baseDelay: Duration = .milliseconds(600), maxDelay: Duration = .seconds(5)) {
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }

    public static let none = RetryPolicy(maxRetries: 0)
}

/// iOS → 自分のBackend → AI API。AI APIキーはBackendだけが持つ。
public struct BackendClient: ExperienceService {
    public typealias Sleeper = @Sendable (Duration) async throws -> Void

    private let endpoint: BackendEndpoint
    private let transport: any HTTPTransport
    private let installID: String
    private let retry: RetryPolicy
    private let sleep: Sleeper
    private let diagnostics: any Diagnostics

    public init(
        endpoint: BackendEndpoint,
        transport: any HTTPTransport = URLSessionTransport(),
        installID: String,
        retry: RetryPolicy = RetryPolicy(),
        diagnostics: any Diagnostics = NoopDiagnostics(),
        sleep: @escaping Sleeper = { try await Task.sleep(for: $0) }
    ) {
        self.endpoint = endpoint
        self.transport = transport
        self.installID = installID
        self.retry = retry
        self.sleep = sleep
        self.diagnostics = diagnostics
    }

    public func generateExperience(_ request: ExperienceRequest) async throws -> ExperienceResponse {
        // Web検索を伴うと時間がかかるため長めに待つ
        try await call("POST", "v1/experience", body: request, timeout: request.allowWebSearch ? 75 : 55)
    }

    public func chat(_ request: ChatRequest) async throws -> ChatResponse {
        try await call("POST", "v1/chat", body: request, timeout: 45)
    }

    public func status() async throws -> ServiceStatus {
        try await call("GET", "v1/status", body: Optional<ExperienceRequest>.none, timeout: 10)
    }

    private func call<Body: Encodable, Response: Decodable>(_ method: String, _ path: String, body: Body?, timeout: TimeInterval) async throws -> Response {
        var request = URLRequest(url: endpoint.baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(installID, forHTTPHeaderField: "X-Install-ID")
        if let token = endpoint.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try APICoding.encoder().encode(body)
        }

        var attempt = 0
        while true {
            let requestID = UUID().uuidString.lowercased()
            request.setValue(requestID, forHTTPHeaderField: "X-Request-ID")
            do {
                return try await once(request, path: path, requestID: requestID)
            } catch let error as AppError where error.isTransient && attempt < retry.maxRetries {
                attempt += 1
                let delay = retryDelay(for: error, attempt: attempt)
                diagnostics.record("backend.retry", ["path": path, "attempt": String(attempt)])
                try await sleep(delay)
            }
        }
    }

    private func retryDelay(for error: AppError, attempt: Int) -> Duration {
        if case .rateLimited(let seconds?) = error {
            return min(.seconds(seconds), retry.maxDelay)
        }
        let exponential = retry.baseDelay * Int(pow(2.0, Double(attempt - 1)))
        return min(exponential, retry.maxDelay)
    }

    private func once<Response: Decodable>(_ request: URLRequest, path: String, requestID: String) async throws -> Response {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as AppError {
            throw error
        } catch {
            diagnostics.record("backend.offline", ["path": path, "request_id": requestID])
            throw AppError.offline
        }

        let decoder = APICoding.decoder()
        guard (200..<300).contains(response.statusCode) else {
            let detail = try? decoder.decode(APIErrorBody.self, from: data).error
            diagnostics.record("backend.http_error", [
                "path": path, "status": String(response.statusCode),
                "code": detail?.code ?? "-", "request_id": detail?.requestId ?? requestID,
            ])
            throw Self.map(status: response.statusCode, detail: detail)
        }
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            diagnostics.record("backend.decode_error", ["path": path, "request_id": requestID])
            throw AppError.invalidResponse
        }
    }

    static func map(status: Int, detail: APIErrorBody.Detail?) -> AppError {
        let message = detail?.message ?? "サーバーでエラーが発生しました。"
        switch status {
        case 401, 403: return .unauthorized
        case 429: return .rateLimited(retryAfter: detail?.retryAfterSeconds)
        case 502, 503, 504: return .unavailable(message: message)
        default: return .server(message: message)
        }
    }
}
