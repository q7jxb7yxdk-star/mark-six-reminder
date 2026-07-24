import Foundation
import Observation

/// Owns the homepage's loading and error state.
@MainActor
@Observable
final class HomeViewModel {
    private static let hongKongTimeZone = TimeZone(identifier: "Asia/Hong_Kong")!

    private static let iso8601Formatter = ISO8601DateFormatter()

    private static let fractionalISO8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private(set) var draw: DrawInfo?
    private(set) var drawsByID: [String: DrawInfo] = [:]
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    private let apiClient: JackpotAPIClient?
    private var hasLoaded = false

    /// Creates a homepage model from the current app configuration.
    init(apiClient: JackpotAPIClient? = AppConfiguration.apiBaseURL.map(JackpotAPIClient.init)) {
        self.apiClient = apiClient
    }

    /// Loads once when the homepage first appears.
    func loadIfNeeded(drawIDs: [String]) async {
        guard !hasLoaded else {
            return
        }

        hasLoaded = true
        await refresh(drawIDs: drawIDs)
    }

    /// Replaces the visible snapshot and saved-entry results with Worker responses.
    func refresh(drawIDs: [String]) async {
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

        await loadResults(for: drawIDs)
    }

    /// Fetches each distinct saved draw without making one failed result hide the homepage.
    func loadResults(for drawIDs: [String]) async {
        guard let apiClient else {
            return
        }

        let requestedIDs = Set(drawIDs)
        drawsByID = drawsByID.filter { requestedIDs.contains($0.key) }

        let fetchedDraws = await withTaskGroup(of: DrawInfo?.self) { group in
            for drawID in requestedIDs {
                group.addTask {
                    try? await apiClient.draw(id: drawID)
                }
            }

            var values: [DrawInfo] = []
            for await value in group {
                if let value {
                    values.append(value)
                }
            }
            return values
        }

        for fetchedDraw in fetchedDraws {
            drawsByID[fetchedDraw.id] = fetchedDraw
        }
    }

    /// Returns the latest Worker snapshot for one locally saved entry.
    func drawResult(for drawID: String) -> DrawInfo? {
        drawsByID[drawID]
    }

    /// Waits for each pending draw's foreground refresh times and reloads its result.
    func runForegroundResultRefreshes(drawIDs: [String], drawDates: [String]) async {
        while !Task.isCancelled {
            guard let refreshDate = Self.nextResultRefreshDate(
                drawDates: drawDates,
                after: Date()
            ) else {
                return
            }

            let delay = max(0, refreshDate.timeIntervalSinceNow)
            do {
                try await Task.sleep(for: .seconds(delay), tolerance: .seconds(1))
            } catch {
                return
            }

            guard !Task.isCancelled else {
                return
            }
            await refresh(drawIDs: drawIDs)
        }
    }

    /// Finds the next 21:46 or 22:16 Hong Kong refresh for saved draw dates.
    private static func nextResultRefreshDate(drawDates: [String], after now: Date) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = hongKongTimeZone

        let triggerTimes = [(hour: 21, minute: 46), (hour: 22, minute: 16)]
        let candidates = Set(drawDates).compactMap(parseISO8601).flatMap { drawDate in
            let dateComponents = calendar.dateComponents([.year, .month, .day], from: drawDate)
            return triggerTimes.compactMap { triggerTime -> Date? in
                var components = dateComponents
                components.calendar = calendar
                components.timeZone = hongKongTimeZone
                components.hour = triggerTime.hour
                components.minute = triggerTime.minute
                components.second = 0
                return calendar.date(from: components)
            }
        }

        return candidates.filter { $0 > now }.min()
    }

    /// Parses the ISO 8601 timestamp variants returned by the Worker.
    private static func parseISO8601(_ value: String) -> Date? {
        fractionalISO8601Formatter.date(from: value) ?? iso8601Formatter.date(from: value)
    }
}
