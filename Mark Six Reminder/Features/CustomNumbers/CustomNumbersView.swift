import SwiftData
import SwiftUI

/// Lets the user build and save single, multiple or banker Mark Six selections.
struct CustomNumbersView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var model: CustomNumbersViewModel

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 4),
        count: 7
    )

    /// Creates the page with an injectable model for previews and tests.
    init(model: CustomNumbersViewModel = CustomNumbersViewModel()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    typePicker
                    guidanceCard

                    if model.selectionType == .banker {
                        bankerRolePicker
                    }

                    numberGrid
                    selectionSummary
                    actionButtons

                    Text("自選號碼只供記錄及結果核對，本 App 不提供投注或博彩建議。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
            .navigationTitle("自選號碼")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// Lets the user choose one of the three supported entry structures.
    private var typePicker: some View {
        Picker(
            "選號方式",
            selection: Binding(
                get: { model.selectionType },
                set: { model.selectType($0) }
            )
        ) {
            ForEach(NumberSelectionType.allCases) { type in
                Text(type.displayName).tag(type)
            }
        }
        .pickerStyle(.segmented)
        .disabled(model.isSaving)
    }

    /// Displays the current official structural requirement and selected count.
    private var guidanceCard: some View {
        Text(model.guidance)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
    }

    /// Selects whether subsequent banker-mode taps represent bankers or legs.
    private var bankerRolePicker: some View {
        Picker(
            "膽拖選擇",
            selection: Binding(
                get: { model.bankerRole },
                set: { model.selectBankerRole($0) }
            )
        ) {
            ForEach(BankerSelectionRole.allCases) { role in
                Text(role.displayName).tag(role)
            }
        }
        .pickerStyle(.segmented)
        .disabled(model.isSaving)
    }

    /// Renders all 49 official-color number balls as accessible buttons.
    private var numberGrid: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(1...49, id: \.self) { number in
                Button {
                    model.toggleNumber(number)
                } label: {
                    MarkSixNumberBall(
                        number: number,
                        size: 38,
                        isHighlighted: model.selectedNumbers.contains(number)
                    )
                    .overlay(alignment: .topTrailing) {
                        if model.bankerNumbers.contains(number) {
                            Text("膽")
                                .font(.caption2.bold())
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(.orange, in: Circle())
                                .offset(x: 3, y: -3)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(model.isSaving)
                .accessibilityHint(numberAccessibilityHint(number))
            }
        }
    }

    /// Summarizes selected numbers and the represented combination count.
    @ViewBuilder
    private var selectionSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.selectionType == .banker, !model.selectedNumbers.isEmpty {
                selectedLine(title: "膽", numbers: model.sortedBankerNumbers)
                selectedLine(title: "拖", numbers: model.sortedLegNumbers)
            } else if !model.selectedNumbers.isEmpty {
                selectedLine(title: "已選", numbers: model.sortedNumbers)
            }

            if model.canSave {
                Label(
                    "共 \(model.combinationCount.formatted()) 注六個號碼組合",
                    systemImage: "checkmark.circle.fill"
                )
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Displays one sorted list without adding another row of large balls.
    private func selectedLine(title: String, numbers: [Int]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(numbers.isEmpty ? "尚未選擇" : numbers.map { String(format: "%02d", $0) }.joined(separator: "、"))
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    /// Provides clear, separate reset and persistence actions.
    private var actionButtons: some View {
        VStack(spacing: 12) {
            HStack {
                Button("清除全部", systemImage: "trash") {
                    model.clearSelection()
                }
                .buttonStyle(.bordered)
                .disabled(model.selectedNumbers.isEmpty || model.isSaving)

                Button("儲存號碼", systemImage: "square.and.arrow.down") {
                    Task {
                        await model.saveSelection(in: modelContext)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canSave)
            }

            if model.isSaving {
                ProgressView("正在綁定下一期攪珠…")
                    .font(.footnote)
            } else if let successMessage = model.successMessage {
                Label(successMessage, systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
            } else if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    /// Explains the effect of tapping a number to VoiceOver users.
    private func numberAccessibilityHint(_ number: Int) -> String {
        if model.selectionType == .banker {
            return model.bankerRole == .banker ? "點兩下選擇或移除膽號" : "點兩下選擇或移除拖號"
        }
        return model.selectedNumbers.contains(number) ? "點兩下移除此號碼" : "點兩下選擇此號碼"
    }
}

#Preview {
    CustomNumbersView()
}
