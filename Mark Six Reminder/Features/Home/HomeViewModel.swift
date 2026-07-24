import Foundation
import Observation

/// Owns the homepage's loading and error state.
@MainActor
@Observable
final class HomeViewModel {
    private(set) var draw: DrawInfo?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let apiClient: JackpotAPIClient?
    private var hasLoaded = false

    /// Creates a homepage model from the current app configuration.
    init(apiClient: JackpotAPIClient? = AppConfiguration.apiBaseURL.map(JackpotAPIClient.init)) {
        self.apiClient = apiClient
    }

    /// Loads once when the homepage first appears.
    func loadIfNeeded() async {
        guard !hasLoaded else {
            return
        }

        hasLoaded = true
        await refresh()
    }

    /// Replaces the visible snapshot with the latest Worker response.
    func refresh() async {
        guard !isLoading else {
            return
        }

        guard let apiClient else {
            errorMessage = JackpotAPIError.invalidConfiguration.localizedDescription
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            draw = try await apiClient.currentDraw()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
