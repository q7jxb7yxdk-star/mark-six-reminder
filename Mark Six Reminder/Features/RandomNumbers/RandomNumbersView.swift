import SwiftUI
import SwiftData

/// Displays six unique random numbers and allows the user to generate a new set.
struct RandomNumbersView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var model: RandomNumbersViewModel

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: 12),
        count: 3
    )

    /// Creates the page with an injectable model for previews and tests.
    init(model: RandomNumbersViewModel = RandomNumbersViewModel()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 8) {
                        Text("隨機產生六個號碼")
                            .font(.title2.bold())

                        Text("號碼範圍為 1 至 49，不會重複，並按小至大排列。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(Array(displayedNumbers.enumerated()), id: \.offset) { _, number in
                            MarkSixNumberBall(number: number)
                                .frame(maxWidth: .infinity)
                        }
                    }

                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Button(
                                model.hasGeneratedNumbers ? "重新產生" : "產生號碼",
                                systemImage: model.hasGeneratedNumbers ? "arrow.clockwise" : "dice.fill"
                            ) {
                                model.generateNumbers()
                            }
                            .frame(maxWidth: .infinity)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .disabled(model.isSaving)

                            Button("儲存號碼", systemImage: "square.and.arrow.down") {
                                Task {
                                    await model.saveNumbers(in: modelContext)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                            .disabled(!model.canSaveNumbers)
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

                    Divider()

                    Text("隨機號碼只供娛樂，不構成博彩建議。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
            .navigationTitle("運財號碼")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    /// Returns generated values, or six empty positions rendered as zero placeholders.
    private var displayedNumbers: [Int?] {
        guard model.hasGeneratedNumbers else {
            return Array(repeating: nil, count: 6)
        }
        return model.numbers.map(Optional.some)
    }
}

#Preview {
    RandomNumbersView()
}
