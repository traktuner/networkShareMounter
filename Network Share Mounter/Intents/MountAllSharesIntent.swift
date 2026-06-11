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
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        DistributedNotificationCenter.default().post(name: .nsmDistributedMountTrigger, object: nil)
        return .result(dialog: IntentDialog(LocalizedStringResource("MountAllShares.Success", table: "Localizable")))
    }
}

