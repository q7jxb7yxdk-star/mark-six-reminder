import SwiftUI
import UserNotifications

/// Allows the user to control notification permission and the jackpot threshold.
struct SettingsView: View {
    @Environment(SettingsViewModel.self) private var model

    var body: some View {
        NavigationStack {
            Form {
                notificationSection
                thresholdSection
                savedNumbersSection

                if let statusMessage = model.statusMessage {
                    Section {
                        AppStatusMessage(
                            message: statusMessage,
                            kind: model.isBusy ? .progress : .info
                        )
                    }
                    .listRowBackground(Color.clear)
                }

                Section {
                    Label(
                        "本 App 不提供投注、不收取款項，通知只根據你設定的估計頭獎基金門檻。",
                        systemImage: "info.circle"
                    )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            await model.prepare()
        }
    }

    /// Displays notification authorization and the user's enabled preference.
    private var notificationSection: some View {
        Section {
            Toggle(
                isOn: Binding(
                    get: { model.notificationsEnabled },
                    set: { enabled in
                        Task {
                            await model.setNotificationsEnabled(enabled)
                        }
                    }
                )
            ) {
                Label("啟用通知", systemImage: "bell.badge.fill")
                    .foregroundStyle(.primary)
            }
            .disabled(model.isSynchronizing)

            if model.authorizationStatus == .notDetermined {
                Button("設定通知權限") {
                    Task {
                        await model.requestPermission()
                    }
                }
                .disabled(model.isBusy)
            } else if model.authorizationStatus == .denied {
                Button("開啟 iPhone 設定") {
                    model.openSystemSettings()
                }
            }
        } header: {
            Text("頭獎基金通知")
        }
    }

    /// Displays the supported jackpot notification thresholds.
    private var thresholdSection: some View {
        Section {
            ForEach(SettingsViewModel.presetThresholds, id: \.self) { amount in
                Button {
                    Task {
                        await model.updateThreshold(amount)
                    }
                } label: {
                    HStack {
                        Text(currency(amount))
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(
                            systemName: model.threshold == amount
                                ? "checkmark.circle.fill"
                                : "circle"
                        )
                        .font(.title3)
                        .foregroundStyle(
                            model.threshold == amount
                                ? Color.red
                                : Color.secondary.opacity(0.45)
                        )
                    }
                    .contentShape(Rectangle())
                }
                .disabled(model.isSynchronizing)
            }
        } header: {
            Text("通知門檻")
        } footer: {
            Text("只有當日有攪珠，而且估計頭獎基金達到或超過此金額，才會通知。每期最多一次。")
        }
    }

    /// Controls whether selections from draws earlier than the current draw are retained.
    private var savedNumbersSection: some View {
        Section {
            Toggle(
                isOn: Binding(
                    get: { model.deleteOldNumbersEnabled },
                    set: { model.setDeleteOldNumbersEnabled($0) }
                )
            ) {
                Label("刪除舊號碼", systemImage: "trash")
                    .foregroundStyle(.primary)
            }
        } header: {
            Text("號碼記錄")
        } footer: {
            Text("開啟後，App 取得新的攪珠期數時會永久刪除較早期數的已儲存號碼，只保留目前期數。預設關閉。")
        }
    }

    /// Formats preset amounts consistently with the rest of the app.
    private func currency(_ amount: Int) -> String {
        "$\(amount.formatted(.number.grouping(.automatic)))"
    }
}
