import SwiftUI
import UserNotifications

/// Allows the user to control notification permission and the jackpot threshold.
struct SettingsView: View {
    @Environment(SettingsViewModel.self) private var model
    @State private var customThreshold = ""

    var body: some View {
        NavigationStack {
            Form {
                notificationSection
                thresholdSection

                if let statusMessage = model.statusMessage {
                    Section {
                        Label(statusMessage, systemImage: statusIcon)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Text("本 App 不提供投注、不收取款項，通知只根據你設定的估計頭獎基金門檻。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("設定")
        }
        .task {
            await model.prepare()
        }
    }

    /// Displays notification authorization and the user's enabled preference.
    private var notificationSection: some View {
        Section("頭獎基金通知") {
            Toggle(
                "啟用通知",
                isOn: Binding(
                    get: { model.notificationsEnabled },
                    set: { enabled in
                        Task {
                            await model.setNotificationsEnabled(enabled)
                        }
                    }
                )
            )
            .disabled(model.isSynchronizing)

            LabeledContent("系統權限", value: authorizationDescription)

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
        }
    }

    /// Displays preset values and accepts a custom whole-dollar threshold.
    private var thresholdSection: some View {
        Section {
            LabeledContent("目前門檻", value: model.formattedThreshold)

            ForEach(SettingsViewModel.presetThresholds, id: \.self) { amount in
                Button {
                    Task {
                        await model.updateThreshold(amount)
                    }
                } label: {
                    HStack {
                        Text(currency(amount))
                        Spacer()
                        if model.threshold == amount {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            TextField("自訂金額，例如 25000000", text: $customThreshold)
                .keyboardType(.numberPad)

            Button("套用自訂門檻") {
                guard let amount = Int(customThreshold) else {
                    return
                }
                Task {
                    await model.updateThreshold(amount)
                    customThreshold = ""
                }
            }
            .disabled(Int(customThreshold) == nil)
        } header: {
            Text("通知門檻")
        } footer: {
            Text("只有當日有攪珠，而且估計頭獎基金達到或超過此金額，才會通知。每期最多一次。")
        }
    }

    /// Provides a concise localized summary of the current system permission.
    private var authorizationDescription: String {
        switch model.authorizationStatus {
        case .notDetermined:
            "尚未詢問"
        case .denied:
            "已拒絕"
        case .authorized:
            "已允許"
        case .provisional:
            "暫時允許"
        case .ephemeral:
            "暫時允許"
        @unknown default:
            "未知"
        }
    }

    /// Chooses a neutral status symbol while a backend update is running.
    private var statusIcon: String {
        model.isBusy ? "arrow.trianglehead.2.clockwise" : "info.circle"
    }

    /// Formats preset amounts consistently with the rest of the app.
    private func currency(_ amount: Int) -> String {
        "HK$\(amount.formatted(.number.grouping(.automatic)))"
    }
}
