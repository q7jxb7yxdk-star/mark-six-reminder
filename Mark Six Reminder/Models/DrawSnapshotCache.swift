import Foundation

/// Persists the latest draw snapshot and immutable published results on this device.
actor DrawSnapshotCache {
    static let shared = DrawSnapshotCache()

    private enum StorageKey {
        static let currentDraw = "drawCache.current"
        static let publishedResults = "drawCache.publishedResults"
    }

    private struct CachedCurrentDraw: Codable {
        let draw: DrawInfo
        let fetchedAt: Date
    }

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    /// Creates a cache backed by the supplied defaults store.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Returns the most recently downloaded current draw and its local fetch time.
    func currentDraw() -> (draw: DrawInfo, fetchedAt: Date)? {
        guard let cached: CachedCurrentDraw = decode(forKey: StorageKey.currentDraw) else {
            return nil
        }

        return (cached.draw, cached.fetchedAt)
    }

    /// Saves a successful current-draw response with the time it reached this device.
    func saveCurrentDraw(_ draw: DrawInfo, fetchedAt: Date) {
        encode(
            CachedCurrentDraw(draw: draw, fetchedAt: fetchedAt),
            forKey: StorageKey.currentDraw
        )
    }

    /// Returns complete official results for the requested saved draw identifiers.
    func publishedResults(for drawIDs: Set<String>) -> [String: DrawInfo] {
        let storedResults: [String: DrawInfo] = decode(
            forKey: StorageKey.publishedResults
        ) ?? [:]

        return storedResults.filter { drawIDs.contains($0.key) && $0.value.hasPublishedResult }
    }

    /// Merges newly published results into the persistent device cache.
    func savePublishedResults(_ draws: [DrawInfo]) {
        let publishedDraws = draws.filter(\.hasPublishedResult)
        guard !publishedDraws.isEmpty else {
            return
        }

        var storedResults: [String: DrawInfo] = decode(
            forKey: StorageKey.publishedResults
        ) ?? [:]
        for draw in publishedDraws {
            storedResults[draw.id] = draw
        }
        encode(storedResults, forKey: StorageKey.publishedResults)
    }

    /// Removes cached results which no longer have a corresponding saved-number record.
    func retainPublishedResults(for drawIDs: Set<String>) {
        let storedResults: [String: DrawInfo] = decode(
            forKey: StorageKey.publishedResults
        ) ?? [:]
        let retainedResults = storedResults.filter { drawIDs.contains($0.key) }

        guard retainedResults.count != storedResults.count else {
            return
        }
        encode(retainedResults, forKey: StorageKey.publishedResults)
    }

    /// Encodes one cache value and clears the key if encoding unexpectedly fails.
    private func encode<Value: Encodable>(_ value: Value, forKey key: String) {
        do {
            defaults.set(try encoder.encode(value), forKey: key)
        } catch {
            defaults.removeObject(forKey: key)
        }
    }

    /// Decodes one cache value and discards corrupted local data safely.
    private func decode<Value: Decodable>(forKey key: String) -> Value? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }

        do {
            return try decoder.decode(Value.self, from: data)
        } catch {
            defaults.removeObject(forKey: key)
            return nil
        }
    }
}
