import Foundation

/// The single network entry point for the entire app — this is a product promise,
/// not a style choice. `Scripts/check_network_policy.sh` fails the build if any
/// networking API appears outside this directory. See docs/NETWORK_POLICY.md.
struct NetworkClient: Sendable {
    enum NetworkPolicyViolation: Error {
        case disallowedHost(String)
    }

    /// License validation only. Sparkle's update check runs inside the Sparkle
    /// framework against the appcast host and is disclosed in the network policy.
    static let allowedHosts: Set<String> = [
        "api.lemonsqueezy.com"
    ]

    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        self.session = URLSession(configuration: configuration)
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        guard let host = request.url?.host(), Self.allowedHosts.contains(host) else {
            throw NetworkPolicyViolation.disallowedHost(request.url?.host() ?? "<nil>")
        }
        return try await session.data(for: request)
    }
}
