import Foundation
import SwiftData

/// The supported ways a user can build one locally saved Mark Six selection.
enum NumberSelectionType: String, CaseIterable, Identifiable {
    case single
    case multiple
    case banker

    var id: Self { self }

    /// Returns the Traditional Chinese name shown throughout the app.
    var displayName: String {
        switch self {
        case .single:
            "單式"
        case .multiple:
            "複式"
        case .banker:
            "膽拖"
        }
    }
}

/// A locally stored number selection tied to one official Mark Six draw.
@Model
final class SavedNumberEntry {
    @Attribute(.unique) var id: UUID
    var drawID: String
    var drawNumber: String
    var drawDate: String
    var firstNumber: Int
    var secondNumber: Int
    var thirdNumber: Int
    var fourthNumber: Int
    var fifthNumber: Int
    var sixthNumber: Int
    var createdAt: Date
    var selectionTypeRawValue: String = "single"
    var selectedNumbersStorage: String = ""
    var bankerNumbersStorage: String = ""

    /// Creates a validated, sorted local number selection for the supplied draw.
    init(
        draw: DrawInfo,
        numbers: [Int],
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) {
        let sortedNumbers = numbers.sorted()
        precondition(
            sortedNumbers.count == 6
                && Set(sortedNumbers).count == 6
                && sortedNumbers.allSatisfy { (1...49).contains($0) },
            "Saved Mark Six selections must contain six unique numbers from 1 through 49."
        )

        self.id = id
        drawID = draw.id
        drawNumber = draw.drawNumber
        drawDate = draw.drawDate
        firstNumber = sortedNumbers[0]
        secondNumber = sortedNumbers[1]
        thirdNumber = sortedNumbers[2]
        fourthNumber = sortedNumbers[3]
        fifthNumber = sortedNumbers[4]
        sixthNumber = sortedNumbers[5]
        self.createdAt = createdAt
        selectionTypeRawValue = NumberSelectionType.single.rawValue
        selectedNumbersStorage = Self.encode(sortedNumbers)
        bankerNumbersStorage = ""
    }

    /// Creates a validated single, multiple or banker selection for the supplied draw.
    init(
        draw: DrawInfo,
        selectionType: NumberSelectionType,
        selectedNumbers: [Int],
        bankerNumbers: [Int] = [],
        id: UUID = UUID(),
        createdAt: Date = Date()
    ) {
        let sortedNumbers = selectedNumbers.sorted()
        let sortedBankers = bankerNumbers.sorted()
        precondition(
            Self.isValid(
                selectionType: selectionType,
                selectedNumbers: sortedNumbers,
                bankerNumbers: sortedBankers
            ),
            "Saved Mark Six selection does not satisfy its selection type."
        )

        self.id = id
        drawID = draw.id
        drawNumber = draw.drawNumber
        drawDate = draw.drawDate
        firstNumber = sortedNumbers[0]
        secondNumber = sortedNumbers[1]
        thirdNumber = sortedNumbers[2]
        fourthNumber = sortedNumbers[3]
        fifthNumber = sortedNumbers[4]
        sixthNumber = sortedNumbers[5]
        self.createdAt = createdAt
        selectionTypeRawValue = selectionType.rawValue
        selectedNumbersStorage = Self.encode(sortedNumbers)
        bankerNumbersStorage = Self.encode(sortedBankers)
    }

    /// Resolves the stored type while treating legacy records as single selections.
    var selectionType: NumberSelectionType {
        NumberSelectionType(rawValue: selectionTypeRawValue) ?? .single
    }

    /// Returns all selected values in ascending order, including legacy records.
    var numbers: [Int] {
        let decodedNumbers = Self.decode(selectedNumbersStorage)
        if !decodedNumbers.isEmpty {
            return decodedNumbers
        }
        return [firstNumber, secondNumber, thirdNumber, fourthNumber, fifthNumber, sixthNumber]
    }

    /// Returns the fixed banker values for a banker selection.
    var bankerNumbers: [Int] {
        Self.decode(bankerNumbersStorage)
    }

    /// Returns selected values which are not fixed bankers.
    var legNumbers: [Int] {
        let bankers = Set(bankerNumbers)
        return numbers.filter { !bankers.contains($0) }
    }

    /// Returns the number of six-number combinations represented by this entry.
    var combinationCount: Int {
        switch selectionType {
        case .single:
            1
        case .multiple:
            Self.combinations(choosing: 6, from: numbers.count)
        case .banker:
            Self.combinations(choosing: 6 - bankerNumbers.count, from: legNumbers.count)
        }
    }

    /// Checks whether this entry contains exactly the same six numbers.
    func hasSameNumbers(as otherNumbers: [Int]) -> Bool {
        selectionType == .single && numbers == otherNumbers.sorted()
    }

    /// Checks whether this entry represents the same type, numbers and bankers.
    func hasSameSelection(
        type: NumberSelectionType,
        numbers otherNumbers: [Int],
        bankers otherBankers: [Int]
    ) -> Bool {
        selectionType == type
            && numbers == otherNumbers.sorted()
            && bankerNumbers == otherBankers.sorted()
    }

    /// Encodes sorted integer values in a compact migration-friendly form.
    private static func encode(_ numbers: [Int]) -> String {
        numbers.map(String.init).joined(separator: ",")
    }

    /// Decodes a stored comma-separated number list and restores ascending order.
    private static func decode(_ value: String) -> [Int] {
        value.split(separator: ",").compactMap { Int($0) }.sorted()
    }

    /// Validates selection rules before SwiftData receives a new record.
    private static func isValid(
        selectionType: NumberSelectionType,
        selectedNumbers: [Int],
        bankerNumbers: [Int]
    ) -> Bool {
        guard Set(selectedNumbers).count == selectedNumbers.count,
              selectedNumbers.allSatisfy({ (1...49).contains($0) }),
              Set(bankerNumbers).count == bankerNumbers.count,
              bankerNumbers.allSatisfy({ selectedNumbers.contains($0) }) else {
            return false
        }

        switch selectionType {
        case .single:
            return selectedNumbers.count == 6 && bankerNumbers.isEmpty
        case .multiple:
            return selectedNumbers.count >= 7 && bankerNumbers.isEmpty
        case .banker:
            return (1...5).contains(bankerNumbers.count) && selectedNumbers.count >= 7
        }
    }

    /// Calculates n choose k without materializing individual combinations.
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
