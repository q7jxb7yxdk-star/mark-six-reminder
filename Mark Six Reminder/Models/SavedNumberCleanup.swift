import Foundation
import SwiftData

/// Removes locally saved selections which precede the current official draw.
@MainActor
enum SavedNumberCleanup {
    private static let hongKongTimeZone = TimeZone(identifier: "Asia/Hong_Kong")!

    private static let iso8601Formatter = ISO8601DateFormatter()

    private static let fractionalISO8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Returns the start of the supplied draw day in Hong Kong.
    static func cleanupDate(for currentDraw: DrawInfo) -> Date? {
        guard let currentDrawDate = parseISO8601(currentDraw.drawDate) else {
            return nil
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = hongKongTimeZone
        return calendar.startOfDay(for: currentDrawDate)
    }

    /// Deletes older entries only after the supplied current draw day begins in Hong Kong.
    static func deleteEntries(
        before currentDraw: DrawInfo,
        from entries: [SavedNumberEntry],
        in modelContext: ModelContext,
        asOf now: Date = Date()
    ) throws {
        guard
            let currentDrawDate = parseISO8601(currentDraw.drawDate),
            let cleanupDate = cleanupDate(for: currentDraw),
            now >= cleanupDate
        else {
            return
        }

        let oldEntries = entries.filter { entry in
            guard let entryDrawDate = parseISO8601(entry.drawDate) else {
                return false
            }
            return entryDrawDate < currentDrawDate
        }

        guard !oldEntries.isEmpty else {
            return
        }

        oldEntries.forEach(modelContext.delete)

        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    /// Parses the ISO 8601 timestamp variants stored with draw records.
    private static func parseISO8601(_ value: String) -> Date? {
        fractionalISO8601Formatter.date(from: value) ?? iso8601Formatter.date(from: value)
    }
}
