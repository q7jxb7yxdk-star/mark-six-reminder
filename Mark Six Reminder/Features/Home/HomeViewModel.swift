import Foundation
import Observation

/// Owns the homepage's loading and error state.
@MainActor
@Observable
final class HomeViewModel {
    private static let automaticRefreshInterval: TimeInterval = 15 * 60

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
    private let cache: DrawSnapshotCache
    private var hasLoaded = false
    private var lastSuccessfulRefreshAt: Date?
    private var resultIDsBeingFetched: Set<String> = []

    /// Creates a homepage model from the current app configuration.
    init(
        apiClient: JackpotAPIClient? = AppConfiguration.apiBaseURL.map(JackpotAPIClient.init),
        cache: DrawSnapshotCache = .shared
    ) {
        self.apiClient = apiClient
        self.cache = cache
    }

    /// Loads once when the homepage first appears.
    func loadIfNeeded(drawIDs: [String], pendingDrawDates: [String]) async {
        guard !hasLoaded else {
            return
        }

        hasLoaded = true
        await restoreCachedData(drawIDs: drawIDs)
        await refresh(drawIDs: drawIDs, pendingDrawDates: pendingDrawDates)
    }

    /// Refreshes Worker data unless a recent automatic refresh can be reused safely.
    func refresh(
        drawIDs: [String],
        pendingDrawDates: [String] = [],
        force: Bool = false
    ) async {
        guard !isLoading else {
            return
        }

        if !force, canReuseRecentRefresh(pendingDrawDates: pendingDrawDates) {
            await restoreCachedResults(drawIDs: drawIDs)
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
            let fetchedDraw = try await apiClient.currentDraw()
            let fetchedAt = Date()
            draw = fetchedDraw
            lastSuccessfulRefreshAt = fetchedAt
            await cache.saveCurrentDraw(fetchedDraw, fetchedAt: fetchedAt)
        } catch {
            errorMessage = error.localizedDescription
        }

        await loadResults(for: drawIDs)
    }

    /// Restores immutable results locally and only fetches draws which remain unpublished.
    func loadResults(for drawIDs: [String]) async {
        await restoreCachedResults(drawIDs: drawIDs)

        guard let apiClient else {
            return
        }

        let requestedIDs = Set(drawIDs)
        let fetchableIDs = requestedIDs.filter { drawID in
            drawsByID[drawID]?.hasPublishedResult != true
                && !resultIDsBeingFetched.contains(drawID)
        }
        guard !fetchableIDs.isEmpty else {
            return
        }

        resultIDsBeingFetched.formUnion(fetchableIDs)

        let fetchedDraws = await withTaskGroup(of: DrawInfo?.self) { group in
            for drawID in fetchableIDs {
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
        resultIDsBeingFetched.subtract(fetchableIDs)

        for fetchedDraw in fetchedDraws {
            drawsByID[fetchedDraw.id] = fetchedDraw
        }
        await cache.savePublishedResults(fetchedDraws)
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
            await refresh(drawIDs: drawIDs, force: true)
        }
    }

    /// Restores the latest current draw and published saved-draw results before networking.
    private func restoreCachedData(drawIDs: [String]) async {
        if let cachedCurrentDraw = await cache.currentDraw() {
            draw = cachedCurrentDraw.draw
            lastSuccessfulRefreshAt = cachedCurrentDraw.fetchedAt
        }
        await restoreCachedResults(drawIDs: drawIDs)
    }

    /// Replaces requested result state with complete results persisted on this device.
    private func restoreCachedResults(drawIDs: [String]) async {
        let requestedIDs = Set(drawIDs)
        drawsByID = drawsByID.filter { requestedIDs.contains($0.key) }

        let cachedResults = await cache.publishedResults(for: requestedIDs)
        drawsByID.merge(cachedResults) { _, cached in cached }
        await cache.retainPublishedResults(for: requestedIDs)
    }

    /// Indicates whether automatic refresh can avoid repeating recent network work safely.
    private func canReuseRecentRefresh(pendingDrawDates: [String]) -> Bool {
        guard let lastSuccessfulRefreshAt else {
            return false
        }

        let now = Date()
        let elapsed = now.timeIntervalSince(lastSuccessfulRefreshAt)
        guard elapsed >= 0 && elapsed < Self.automaticRefreshInterval else {
            return false
        }

        return !Self.resultRefreshTimePassed(
            drawDates: pendingDrawDates,
            after: lastSuccessfulRefreshAt,
            through: now
        )
    }

    /// Detects whether 21:40 or 21:50 passed while the app was backgrounded or throttled.
    private static func resultRefreshTimePassed(
        drawDates: [String],
        after previousRefresh: Date,
        through now: Date
    ) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = hongKongTimeZone

        let triggerTimes = [(hour: 21, minute: 40), (hour: 21, minute: 50)]
        return Set(drawDates).compactMap(parseISO8601).contains { drawDate in
            let dateComponents = calendar.dateComponents([.year, .month, .day], from: drawDate)
            return triggerTimes.contains { triggerTime in
                var components = dateComponents
                components.calendar = calendar
                components.timeZone = hongKongTimeZone
                components.hour = triggerTime.hour
                components.minute = triggerTime.minute
                components.second = 0

                guard let triggerDate = calendar.date(from: components) else {
                    return false
                }
                return triggerDate > previousRefresh && triggerDate <= now
            }
        }
    }

    /// Finds the next 21:40 or 21:50 Hong Kong refresh for saved draw dates.
    private static func nextResultRefreshDate(drawDates: [String], after now: Date) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = hongKongTimeZone

        let triggerTimes = [(hour: 21, minute: 40), (hour: 21, minute: 50)]
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
