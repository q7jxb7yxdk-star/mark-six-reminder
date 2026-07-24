import SwiftUI

/// Displays the latest validated draw information and its freshness.
struct HomeView: View {
    @Environment(SettingsViewModel.self) private var settingsModel
    @State private var model: HomeViewModel

    /// Creates a homepage with an injectable model for previews and tests.
    init(model: HomeViewModel = HomeViewModel()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let draw = model.draw {
                    drawContent(draw)
                } else if model.isLoading {
                    ProgressView("正在更新六合彩資料…")
                } else {
                    unavailableContent
                }
            }
            .navigationTitle("Jackpot Alert")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("重新整理", systemImage: "arrow.clockwise") {
                        Task {
                            await model.refresh()
                        }
                    }
                    .disabled(model.isLoading)
                }
            }
        }
        .task {
            await model.loadIfNeeded()
        }
    }

    /// Builds the scrollable success state for one draw.
    private func drawContent(_ draw: DrawInfo) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                jackpotCard(draw)

                VStack(spacing: 0) {
                    DetailRow(title: "期數", value: "第 \(draw.drawNumber) 期")
                    Divider()
                    DetailRow(title: "攪珠日期", value: DrawDateFormatter.display(draw.drawDate))
                    Divider()
                    DetailRow(title: "截止售票", value: DrawDateFormatter.display(draw.salesCloseAt))
                    Divider()
                    DetailRow(title: "最近更新", value: DrawDateFormatter.display(draw.updatedAt))
                    Divider()
                    DetailRow(title: "通知門檻", value: settingsModel.formattedThreshold)
                }
                .padding(.horizontal)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18))

                Label("非香港賽馬會官方應用程式，資料只供參考。", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .refreshable {
            await model.refresh()
        }
    }

    /// Builds the primary estimated-prize card.
    private func jackpotCard(_ draw: DrawInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("估計頭獎基金", systemImage: "bell.badge.fill")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(DrawAmountFormatter.currency(draw.estimatedFirstPrizeFund))
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            if let jackpot = draw.jackpot, jackpot > 0 {
                Text("累積多寶：\(DrawAmountFormatter.currency(jackpot))")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 22))
    }

    /// Displays configuration, network or backend errors without fake data.
    private var unavailableContent: some View {
        ContentUnavailableView {
            Label("暫時未有資料", systemImage: "exclamationmark.triangle")
        } description: {
            Text(model.errorMessage ?? "資料尚未完成第一次更新。")
        } actions: {
            Button("再試一次") {
                Task {
                    await model.refresh()
                }
            }
        }
    }
}

/// Displays one label-value pair in the homepage details card.
private struct DetailRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 14)
    }
}

/// Formats monetary values consistently without assuming a non-null estimate.
private enum DrawAmountFormatter {
    /// Formats an optional whole-dollar amount in Hong Kong dollars.
    static func currency(_ amount: Int?) -> String {
        guard let amount else {
            return "尚未公布"
        }

        return "HK$\(amount.formatted(.number.grouping(.automatic)))"
    }
}

/// Formats ISO 8601 timestamps for the user's current locale and time zone.
private enum DrawDateFormatter {
    /// Converts an API timestamp to a compact local date and time.
    static func display(_ value: String) -> String {
        guard let date = ISO8601DateFormatter().date(from: value) else {
            return value
        }

        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
