//
//  MountShareIntent.swift
//  Network Share Mounter
//
//  Copyright © 2026 RRZE. All rights reserved.
//

import AppIntents
import Foundation

/// An App Intent that mounts a specific configured network share.
///
/// Allows Siri and Shortcuts to mount individual shares by name, e.g.:
/// "Mount RRZE-Share in Network Share Mounter"
struct MountShareIntent: AppIntent {
    static var title: LocalizedStringResource = LocalizedStringResource("MountShare.Title", table: "Localizable")
    static var description = IntentDescription(LocalizedStringResource("MountShare.Description", table: "Localizable"))
    static var openAppWhenRun: Bool = false

    @Parameter(title: LocalizedStringResource("MountShare.Parameter.Share", table: "Localizable"))
    var share: ShareAppEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        DistributedNotificationCenter.default().post(
            name: .nsmDistributedMountShareTrigger,
            object: share.id
        )
        return .result(
            dialog: IntentDialog(stringLiteral: String(
                format: String(localized: "MountShare.Success", table: "Localizable"),
                share.name
            ))
        )
    }
}
