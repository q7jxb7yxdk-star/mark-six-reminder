import Foundation
import Observation
import UserNotifications

/// Owns persisted jackpot notification preferences and backend synchronization state.
@MainActor
@Observable
final class SettingsViewModel {
    static let presetThresholds = [8_000_000, 13_000_000, 18_000_000]

    private(set) var threshold: Int
    private(set) var notificationsEnabled: Bool
    private(set) var isSynchronizing = false
    private(set) var isRegisteringDevice = false
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

        threshold = defaults.object(forKey: PreferenceKey.threshold) as? Int ?? 13_000_000
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
                self?.isRegisteringDevice = false
                await self?.synchronizeIfPossible()
            }
        }
        notificationManager.registrationDidFail = { [weak self] message in
            Task { @MainActor [weak self] in
                self?.isRegisteringDevice = false
                self?.statusMessage = "無法註冊通知裝置：\(message)"
            }
        }
    }

    /// Exposes the current iOS authorization state for settings UI decisions.
    var authorizationStatus: UNAuthorizationStatus {
        notificationManager.authorizationStatus
    }

    /// Indicates that either APNs registration or backend synchronization is active.
    var isBusy: Bool {
        isRegisteringDevice || isSynchronizing
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
            return
        }
        await synchronizeIfPossible()
    }

    /// Opens the app-specific iOS Settings page so a denied permission can be changed.
    func openSystemSettings() {
        notificationManager.openSystemSettings()
    }

    /// Persists and synchronizes the user's chosen alert threshold.
    func updateThreshold(_ newValue: Int) async {
        guard Self.presetThresholds.contains(newValue) else {
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

        if enabled {
            await notificationManager.refreshAuthorizationStatus()
        } else {
            isRegisteringDevice = false
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
            if notificationsEnabled && hasSystemAuthorization {
                isRegisteringDevice = true
                statusMessage = "正在註冊通知裝置…"
            }
            return
        }

        isRegisteringDevice = false
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
            statusMessage = notificationsEnabled ? nil : "通知已關閉。"
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

    /// Returns whether iOS currently permits this app to register for notifications.
    private var hasSystemAuthorization: Bool {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            true
        default:
            false
        }
    }
}

/// UserDefaults keys owned by notification settings.
private enum PreferenceKey {
    static let threshold = "notification.threshold"
    static let enabled = "notification.enabled"
    static let installationId = "notification.installationId"
}
