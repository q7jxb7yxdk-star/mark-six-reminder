import Observation
import UIKit
import UserNotifications

/// Coordinates notification authorization and the APNs token supplied by iOS.
@MainActor
@Observable
final class NotificationManager {
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var deviceToken: String?

    @ObservationIgnored
    var deviceTokenDidChange: ((String) -> Void)?

    /// Refreshes authorization state without displaying a system prompt.
    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus

        if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// Requests visible alert permission and registers with APNs when accepted.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .badge, .sound]
            )
            await refreshAuthorizationStatus()
            return granted
        } catch {
            await refreshAuthorizationStatus()
            return false
        }
    }

    /// Opens this app's iOS Settings page after the system prompt has been denied.
    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url)
    }

    /// Converts APNs token bytes into the lowercase hexadecimal form expected by the Worker.
    func receiveDeviceToken(_ data: Data) {
        let token = data.map { String(format: "%02x", $0) }.joined()
        guard token != deviceToken else {
            return
        }

        deviceToken = token
        deviceTokenDidChange?(token)
    }
}

/// Bridges UIKit application callbacks into the observable notification model.
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var notificationManager: NotificationManager? {
        didSet {
            if let pendingDeviceToken {
                notificationManager?.receiveDeviceToken(pendingDeviceToken)
                self.pendingDeviceToken = nil
            }
        }
    }

    private var pendingDeviceToken: Data?

    /// Installs the foreground notification delegate at app launch.
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Forwards a newly issued APNs token to the app model.
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        if let notificationManager {
            notificationManager.receiveDeviceToken(deviceToken)
        } else {
            pendingDeviceToken = deviceToken
        }
    }

    /// Logs registration failures without showing technical details to the user.
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: any Error
    ) {
        print("APNs registration failed: \(error.localizedDescription)")
    }

    /// Displays jackpot alerts even when the app is currently in the foreground.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
