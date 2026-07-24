import Foundation
import Observation
import SwiftData

/// Identifies which part of a banker selection receives the next tapped number.
enum BankerSelectionRole: String, CaseIterable, Identifiable {
    case banker
    case leg

    var id: Self { self }

    /// Returns the concise label used by the segmented control.
    var displayName: String {
        switch self {
        case .banker:
            "選膽"
        case .leg:
            "選拖"
        }
    }
}

/// Owns user-selected Mark Six numbers and persists valid entries for the next draw.
@MainActor
@Observable
final class CustomNumbersViewModel {
    private(set) var selectionType: NumberSelectionType = .single
    private(set) var bankerRole: BankerSelectionRole = .banker
    private(set) var selectedNumbers: Set<Int> = []
    private(set) var bankerNumbers: Set<Int> = []
    private(set) var isSaving = false
    private(set) var successMessage: String?
    private(set) var errorMessage: String?

    private let apiClient: JackpotAPIClient?

    /// Creates an empty selection linked to the configured Worker API.
    init(apiClient: JackpotAPIClient? = AppConfiguration.apiBaseURL.map(JackpotAPIClient.init)) {
        self.apiClient = apiClient
    }

    /// Returns all chosen values in ascending order.
    var sortedNumbers: [Int] {
        selectedNumbers.sorted()
    }

    /// Returns fixed banker values in ascending order.
    var sortedBankerNumbers: [Int] {
        bankerNumbers.sorted()
    }

    /// Returns non-banker leg values in ascending order.
    var sortedLegNumbers: [Int] {
        selectedNumbers.subtracting(bankerNumbers).sorted()
    }

    /// Indicates whether the current selection satisfies the official structural rules.
    var canSave: Bool {
        guard !isSaving else {
            return false
        }

        switch selectionType {
        case .single:
            return selectedNumbers.count == 6
        case .multiple:
            return selectedNumbers.count >= 7
        case .banker:
            return (1...5).contains(bankerNumbers.count)
                && selectedNumbers.count >= 7
                && sortedLegNumbers.count >= 6 - bankerNumbers.count
        }
    }

    /// Returns a concise instruction or validation message for the selected type.
    var guidance: String {
        switch selectionType {
        case .single:
            return "請選擇 6 個不同號碼。目前已選 \(selectedNumbers.count) 個。"
        case .multiple:
            return "請選擇最少 7 個不同號碼。目前已選 \(selectedNumbers.count) 個。"
        case .banker:
            return "請選擇 1 至 5 個膽，並令膽與拖合共最少 7 個。現在有 \(bankerNumbers.count) 膽、\(sortedLegNumbers.count) 拖。"
        }
    }

    /// Returns the number of represented six-number combinations.
    var combinationCount: Int {
        switch selectionType {
        case .single:
            return canSave ? 1 : 0
        case .multiple:
            return Self.combinations(choosing: 6, from: selectedNumbers.count)
        case .banker:
            return Self.combinations(
                choosing: 6 - bankerNumbers.count,
                from: sortedLegNumbers.count
            )
        }
    }

    /// Changes the selection type and clears values which belong to the previous type.
    func selectType(_ newType: NumberSelectionType) {
        guard newType != selectionType else {
            return
        }
        selectionType = newType
        clearSelection()
    }

    /// Changes whether number taps choose bankers or legs.
    func selectBankerRole(_ newRole: BankerSelectionRole) {
        bankerRole = newRole
        successMessage = nil
        errorMessage = nil
    }

    /// Adds, removes or moves one number according to the active selection mode.
    func toggleNumber(_ number: Int) {
        guard (1...49).contains(number), !isSaving else {
            return
        }

        successMessage = nil
        errorMessage = nil

        switch selectionType {
        case .single:
            if selectedNumbers.contains(number) {
                selectedNumbers.remove(number)
            } else if selectedNumbers.count < 6 {
                selectedNumbers.insert(number)
            }
        case .multiple:
            toggleSelectedNumber(number)
        case .banker:
            toggleBankerNumber(number)
        }
    }

    /// Removes all numbers while retaining the current selection type.
    func clearSelection() {
        selectedNumbers.removeAll()
        bankerNumbers.removeAll()
        bankerRole = .banker
        successMessage = nil
        errorMessage = nil
    }

    /// Associates the valid selection with the next draw and saves one SwiftData record.
    func saveSelection(in context: ModelContext) async {
        guard canSave else {
            errorMessage = guidance
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
            if existingEntries.contains(where: {
                $0.hasSameSelection(
                    type: selectionType,
                    numbers: sortedNumbers,
                    bankers: sortedBankerNumbers
                )
            }) {
                successMessage = "這項\(selectionType.displayName)號碼已儲存至第\(draw.drawNumber)期。"
                return
            }

            let entry = SavedNumberEntry(
                draw: draw,
                selectionType: selectionType,
                selectedNumbers: sortedNumbers,
                bankerNumbers: sortedBankerNumbers
            )
            context.insert(entry)
            do {
                try context.save()
                successMessage = "已儲存\(selectionType.displayName)號碼至第\(draw.drawNumber)期。"
            } catch {
                context.delete(entry)
                throw error
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Toggles one unrestricted multiple-selection number.
    private func toggleSelectedNumber(_ number: Int) {
        if selectedNumbers.contains(number) {
            selectedNumbers.remove(number)
        } else {
            selectedNumbers.insert(number)
        }
    }

    /// Toggles one banker or leg while keeping both groups mutually exclusive.
    private func toggleBankerNumber(_ number: Int) {
        switch bankerRole {
        case .banker:
            if bankerNumbers.contains(number) {
                bankerNumbers.remove(number)
                selectedNumbers.remove(number)
            } else if bankerNumbers.count < 5 {
                bankerNumbers.insert(number)
                selectedNumbers.insert(number)
            }
        case .leg:
            if selectedNumbers.contains(number) && !bankerNumbers.contains(number) {
                selectedNumbers.remove(number)
            } else {
                bankerNumbers.remove(number)
                selectedNumbers.insert(number)
            }
        }
    }

    /// Calculates n choose k without generating every six-number combination.
    private static func combinations(choosing selectionCount: Int, from totalCount: Int) -> Int {
        guard selectionCount >= 0, totalCount >= selectionCount else {
            return 0
        }
        if selectionCount == 0 || totalCount == selectionCount {
            return 1
        }

        let smallerSelection = min(selectionCount, totalCount - selectionCount)
        return (1...smallerSelection).reduce(1) { result, index in
            result * (totalCount - smallerSelection + index) / index
        }
    }
}
