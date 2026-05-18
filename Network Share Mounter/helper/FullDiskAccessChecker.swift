//
//  FullDiskAccessChecker.swift
//  Network Share Mounter
//
//  Created by Gregor Longariva on 18.05.26.
//  Copyright © 2024 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import AppKit
import Foundation
import OSLog

struct FullDiskAccessChecker {

    /// Returns true if the app currently has Full Disk Access.
    /// Reads the system TCC database, which is only accessible with FDA granted.
    static func hasAccess() -> Bool {
        FileManager.default.isReadableFile(atPath: "/Library/Application Support/com.apple.TCC/TCC.db")
    }

    /// Shows a Full Disk Access prompt when required.
    ///
    /// Only shown on macOS 26+, only when the mount path is outside /Volumes, and only when FDA is not
    /// already granted. Attempting to read TCC.db also registers the app in the FDA candidate list so
    /// the user can grant access with a single click in System Settings.
    ///
    /// - Parameters:
    ///   - mountPath: The configured default mount path.
    ///   - onOpenSettings: Called when the user chooses to open System Settings.
    ///   - onSwitchToVolumes: Called when the user chooses to fall back to /Volumes.
    @MainActor
    static func promptIfNeeded(
        forMountPath mountPath: String,
        onOpenSettings: () -> Void,
        onSwitchToVolumes: () -> Void
    ) {
        guard #available(macOS 26, *) else { return }
        guard !mountPath.hasPrefix("/Volumes") else { return }
        guard !hasAccess() else { return }

        Logger.app.warning("⚠️ Full Disk Access not granted; mount path outside /Volumes: \(mountPath, privacy: .public)")

        let alert = NSAlert()
        alert.messageText = NSLocalizedString(
            "Full Disk Access Required",
            comment: "FDA alert title"
        )
        alert.informativeText = String(
            format: NSLocalizedString(
                "Network Share Mounter needs Full Disk Access to mount network shares to \"%@\". Without this permission, shares can only be mounted under /Volumes.\n\nGrant Full Disk Access in System Settings → Privacy & Security → Full Disk Access.",
                comment: "FDA alert message; %@ is the configured mount path"
            ),
            mountPath
        )
        alert.addButton(withTitle: NSLocalizedString("Open System Settings\u{2026}", comment: "FDA open settings button"))
        alert.addButton(withTitle: NSLocalizedString("Use /Volumes Instead", comment: "FDA fallback to /Volumes button"))
        alert.alertStyle = .warning

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            onOpenSettings()
        default:
            onSwitchToVolumes()
        }
    }
}
