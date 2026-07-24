import Foundation

/// Resolves build-time and launch-time values used by the app.
enum AppConfiguration {
    /// Returns the Worker base URL, preferring an Xcode launch environment override.
    static var apiBaseURL: URL? {
        let environmentValue = ProcessInfo.processInfo.environment["JACKPOT_API_BASE_URL"]
        let infoValue = Bundle.main.object(forInfoDictionaryKey: "JACKPOT_API_BASE_URL") as? String

        return makeURL(from: environmentValue) ?? makeURL(from: infoValue)
    }

    /// Converts a non-empty configuration string into a validated HTTP URL.
    private static func makeURL(from rawValue: String?) -> URL? {
        guard let rawValue else {
            return nil
        }

        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              !value.contains("$("),
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || (scheme == "http" && url.isLoopbackURL) else {
            return nil
        }

        return url
    }
}

private extension URL {
    /// Indicates whether an HTTP URL is limited to local development.
    var isLoopbackURL: Bool {
        host == "127.0.0.1" || host == "localhost" || host == "::1"
    }
}
