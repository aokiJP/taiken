import Foundation

/// 接続先URLの検証。平文 (http) はローカル・私的ネットワークだけに限る。
public enum EndpointValidator {
    public enum Problem: Error, Equatable, Sendable {
        case empty
        case malformed
        case unsupportedScheme
        case insecureRemote

        public var message: String {
            switch self {
            case .empty: "接続先のURLを入力してください。"
            case .malformed: "URLの形式が正しくありません。"
            case .unsupportedScheme: "https:// で始まるURLにしてください。"
            case .insecureRemote: "インターネット越しの接続は https にしてください (http は自宅ネットワークや Tailscale の中だけで使えます)。"
            }
        }
    }

    public static func validate(_ text: String) -> Result<URL, Problem> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), let host = url.host, !host.isEmpty else {
            return .failure(.malformed)
        }
        switch scheme {
        case "https":
            return .success(url)
        case "http":
            return isPrivateHost(host) ? .success(url) : .failure(.insecureRemote)
        default:
            return .failure(.unsupportedScheme)
        }
    }

    /// localhost / .local / 私的IPv4 / Tailscale (100.64.0.0/10)
    public static func isPrivateHost(_ host: String) -> Bool {
        let h = host.lowercased()
        if h == "localhost" || h.hasSuffix(".local") || h == "::1" { return true }
        let parts = h.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        switch (parts[0], parts[1]) {
        case (10, _), (127, _), (192, 168): return true
        case (172, 16...31): return true
        case (100, 64...127): return true
        default: return false
        }
    }
}
