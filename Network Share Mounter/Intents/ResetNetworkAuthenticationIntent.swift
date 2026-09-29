//
//  ResetNetworkAuthenticationIntent.swift
//  Network Share Mounter
//
//  Copyright © 2026 RRZE. All rights reserved.
//

import AppIntents
import Foundation

/// An App Intent that resets the network authentication agent, like the
/// "Reset Network Authentication" button in the settings.
///
/// It terminates a stuck NetAuthSysAgent, which macOS restarts automatically.
/// Shares are not remounted; combine it with the mount intents in Shortcuts if needed.
struct ResetNetworkAuthenticationIntent: AppIntent {

    static var title: LocalizedStringResource = LocalizedStringResource("ResetNetworkAuthentication.Title", table: "Localizable")

    static var description = IntentDescription(LocalizedStringResource("ResetNetworkAuthentication.Description", table: "Localizable"))

    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let agentKilled = await NetworkAuthReset.perform()
        let message = agentKilled
            ? LocalizedStringResource("ResetNetworkAuthentication.Success", table: "Localizable")
            : LocalizedStringResource("ResetNetworkAuthentication.AlreadyClean", table: "Localizable")
        return .result(dialog: IntentDialog(message))
    }
}
