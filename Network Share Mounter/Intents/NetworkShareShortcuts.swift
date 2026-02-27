//
//  NetworkShareShortcuts.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 28.10.25.
//  Copyright © 2025 RRZE. All rights reserved.
//

import AppIntents

/// A provider of App Shortcuts that allow users to mount or unmount all configured network shares.
///
/// This type conforms to ``AppShortcutsProvider`` and publishes two shortcuts to the Shortcuts app:
/// - A shortcut to mount all shares.
/// - A shortcut to unmount all shares.
///
/// The phrases for invocation are localized from the "Localizable" strings table and interpolate
/// the app’s display name into a `%@` placeholder. The short titles are also localized.
///
/// - SeeAlso: ``MountAllSharesIntent``
/// - SeeAlso: ``UnmountAllSharesIntent``
struct NetworkShareShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: MountAllSharesIntent(),
            phrases: [
                "Connect shares in \(.applicationName)",
                "Mount shares in \(.applicationName)",
                "Mount network drives in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("Shortcuts.Mount.ShortTitle", table: "Localizable"),
            systemImageName: "externaldrive.connected.to.line.below"
        )
        AppShortcut(
            intent: UnmountAllSharesIntent(),
            phrases: [
                "Disconnect shares in \(.applicationName)",
                "Unmount shares in \(.applicationName)",
                "Unmount network drives in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("Shortcuts.Unmount.ShortTitle", table: "Localizable"),
            systemImageName: "externaldrive.badge.minus"
        )
        AppShortcut(
            intent: RenewKerberosTicketIntent(),
            phrases: [
                "Renew Kerberos ticket in \(.applicationName)",
                "Refresh authentication in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("Shortcuts.RenewKerberos.ShortTitle", table: "Localizable"),
            systemImageName: "ticket.fill"
        )
        AppShortcut(
            intent: GetKerberosStatusIntent(),
            phrases: [
                "Check Kerberos status in \(.applicationName)",
                "Show ticket status in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("Shortcuts.KerberosStatus.ShortTitle", table: "Localizable"),
            systemImageName: "checkmark.shield.fill"
        )
        AppShortcut(
            intent: GetMountStatusIntent(),
            phrases: [
                "Check share status in \(.applicationName)",
                "Show mount status in \(.applicationName)"
            ],
            shortTitle: LocalizedStringResource("Shortcuts.MountStatus.ShortTitle", table: "Localizable"),
            systemImageName: "chart.bar.doc.horizontal.fill"
        )
    }
}
