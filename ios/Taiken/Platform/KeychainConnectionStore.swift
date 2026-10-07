import Foundation
import Security
import TaikenCore

/// 接続先の保存。URL は UserDefaults、トークンは Keychain (この端末のみ・バックアップで他端末へ移らない)。
final class KeychainConnectionStore: ConnectionStore, @unchecked Sendable {
    struct KeychainError: Error {
        let status: OSStatus
    }

    private let defaults: UserDefaults
    private let service: String
    private let account = "client-token"
    private let urlKey = "connection.baseURL"
    private let disconnectedKey = "connection.disconnected"
    /// 開発用の既定URL (xcconfig)。ユーザーが一度も設定していないときだけ使う
    private let developmentDefault: URL?

    init(defaults: UserDefaults = .standard, service: String = "com.example.taiken.backend", developmentDefault: URL?) {
        self.defaults = defaults
        self.service = service
        self.developmentDefault = developmentDefault
    }

    func load() -> BackendEndpoint? {
        if let text = defaults.string(forKey: urlKey), let url = URL(string: text) {
            return BackendEndpoint(baseURL: url, token: readToken())
        }
        guard !defaults.bool(forKey: disconnectedKey), let url = developmentDefault else { return nil }
        return BackendEndpoint(baseURL: url, token: readToken())
    }

    func save(_ endpoint: BackendEndpoint) throws {
        if let token = endpoint.token {
            try writeToken(token)
        } else {
            try deleteToken()
        }
        defaults.set(endpoint.baseURL.absoluteString, forKey: urlKey)
        defaults.set(false, forKey: disconnectedKey)
    }

    func clear() throws {
        try deleteToken()
        defaults.removeObject(forKey: urlKey)
        defaults.set(true, forKey: disconnectedKey)
    }

    // MARK: - Keychain

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func readToken() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func writeToken(_ token: String) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: Data(token.utf8),
            // 再起動後の初回ロック解除以降はバックグラウンド更新からも読める。iCloudキーチェーンには同期しない
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(baseQuery.merging(attributes) { $1 } as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    private func deleteToken() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}
