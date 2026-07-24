import Foundation
import Observation
import SwiftData

/// Owns the six unique Mark Six numbers displayed by the random-number page.
@MainActor
@Observable
final class RandomNumbersViewModel {
    private static let numberCount = 6
    private static let availableNumbers = Array(1...49)

    private(set) var numbers: [Int]
    private(set) var isSaving = false
    private(set) var successMessage: String?
    private(set) var errorMessage: String?

    private let apiClient: JackpotAPIClient?

    /// Creates the model without generating numbers before the user's first request.
    init(apiClient: JackpotAPIClient? = AppConfiguration.apiBaseURL.map(JackpotAPIClient.init)) {
        numbers = []
        self.apiClient = apiClient
    }

    /// Indicates whether the user has generated a set during the current session.
    var hasGeneratedNumbers: Bool {
        !numbers.isEmpty
    }

    /// Indicates whether a complete selection can currently be saved.
    var canSaveNumbers: Bool {
        hasGeneratedNumbers && !isSaving
    }

    /// Replaces the current selection with six new sorted, non-repeating numbers.
    func generateNumbers() {
        numbers = Self.makeNumbers()
        successMessage = nil
        errorMessage = nil
    }

    /// Associates the current numbers with the next draw and persists them using SwiftData.
    func saveNumbers(in context: ModelContext) async {
        guard canSaveNumbers else {
            return
        }

        guard let apiClient else {
            errorMessage = JackpotAPIError.invalidConfiguration.localizedDescription
            successMessage = nil
            return
        }

        isSaving = true
        successMessage = nil
        errorMessage = nil
        defer { isSaving = false }

        do {
            let draw = try await apiClient.currentDraw()
            let drawID = draw.id
            let descriptor = FetchDescriptor<SavedNumberEntry>(
                predicate: #Predicate { entry in
                    entry.drawID == drawID
                }
            )
            let existingEntries = try context.fetch(descriptor)
            if existingEntries.contains(where: { $0.hasSameNumbers(as: numbers) }) {
                successMessage = "這組號碼已儲存至第\(draw.drawNumber)期。"
                return
            }

            let entry = SavedNumberEntry(draw: draw, numbers: numbers)
            context.insert(entry)
            do {
                try context.save()
                successMessage = "已儲存至第\(draw.drawNumber)期。"
            } catch {
                context.delete(entry)
                throw error
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Selects six unique values from 1 through 49 and sorts them in ascending order.
    private static func makeNumbers() -> [Int] {
        let selection = availableNumbers
            .shuffled()
            .prefix(numberCount)
            .sorted()

        precondition(
            selection.count == numberCount && Set(selection).count == numberCount,
            "Random number generation must return six unique values."
        )
        return selection
    }
}
