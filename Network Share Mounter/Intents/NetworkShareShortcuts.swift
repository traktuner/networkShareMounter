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

    /// The collection of shortcuts made available to the Shortcuts app.
    ///
    /// This property constructs:
    /// - The app name used to substitute the `%@` placeholder in localized phrases.
    /// - Localized short titles for the mount and unmount actions.
    /// - Localized phrases that users can speak or type to invoke the shortcuts.
    ///
    /// It then returns two ``AppShortcut`` instances:
    /// 1. One for mounting all shares using ``MountAllSharesIntent``.
    /// 2. One for unmounting all shares using ``UnmountAllSharesIntent``.
    ///
    /// - Returns: An array containing the mount and unmount shortcuts.
    static var appShortcuts: [AppShortcut] {
        // Resolve the app name used to fill the `%@` placeholder in phrases.
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "App"

        // Localized short titles from the "Localizable" table.
        let mountShortTitle: LocalizedStringResource = LocalizedStringResource("Shortcuts.Mount.ShortTitle", table: "Localizable")
        let unmountShortTitle: LocalizedStringResource = LocalizedStringResource("Shortcuts.Unmount.ShortTitle", table: "Localizable")

        // Localized phrases from the "Localizable" table (with `%@` for the app name).
        let mountPhrase1String = String(format: String(localized: "Shortcuts.Phrase.Mount.1", table: "Localizable"), appName)
        let mountPhrase2String = String(format: String(localized: "Shortcuts.Phrase.Mount.2", table: "Localizable"), appName)
        let unmountPhrase1String = String(format: String(localized: "Shortcuts.Phrase.Unmount.1", table: "Localizable"), appName)
        let unmountPhrase2String = String(format: String(localized: "Shortcuts.Phrase.Unmount.2", table: "Localizable"), appName)

        return [
            AppShortcut(
                intent: MountAllSharesIntent(),
                phrases: [
                    .init(mountPhrase1String),
                    .init(mountPhrase2String)
                ],
                shortTitle: mountShortTitle,
                systemImageName: "externaldrive.connected.to.line.below"
            ),
            AppShortcut(
                intent: UnmountAllSharesIntent(),
                phrases: [
                    .init(unmountPhrase1String),
                    .init(unmountPhrase2String)
                ],
                shortTitle: unmountShortTitle,
                systemImageName: "externaldrive.badge.minus"
            )
        ]
    }
}
