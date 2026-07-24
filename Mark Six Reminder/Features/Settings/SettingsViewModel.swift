import Foundation
import Observation
import UserNotifications

/// Owns persisted jackpot notification preferences and backend synchronization state.
@MainActor
@Observable
final class SettingsViewModel {
    static let presetThresholds = [16_000_000, 20_000_000, 30_000_000]

    private(set) var threshold: Int
    private(set) var notificationsEnabled: Bool
    private(set) var isSynchronizing = false
    private(set) var statusMessage: String?

    @ObservationIgnored
    private let notificationManager: NotificationManager
    @ObservationIgnored
    private let apiClient: NotificationAPIClient?
    @ObservationIgnored
    private let defaults: UserDefaults
    @ObservationIgnored
    private let installationId: String

    /// Creates the model using a stable installation identifier and current API configuration.
    init(
        notificationManager: NotificationManager,
        apiClient: NotificationAPIClient? = AppConfiguration.apiBaseURL.map(NotificationAPIClient.init),
        defaults: UserDefaults = .standard
    ) {
        self.notificationManager = notificationManager
        self.apiClient = apiClient
        self.defaults = defaults

        threshold = defaults.object(forKey: PreferenceKey.threshold) as? Int ?? 20_000_000
        notificationsEnabled = defaults.object(forKey: PreferenceKey.enabled) as? Bool ?? true

        if let storedId = defaults.string(forKey: PreferenceKey.installationId),
           UUID(uuidString: storedId) != nil {
            installationId = storedId
        } else {
            let newId = UUID().uuidString.lowercased()
            defaults.set(newId, forKey: PreferenceKey.installationId)
            installationId = newId
        }

        notificationManager.deviceTokenDidChange = { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.synchronizeIfPossible()
            }
        }
    }

    /// Exposes the current iOS authorization state for settings UI decisions.
    var authorizationStatus: UNAuthorizationStatus {
        notificationManager.authorizationStatus
    }

    /// Formats the selected threshold in Hong Kong dollars.
    var formattedThreshold: String {
        "HK$\(threshold.formatted(.number.grouping(.automatic)))"
    }

    /// Refreshes system permission and synchronizes a previously issued APNs token.
    func prepare() async {
        await notificationManager.refreshAuthorizationStatus()
        await synchronizeIfPossible()
    }

    /// Requests system notification permission, then synchronizes when APNs returns a token.
    func requestPermission() async {
        statusMessage = nil
        let granted = await notificationManager.requestAuthorization()
        if !granted {
            statusMessage = "通知權限未啟用，可稍後在 iPhone 設定中開啟。"
        }
        await synchronizeIfPossible()
    }

    /// Opens the app-specific iOS Settings page so a denied permission can be changed.
    func openSystemSettings() {
        notificationManager.openSystemSettings()
    }

    /// Persists and synchronizes the user's chosen alert threshold.
    func updateThreshold(_ newValue: Int) async {
        guard (0...1_000_000_000).contains(newValue) else {
            statusMessage = "請輸入有效的通知門檻。"
            return
        }

        threshold = newValue
        defaults.set(newValue, forKey: PreferenceKey.threshold)
        await synchronizeIfPossible()
    }

    /// Enables or disables future alerts for this installation.
    func setNotificationsEnabled(_ enabled: Bool) async {
        notificationsEnabled = enabled
        defaults.set(enabled, forKey: PreferenceKey.enabled)

        if enabled && authorizationStatus == .notDetermined {
            await requestPermission()
            return
        }

        await synchronizeIfPossible()
    }

    /// Sends current settings only when both the Worker URL and APNs token exist.
    func synchronizeIfPossible() async {
        guard !isSynchronizing else {
            return
        }

        guard let apiClient else {
            statusMessage = JackpotAPIError.invalidConfiguration.localizedDescription
            return
        }

        guard let deviceToken = notificationManager.deviceToken else {
            return
        }

        isSynchronizing = true
        statusMessage = nil
        defer { isSynchronizing = false }

        let registration = NotificationRegistration(
            installationId: installationId,
            deviceToken: deviceToken,
            threshold: threshold,
            enabled: notificationsEnabled,
            apnsEnvironment: apnsEnvironment
        )

        do {
            try await apiClient.register(registration)
            statusMessage = notificationsEnabled ? "通知設定已更新。" : "通知已關閉。"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    /// Selects the APNs gateway matching the active build provisioning environment.
    private var apnsEnvironment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }
}

/// UserDefaults keys owned by notification settings.
private enum PreferenceKey {
    static let threshold = "notification.threshold"
    static let enabled = "notification.enabled"
    static let installationId = "notification.installationId"
}
