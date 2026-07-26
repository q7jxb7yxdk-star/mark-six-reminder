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
                VStack(spacing: 20) {
                    VStack(spacing: 18) {
                        VStack(spacing: 7) {
                            Label("六個運財號碼", systemImage: "sparkles")
                                .font(.title2.bold())
                                .foregroundStyle(.red)

                            Text("從 1 至 49 隨機產生，不會重複，並按小至大排列。")
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
                    }
                    .appCard(cornerRadius: 24)

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
                            AppStatusMessage(
                                message: "正在綁定下一期攪珠…",
                                kind: .progress
                            )
                        } else if let successMessage = model.successMessage {
                            AppStatusMessage(message: successMessage, kind: .success)
                        } else if let errorMessage = model.errorMessage {
                            AppStatusMessage(message: errorMessage, kind: .error)
                        }
                    }

                    Label(
                        "隨機號碼只供娛樂，不構成博彩建議。",
                        systemImage: "info.circle"
                    )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color.primary.opacity(0.025))
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
