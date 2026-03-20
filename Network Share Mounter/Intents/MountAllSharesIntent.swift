//
//  MountAllSharesIntent.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 28.10.25.
//  Copyright © 2025 RRZE. All rights reserved.
//

import AppIntents
import SwiftUI

/// An App Intent that triggers mounting all configured network shares.
///
/// This intent is designed to be invoked from system surfaces such as Shortcuts or Siri.
/// When executed, it posts a distributed notification that the main app observes to perform
/// the actual mounting operation. Using a distributed notification is necessary because
/// App Intents run in a separate process from the host app.
///
/// The app is brought to the foreground when the intent runs to offer immediate feedback
/// or to present UI related to the mounting process.
struct MountAllSharesIntent: AppIntent {

    /// The localized display title shown in Shortcuts, Siri, and other system surfaces.
    ///
    /// The value is resolved from the `Localizable.strings` table using the key
    /// `MountAllShares.Title`.
    static var title: LocalizedStringResource = LocalizedStringResource("MountAllShares.Title", table: "Localizable")

    /// The localized, user‑facing description explaining what this intent does.
    ///
    /// The value is resolved from the `Localizable.strings` table using the key
    /// `MountAllShares.Description`.
    static var description = IntentDescription(LocalizedStringResource("MountAllShares.Description", table: "Localizable"))

    /// Indicates whether the host app should open when the intent is executed.
    ///
    /// This is set to `true` so that the app can provide visual feedback or
    /// additional context while mounting shares.
    static var openAppWhenRun: Bool = true

    /// Performs the intent by notifying the main application to mount all shares.
    ///
    /// This method posts a distributed notification with the name
    /// ``Notification.Name/nsmDistributedMountTrigger`` so that the main app,
    /// which is listening for this notification, can initiate the mount process.
    ///
    /// The use of `DistributedNotificationCenter` is required because the intent
    /// extension runs in a separate process from the app.
    ///
    /// - Returns: An empty intent result indicating successful dispatch of the trigger.
    /// - Throws: Never currently throws. Reserved for future error propagation if needed.
    /// - Important: Ensure the main app registers an observer for the distributed
    ///   notification to handle the mount logic; otherwise, this intent will have no effect.
    func perform() async throws -> some IntentResult {
        // Use DistributedNotificationCenter because the intent extension runs in a separate process.
        DistributedNotificationCenter.default().post(name: .nsmDistributedMountTrigger, object: nil)
        return .result()
    }
}

