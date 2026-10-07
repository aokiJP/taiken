import Foundation
import XCTest
@testable import TaikenCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class BackendClientTests: XCTestCase {
    private let endpoint = BackendEndpoint(baseURL: URL(string: "https://taiken.example/api")!, token: "secret-token")

    private func client(_ transport: StubTransport, retry: RetryPolicy = RetryPolicy(), sleeps: SleepLog = SleepLog()) -> BackendClient {
        BackendClient(endpoint: endpoint, transport: transport, installID: "install-1", retry: retry, sleep: { sleeps.append($0) })
    }

    private func request() throws -> ExperienceRequest {
        try APICoding.decoder().decode(ExperienceRequest.self, from: Fixtures.data("experience_request.sample"))
    }

    func testSendsAuthenticatedJSONAndDecodes() async throws {
        let transport = StubTransport({ _ in (200, try Fixtures.data("experience_response.sample"), [:]) })
        let response = try await client(transport).generateExperience(try request())
        XCTAssertEqual(response.experience.title, "つまずきの観察")

        let sent = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(sent.url?.absoluteString, "https://taiken.example/api/v1/experience")
        XCTAssertEqual(sent.httpMethod, "POST")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "Bearer secret-token")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "X-Install-ID"), "install-1")
        XCTAssertNotNil(sent.value(forHTTPHeaderField: "X-Request-ID"))
        // Web検索を許可したリクエストは長めに待つ
        XCTAssertEqual(sent.timeoutInterval, 75)
        XCTAssertEqual(try jsonObject(XCTUnwrap(sent.httpBody)), try Fixtures.object("experience_request.sample"))
    }

    func testStatusUsesGETWithoutBody() async throws {
        let transport = StubTransport({ _ in (200, try Fixtures.data("status_response.sample"), [:]) })
        let status = try await client(transport).status()
        XCTAssertEqual(status.provider, "anthropic")
        XCTAssertEqual(transport.requests.first?.httpMethod, "GET")
        XCTAssertNil(transport.requests.first?.httpBody)
    }

    func testNoTokenSendsNoAuthorizationHeader() async throws {
        let transport = StubTransport({ _ in (200, try Fixtures.data("status_response.sample"), [:]) })
        let c = BackendClient(endpoint: BackendEndpoint(baseURL: endpoint.baseURL, token: ""), transport: transport, installID: "i")
        _ = try await c.status()
        XCTAssertNil(transport.requests.first?.value(forHTTPHeaderField: "Authorization"))
    }

    func testMapsHTTPErrors() async throws {
        let cases: [(Int, AppError)] = [
            (401, .unauthorized),
            (429, .rateLimited(retryAfter: 30)),
            (503, .unavailable(message: "リクエストが多すぎます。少し時間をおいてから試してください。")),
            (400, .server(message: "リクエストが多すぎます。少し時間をおいてから試してください。")),
        ]
        for (status, expected) in cases {
            let transport = StubTransport({ _ in (status, try Fixtures.data("error_response.sample"), [:]) })
            do {
                _ = try await client(transport, retry: .none).status()
                XCTFail("should throw for \(status)")
            } catch let error as AppError {
                XCTAssertEqual(error, expected, "status \(status)")
            }
        }
    }

    func testRetriesTransientErrorsOnceWithBackoff() async throws {
        let sleeps = SleepLog()
        let transport = StubTransport(
            { _ in throw URLError(.notConnectedToInternet) },
            { _ in (200, try Fixtures.data("status_response.sample"), [:]) }
        )
        _ = try await client(transport, sleeps: sleeps).status()
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(sleeps.values, [.milliseconds(600)])
        // 再試行ごとに別のリクエストIDを使う
        let ids = transport.requests.compactMap { $0.value(forHTTPHeaderField: "X-Request-ID") }
        XCTAssertEqual(Set(ids).count, 2)
    }

    func testRespectsRetryAfterForRateLimit() async throws {
        let sleeps = SleepLog()
        let body = Data(#"{"error":{"code":"rate_limited","message":"m","retry_after_seconds":3}}"#.utf8)
        let transport = StubTransport(
            { _ in (429, body, [:]) },
            { _ in (200, try Fixtures.data("status_response.sample"), [:]) }
        )
        _ = try await client(transport, sleeps: sleeps).status()
        XCTAssertEqual(sleeps.values, [.seconds(3)])
    }

    func testDoesNotRetryPermanentErrors() async {
        let transport = StubTransport({ _ in (401, Data(), [:]) })
        do {
            _ = try await client(transport).status()
            XCTFail("should throw")
        } catch {
            XCTAssertEqual(error as? AppError, .unauthorized)
        }
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testGivesUpAfterRetries() async {
        let transport = StubTransport({ _ in throw URLError(.timedOut) })
        do {
            _ = try await client(transport).status()
            XCTFail("should throw")
        } catch {
            XCTAssertEqual(error as? AppError, .offline)
        }
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testCancellationIsNotOffline() async {
        let transport = StubTransport({ _ in throw URLError(.cancelled) })
        do {
            _ = try await client(transport).status()
            XCTFail("should throw")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }
    }

    func testInvalidBodyIsInvalidResponse() async {
        let transport = StubTransport({ _ in (200, Data("<html>".utf8), [:]) })
        do {
            _ = try await client(transport).status()
            XCTFail("should throw")
        } catch {
            XCTAssertEqual(error as? AppError, .invalidResponse)
        }
    }

    func testRoutingServiceSwapsImplementation() async throws {
        let routing = RoutingExperienceService(LocalExperienceService())
        XCTAssertTrue(routing.isLocal)
        do {
            _ = try await routing.status()
            XCTFail("local has no status")
        } catch {
            XCTAssertEqual(error as? AppError, .notConfigured)
        }
        routing.replace(with: StubService())
        XCTAssertFalse(routing.isLocal)
        let status = try await routing.status()
        XCTAssertEqual(status.provider, "mock")
    }

    func testEndpointValidation() {
        XCTAssertNoThrow(try EndpointValidator.validate("https://my-mac.tail1234.ts.net").get())
        XCTAssertNoThrow(try EndpointValidator.validate("http://localhost:8787").get())
        XCTAssertNoThrow(try EndpointValidator.validate("http://192.168.1.20:8787").get())
        XCTAssertNoThrow(try EndpointValidator.validate("http://100.101.102.103:8787").get())
        XCTAssertNoThrow(try EndpointValidator.validate("http://my-mac.local:8787").get())
        XCTAssertEqual(EndpointValidator.validate("http://example.com"), .failure(.insecureRemote))
        XCTAssertEqual(EndpointValidator.validate("http://100.200.1.1"), .failure(.insecureRemote))
        XCTAssertEqual(EndpointValidator.validate("ftp://example.com"), .failure(.unsupportedScheme))
        XCTAssertEqual(EndpointValidator.validate("   "), .failure(.empty))
        XCTAssertEqual(EndpointValidator.validate("not a url"), .failure(.malformed))
    }
}

final class SleepLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Duration] = []
    var values: [Duration] { lock.withLock { stored } }
    func append(_ value: Duration) { lock.withLock { stored.append(value) } }
}
