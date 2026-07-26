import SwiftUI
import SwiftData

/// Displays the latest validated draw information and its freshness.
struct HomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \SavedNumberEntry.createdAt, order: .reverse) private var savedEntries: [SavedNumberEntry]
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
            .navigationTitle("六合彩提醒")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await model.loadIfNeeded(drawIDs: savedDrawIDs)
        }
        .task(id: automaticRefreshTaskID) {
            guard scenePhase == .active else {
                return
            }

            await model.runForegroundResultRefreshes(
                drawIDs: savedDrawIDs,
                drawDates: pendingResultDrawDates
            )
        }
        .onChange(of: savedDrawIDs) { _, newDrawIDs in
            Task {
                await model.loadResults(for: newDrawIDs)
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else {
                return
            }

            Task {
                await model.refresh(drawIDs: savedDrawIDs)
            }
        }
    }

    /// Builds the refreshable list state for one draw and its locally saved selections.
    private func drawContent(_ draw: DrawInfo) -> some View {
        List {
            jackpotCard(draw)
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 10, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            VStack(spacing: 0) {
                DetailRow(title: "攪珠期數", value: draw.drawNumber)
                Divider()
                DetailRow(
                    title: "攪珠日期",
                    value: DrawDateFormatter.hongKongDrawDate(draw.drawDate)
                )
                Divider()
                DetailRow(
                    title: "最近更新",
                    value: DrawDateFormatter.hongKongTimestamp(draw.updatedAt)
                )
            }
            .padding(.horizontal)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18))
            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            SavedNumbersSection(
                entries: savedEntries,
                drawsByID: model.drawsByID
            )

            Label("非香港賽馬會官方應用程式，資料只供參考。", systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .contentMargins(.top, 0, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .refreshable {
            await model.refresh(drawIDs: savedDrawIDs)
        }
    }

    /// Returns unique saved draw identifiers for result refresh requests.
    private var savedDrawIDs: [String] {
        Array(Set(savedEntries.map(\.drawID))).sorted()
    }

    /// Returns draw dates which still need a complete official result.
    private var pendingResultDrawDates: [String] {
        Array(
            Set(
                savedEntries
                    .filter { entry in
                        model.drawResult(for: entry.drawID)?.hasPublishedResult != true
                    }
                    .map(\.drawDate)
            )
        )
        .sorted()
    }

    /// Restarts or cancels the foreground schedule when app state or pending draws change.
    private var automaticRefreshTaskID: String {
        let appState = scenePhase == .active ? "active" : "inactive"
        return "\(appState)|\(savedDrawIDs.joined(separator: ","))|\(pendingResultDrawDates.joined(separator: ","))"
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
                    await model.refresh(drawIDs: savedDrawIDs)
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
    /// Formats an optional whole-dollar amount using the app's concise dollar prefix.
    static func currency(_ amount: Int?) -> String {
        guard let amount else {
            return "尚未公布"
        }

        return "$\(amount.formatted(.number.grouping(.automatic)))"
    }
}

/// Formats ISO 8601 timestamps for the user's current locale and time zone.
enum DrawDateFormatter {
    private static let iso8601Formatter = ISO8601DateFormatter()

    private static let fractionalISO8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let hongKongDrawDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "zh_HK")
        formatter.timeZone = TimeZone(identifier: "Asia/Hong_Kong")
        formatter.dateFormat = "dd/MM/yyyy (EEEE)"
        return formatter
    }()

    private static let hongKongTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Hong_Kong")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()

    /// Displays a draw timestamp as a Hong Kong date with a Traditional Chinese weekday.
    static func hongKongDrawDate(_ value: String) -> String {
        guard let date = parseISO8601(value) else {
            return value
        }

        return hongKongDrawDateFormatter.string(from: date)
    }

    /// Displays a Worker update timestamp in a fixed Hong Kong date-time format.
    static func hongKongTimestamp(_ value: String) -> String {
        guard let date = parseISO8601(value) else {
            return value
        }

        return hongKongTimestampFormatter.string(from: date)
    }

    /// Parses the ISO 8601 variants returned by the Worker and HKJC.
    private static func parseISO8601(_ value: String) -> Date? {
        fractionalISO8601Formatter.date(from: value) ?? iso8601Formatter.date(from: value)
    }
}
