import SwiftData
import SwiftUI

/// Groups locally saved selections by draw and compares every set with one official result.
struct SavedNumbersSection: View {
    @Environment(\.modelContext) private var modelContext
    @State private var deletionErrorMessage: String?

    let entries: [SavedNumberEntry]
    let drawsByID: [String: DrawInfo]

    var body: some View {
        Group {
            if drawGroups.isEmpty {
                Label("尚未儲存號碼", systemImage: "tray")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .appCard()
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else {
                ForEach(drawGroups) { group in
                    drawGroupSection(group)
                }
            }
        }
        .alert("未能刪除號碼", isPresented: deletionErrorIsPresented) {
            Button("確定", role: .cancel) {}
        } message: {
            Text(deletionErrorMessage ?? "請稍後再試。")
        }
    }

    /// Builds one native list section containing a shared result and swipeable selections.
    private func drawGroupSection(_ group: SavedDrawGroup) -> some View {
        let result = drawsByID[group.id]

        return Section {
            VStack(alignment: .leading, spacing: 12) {
                if let result, result.hasPublishedResult, let specialNumber = result.specialNumber {
                    Label("官方攪珠結果", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)

                    officialResultRow(result.mainNumbers, specialNumber: specialNumber)
                } else {
                    Label("等待官方攪珠結果", systemImage: "clock")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 8)
            .background(.red.opacity(0.07), in: RoundedRectangle(cornerRadius: 18))
            .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                savedSelection(
                    entry,
                    position: index + 1,
                    result: result
                )
                .appCard(cornerRadius: 18)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button("刪除", systemImage: "trash", role: .destructive) {
                        delete(entry)
                    }
                }
            }
        } header: {
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(.red)

                VStack(alignment: .leading, spacing: 3) {
                    Text("第\(group.drawNumber)期")
                        .font(.headline)
                    Text(DrawDateFormatter.hongKongDrawDate(group.drawDate))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .textCase(nil)
        }
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
                Text("\(entry.drawNumber) 期，第 \(position) 組・\(entry.selectionType.displayName)")
                Spacer()
                if entry.combinationCount > 1 {
                    Text("\(entry.combinationCount.formatted()) 注")
                        .foregroundStyle(.secondary)
                }
            }
                .font(.subheadline.weight(.semibold))

            savedNumberRows(entry, highlightedNumbers: matchedNumbers)

            if let result,
               result.hasPublishedResult,
               let specialNumber = result.specialNumber {
                prizeStatus(
                    MarkSixPrizeEvaluator.evaluate(
                        selectionType: entry.selectionType,
                        selectedNumbers: entry.numbers,
                        bankerNumbers: entry.bankerNumbers,
                        mainNumbers: result.mainNumbers,
                        specialNumber: specialNumber
                    )
                )
            }
        }
    }

    /// Displays a visually distinct winning or non-winning qualification result.
    private func prizeStatus(_ evaluation: MarkSixPrizeEvaluation) -> some View {
        let hasPrize = !evaluation.prizeCounts.isEmpty
        let color: Color = hasPrize ? .orange : .gray

        return Label(
            evaluation.summary,
            systemImage: hasPrize ? "trophy.fill" : "minus.circle.fill"
        )
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(color.opacity(0.11), in: Capsule())
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
        } else if entry.numbers.count == 6 {
            centeredNumberRow(entry.numbers, highlightedNumbers: highlightedNumbers)
        } else {
            numberGrid(entry.numbers, highlightedNumbers: highlightedNumbers)
        }
    }

    /// Shows one complete six-number selection centered within its list row.
    private func centeredNumberRow(
        _ numbers: [Int],
        highlightedNumbers: Set<Int>
    ) -> some View {
        HStack(spacing: 6) {
            ForEach(numbers, id: \.self) { number in
                MarkSixNumberBall(
                    number: number,
                    size: 42,
                    isHighlighted: highlightedNumbers.contains(number)
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
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

    /// Shows six official main numbers, a plus sign and the equally sized special number.
    private func officialResultRow(_ mainNumbers: [Int], specialNumber: Int) -> some View {
        HStack(spacing: 2) {
            ForEach(mainNumbers, id: \.self) { number in
                MarkSixNumberBall(number: number, size: 42)
            }

            Text("+")
                .font(.headline.bold())
                .foregroundStyle(.secondary)
                .frame(width: 12)
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(1)
                .accessibilityLabel("加")

            MarkSixNumberBall(number: specialNumber, size: 42)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    /// Deletes one local selection and rolls back the context if persistence fails.
    private func delete(_ entry: SavedNumberEntry) {
        modelContext.delete(entry)
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            deletionErrorMessage = error.localizedDescription
        }
    }

    /// Presents deletion errors while keeping optional alert state in one property.
    private var deletionErrorIsPresented: Binding<Bool> {
        Binding(
            get: { deletionErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    deletionErrorMessage = nil
                }
            }
        )
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
