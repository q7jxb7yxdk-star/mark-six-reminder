import SwiftUI

/// Groups locally saved selections by draw and compares every set with one official result.
struct SavedNumbersSection: View {
    let entries: [SavedNumberEntry]
    let drawsByID: [String: DrawInfo]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("我的號碼")
                .font(.title3.bold())
                .frame(maxWidth: .infinity, alignment: .leading)

            if drawGroups.isEmpty {
                Label("尚未儲存號碼", systemImage: "tray")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18))
            } else {
                ForEach(drawGroups) { group in
                    drawGroupCard(group)
                }
            }
        }
    }

    /// Builds one card containing a shared official result and every saved set for that draw.
    private func drawGroupCard(_ group: SavedDrawGroup) -> some View {
        let result = drawsByID[group.id]

        return VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("第\(group.drawNumber)期")
                    .font(.headline)
                Text(DrawDateFormatter.hongKongDrawDate(group.drawDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let result, result.hasPublishedResult, let specialNumber = result.specialNumber {
                Text("官方攪珠結果")
                    .font(.subheadline.weight(.semibold))

                officialResultRow(result.mainNumbers, specialNumber: specialNumber)
            } else {
                Label("等待官方攪珠結果", systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Divider()

            ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                savedSelection(
                    entry,
                    position: index + 1,
                    result: result
                )

                if index < group.entries.count - 1 {
                    Divider()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18))
    }

    /// Shows one numbered selection and its independent result summary.
    private func savedSelection(
        _ entry: SavedNumberEntry,
        position: Int,
        result: DrawInfo?
    ) -> some View {
        let matchedNumbers = Set(result?.mainNumbers ?? [])
            .union(result?.specialNumber.map { [$0] } ?? [])

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("第 \(position) 組・\(entry.selectionType.displayName)")
                Spacer()
                if entry.combinationCount > 1 {
                    Text("\(entry.combinationCount.formatted()) 注")
                        .foregroundStyle(.secondary)
                }
            }
                .font(.subheadline.weight(.semibold))

            savedNumberRows(entry, highlightedNumbers: matchedNumbers)

            if let result, result.hasPublishedResult {
                Text(matchSummary(entry: entry, result: result))
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    /// Shows saved balls, splitting banker and leg values when necessary.
    @ViewBuilder
    private func savedNumberRows(
        _ entry: SavedNumberEntry,
        highlightedNumbers: Set<Int>
    ) -> some View {
        if entry.selectionType == .banker {
            Text("膽")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            numberGrid(entry.bankerNumbers, highlightedNumbers: highlightedNumbers)
            Text("拖")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            numberGrid(entry.legNumbers, highlightedNumbers: highlightedNumbers)
        } else {
            numberGrid(entry.numbers, highlightedNumbers: highlightedNumbers)
        }
    }

    /// Shows a wrapping grid of saved balls with all matching numbers highlighted.
    private func numberGrid(_ numbers: [Int], highlightedNumbers: Set<Int>) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 38, maximum: 42), spacing: 6)], spacing: 8) {
            ForEach(numbers, id: \.self) { number in
                MarkSixNumberBall(
                    number: number,
                    size: 42,
                    isHighlighted: highlightedNumbers.contains(number)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Shows six official main numbers followed by the special number.
    private func officialResultRow(_ mainNumbers: [Int], specialNumber: Int) -> some View {
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(mainNumbers, id: \.self) { number in
                MarkSixNumberBall(number: number, size: 34)
            }

            VStack(spacing: 2) {
                Text("特")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                MarkSixNumberBall(number: specialNumber, size: 34)
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Summarizes main-number and special-number matches for one saved set.
    private func matchSummary(entry: SavedNumberEntry, result: DrawInfo) -> String {
        let selectedNumbers = Set(entry.numbers)
        let mainNumbers = Set(result.mainNumbers)
        let mainMatchCount = selectedNumbers.intersection(mainNumbers).count
        let matchedSpecial = result.specialNumber.map(selectedNumbers.contains) ?? false
        let specialText = matchedSpecial ? "中特別號碼" : "未中特別號碼"

        if entry.selectionType == .banker {
            let bankerMatchCount = Set(entry.bankerNumbers).intersection(mainNumbers).count
            let legMatchCount = Set(entry.legNumbers).intersection(mainNumbers).count
            return "膽中 \(bankerMatchCount) 個正選、拖中 \(legMatchCount) 個正選，\(specialText)"
        }
        if entry.selectionType == .multiple {
            return "所選號碼中了 \(mainMatchCount) 個正選號碼，\(specialText)"
        }
        return "中了 \(mainMatchCount) 個正選號碼，\(specialText)"
    }

    /// Groups entries by draw and orders groups newest-first and selections oldest-first.
    private var drawGroups: [SavedDrawGroup] {
        Dictionary(grouping: entries, by: \.drawID)
            .compactMap { drawID, groupedEntries in
                guard let firstEntry = groupedEntries.first else {
                    return nil
                }

                return SavedDrawGroup(
                    id: drawID,
                    drawNumber: firstEntry.drawNumber,
                    drawDate: firstEntry.drawDate,
                    entries: groupedEntries.sorted { $0.createdAt < $1.createdAt }
                )
            }
            .sorted { $0.drawDate > $1.drawDate }
    }
}

/// A presentation-only group of locally saved selections for one draw.
private struct SavedDrawGroup: Identifiable {
    let id: String
    let drawNumber: String
    let drawDate: String
    let entries: [SavedNumberEntry]
}
