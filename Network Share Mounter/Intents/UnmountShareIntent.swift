//
//  UnmountShareIntent.swift
//  Network Share Mounter
//
//  Copyright © 2026 RRZE. All rights reserved.
//

import AppIntents
import Foundation

/// An App Intent that unmounts a specific configured network share.
///
/// Allows Siri and Shortcuts to unmount individual shares by name, e.g.:
/// "Unmount RRZE-Share in Network Share Mounter"
struct UnmountShareIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource("UnmountShare.Title", table: "Localizable")
    static var description = IntentDescription(LocalizedStringResource("UnmountShare.Description", table: "Localizable"))
    static var openAppWhenRun: Bool = false

    @Parameter(title: LocalizedStringResource("UnmountShare.Parameter.Share", table: "Localizable"))
    var share: ShareAppEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        DistributedNotificationCenter.default().post(
            name: .nsmDistributedUnmountShareTrigger,
            object: share.id
        )
        return .result(
            dialog: IntentDialog(stringLiteral: String(
                format: String(localized: "UnmountShare.Success", table: "Localizable"),
                share.name
            ))
        )
    }
}
