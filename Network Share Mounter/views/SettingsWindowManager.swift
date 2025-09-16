//
//  SettingsWindowManager.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 10.04.25.
//  Copyright © 2024 RRZE. All rights reserved.
//

import Foundation

/// Manager for requesting the SwiftUI-based settings window (Scene) to appear.
///
/// In the modern SwiftUI approach (Option A), we do not construct NSWindow manually.
/// Instead, the App's SwiftUI Scene graph owns the window. This manager only posts
/// a notification with parameters that the SwiftUI App/Scene listens to and opens
/// the SettingsView accordingly.
final class SettingsWindowManager {
    static let shared = SettingsWindowManager()
    private init() {}

    /// Requests to show the Settings SwiftUI window (Scene).
    /// - Parameters:
    ///   - autoOpenProfileCreation: If true, automatically opens the profile creation dialog inside SettingsView.
    ///   - mdmRealm: Optional MDM-configured realm for pre-filling the profile creation dialog.
    func showSettingsWindow(autoOpenProfileCreation: Bool = false, mdmRealm: String? = nil) {
        // In a pure SwiftUI Scene setup, the App listens to this notification
        // and toggles the state that presents a Settings Scene/Window.
        NotificationCenter.default.post(
            name: .showSettingsScene,
            object: nil,
            userInfo: [
                "autoOpenProfileCreation": autoOpenProfileCreation,
                "mdmRealm": mdmRealm as Any
            ]
        )
    }

    /// No-op in SwiftUI Scene world. Closing is handled by the Scene/UI state.
    func closeSettingsWindow() {
        // Intentionally left empty; closing is driven by SwiftUI state/scene management.
    }
}
