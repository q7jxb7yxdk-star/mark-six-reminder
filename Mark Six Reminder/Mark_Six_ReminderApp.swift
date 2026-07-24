//
//  Mark_Six_ReminderApp.swift
//  Mark Six Reminder
//
//  Created by Sunny Yu on 15/7/2026.
//

import SwiftUI
import SwiftData

@main
struct Mark_Six_ReminderApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var notificationManager: NotificationManager
    @State private var settingsViewModel: SettingsViewModel

    /// Creates shared notification models used by UIKit callbacks and SwiftUI settings.
    init() {
        let notificationManager = NotificationManager()
        _notificationManager = State(initialValue: notificationManager)
        _settingsViewModel = State(
            initialValue: SettingsViewModel(notificationManager: notificationManager)
        )
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(notificationManager)
                .environment(settingsViewModel)
                .task {
                    appDelegate.notificationManager = notificationManager
                    await settingsViewModel.prepare()
                }
        }
        .modelContainer(for: SavedNumberEntry.self)
    }
}
