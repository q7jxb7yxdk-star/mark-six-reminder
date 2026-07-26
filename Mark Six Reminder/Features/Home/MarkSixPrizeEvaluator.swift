import Foundation

/// The seven Mark Six prize tiers ordered from highest to lowest.
enum MarkSixPrize: Int, CaseIterable {
    case first = 1
    case second
    case third
    case fourth
    case fifth
    case sixth
    case seventh

    /// Returns the Traditional Chinese prize name shown in result summaries.
    var displayName: String {
        switch self {
        case .first:
            "頭獎"
        case .second:
            "二獎"
        case .third:
            "三獎"
        case .fourth:
            "四獎"
        case .fifth:
            "五獎"
        case .sixth:
            "六獎"
        case .seventh:
            "七獎"
        }
    }
}

/// Stores the number of represented bets qualifying for each prize tier.
struct MarkSixPrizeEvaluation {
    let prizeCounts: [MarkSixPrize: Int]

    /// Builds a concise summary suitable for one saved-number result row.
    var summary: String {
        let awards = MarkSixPrize.allCases.compactMap { prize -> String? in
            guard let count = prizeCounts[prize], count > 0 else {
                return nil
            }
            if count == 1 {
                return "\(prize.displayName)資格"
            }
            return "\(prize.displayName)資格 × \(count.formatted())"
        }

        return awards.isEmpty ? "未獲獎" : awards.joined(separator: "、")
    }
}

/// Evaluates single, multiple and banker selections without materializing every six-number bet.
enum MarkSixPrizeEvaluator {
    /// Counts every prize-qualified bet represented by one saved selection.
    static func evaluate(
        selectionType: NumberSelectionType,
        selectedNumbers: [Int],
        bankerNumbers: [Int],
        mainNumbers: [Int],
        specialNumber: Int
    ) -> MarkSixPrizeEvaluation {
        let selectedSet = Set(selectedNumbers)
        let bankerSet = selectionType == .banker ? Set(bankerNumbers) : []
        let selectableSet = selectedSet.subtracting(bankerSet)
        let selectableCount = 6 - bankerSet.count

        guard selectableCount >= 0, selectableSet.count >= selectableCount else {
            return MarkSixPrizeEvaluation(prizeCounts: [:])
        }

        let mainSet = Set(mainNumbers)
        let fixedMainCount = bankerSet.intersection(mainSet).count
        let fixedHasSpecial = bankerSet.contains(specialNumber)
        let selectableMainCount = selectableSet.intersection(mainSet).count
        let selectableSpecialCount = selectableSet.contains(specialNumber) ? 1 : 0
        let selectableOtherCount = selectableSet.count
            - selectableMainCount
            - selectableSpecialCount
        var prizeCounts: [MarkSixPrize: Int] = [:]

        for selectedMainCount in 0...min(selectableMainCount, selectableCount) {
            for selectedSpecialCount in 0...selectableSpecialCount {
                let selectedOtherCount = selectableCount
                    - selectedMainCount
                    - selectedSpecialCount
                guard selectedOtherCount >= 0 else {
                    continue
                }

                let representedBetCount = combinations(
                    choosing: selectedMainCount,
                    from: selectableMainCount
                ) * combinations(
                    choosing: selectedSpecialCount,
                    from: selectableSpecialCount
                ) * combinations(
                    choosing: selectedOtherCount,
                    from: selectableOtherCount
                )
                guard representedBetCount > 0 else {
                    continue
                }

                let totalMainCount = fixedMainCount + selectedMainCount
                let hasSpecial = fixedHasSpecial || selectedSpecialCount == 1
                guard let prize = prize(
                    mainMatchCount: totalMainCount,
                    hasSpecialNumber: hasSpecial
                ) else {
                    continue
                }

                prizeCounts[prize, default: 0] += representedBetCount
            }
        }

        return MarkSixPrizeEvaluation(prizeCounts: prizeCounts)
    }

    /// Maps one six-number bet's matches to the corresponding prize tier.
    private static func prize(
        mainMatchCount: Int,
        hasSpecialNumber: Bool
    ) -> MarkSixPrize? {
        switch (mainMatchCount, hasSpecialNumber) {
        case (6, _):
            .first
        case (5, true):
            .second
        case (5, false):
            .third
        case (4, true):
            .fourth
        case (4, false):
            .fifth
        case (3, true):
            .sixth
        case (3, false):
            .seventh
        default:
            nil
        }
    }

    /// Calculates n choose k while returning zero for impossible selections.
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
