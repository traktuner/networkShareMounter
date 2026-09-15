//
//  SettingsWindowManager.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 10.04.25.
//  Copyright © 2025 RRZE. All rights reserved.
//

import AppKit
import OSLog
import SwiftUI

/// Owns the Settings window.
///
/// The window is a plain `NSWindow` hosting `SettingsView` — deliberately *not* a SwiftUI
/// `Scene`. A scene-owned window only comes into existence when SwiftUI decides to present its
/// scene, and that decision is not ours to make: a scene presents itself at launch only if it is
/// the app's first scene and no window state was restored, and macOS skips that step altogether
/// when it starts an `LSUIElement` agent in the background as a login item. In such a session
/// the scene — and with it the `openWindow` action the previous implementation captured from a
/// hidden helper window — never existed, so Settings could not be opened for the entire lifetime
/// of that process.
///
/// Creating the window here removes the dependency: the window exists because we allocate it,
/// following the same pattern the password-expiration and credential-onboarding dialogs use.
@MainActor
final class SettingsWindowManager {
    static let shared = SettingsWindowManager()

    private static let defaultContentSize = NSSize(width: 900, height: 600)
    private static let minContentSize = NSSize(width: 900, height: 580)
    private static let frameAutosaveName = "NSMSettingsWindow"

    /// Strong reference: the window must outlive being closed so it can be shown again.
    private var window: NSWindow?

    private init() {}

    /// Shows the Settings window, creating it on first use.
    /// - Parameters:
    ///   - autoOpenProfileCreation: Opens the profile creation dialog inside `SettingsView`.
    ///   - mdmRealm: MDM-configured realm used to pre-fill that dialog.
    ///   - mounter: Injected into the view hierarchy; the share and profile views require it.
    func showSettingsWindow(autoOpenProfileCreation: Bool = false,
                            mdmRealm: String? = nil,
                            mounter: Mounter?) {
        guard let mounter else {
            Logger.app.error("❌ Cannot show Settings window: mounter is not initialized")
            return
        }

        let settingsWindow: NSWindow
        if let existing = window {
            // Rebuild the content when the window is reopened or the caller needs a specific
            // initial state. An already visible window keeps its current state.
            if !existing.isVisible || autoOpenProfileCreation {
                let frame = existing.frame
                existing.contentViewController = makeContentController(
                    autoOpenProfileCreation: autoOpenProfileCreation,
                    mdmRealm: mdmRealm,
                    mounter: mounter
                )
                existing.contentMinSize = Self.minContentSize
                existing.setFrame(frame, display: false)
            }
            settingsWindow = existing
        } else {
            settingsWindow = makeWindow(contentViewController: makeContentController(
                autoOpenProfileCreation: autoOpenProfileCreation,
                mdmRealm: mdmRealm,
                mounter: mounter
            ))
            window = settingsWindow
        }

        bringToFront(settingsWindow)
    }

    private func makeContentController(autoOpenProfileCreation: Bool,
                                       mdmRealm: String?,
                                       mounter: Mounter) -> NSViewController {
        let rootView = SettingsView(autoOpenProfileCreation: autoOpenProfileCreation, mdmRealm: mdmRealm)
            .frame(minWidth: Self.minContentSize.width, minHeight: Self.minContentSize.height)
            .environmentObject(mounter)
        return NSHostingController(rootView: rootView)
    }

    private func makeWindow(contentViewController: NSViewController) -> NSWindow {
        let window = NSWindow(contentViewController: contentViewController)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.title = NSLocalizedString("Settings", comment: "Settings window title")
        window.contentMinSize = Self.minContentSize
        window.setContentSize(Self.defaultContentSize)
        // The window is owned here, not by AppKit: it must survive being closed, and it must stay
        // out of the system's window restoration — restored window state is precisely what kept
        // the previous scene-based window from being created in the first place.
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.setFrameAutosaveName(Self.frameAutosaveName)
        if !window.setFrameUsingName(Self.frameAutosaveName) {
            window.center()
        }
        return window
    }

    /// Brings the window forward, switching the app out of its menu bar agent role first.
    private func bringToFront(_ window: NSWindow) {
        // As an accessory the app has no Dock icon, and macOS refuses to make its windows key.
        // `.regular` gives the Settings window a Dock icon and a menu bar — the latter also
        // supplies ⌘C/⌘V inside its text fields. AppDelegate restores `.accessory` on close.
        let policyChanged = NSApp.activationPolicy() != .regular
        if policyChanged {
            NSApp.setActivationPolicy(.regular)
        }

        activate(window)

        // The activation policy change reaches the window server asynchronously; without a second
        // pass on the next run loop turn the window can end up behind the previously active app.
        if policyChanged {
            DispatchQueue.main.async { [weak self] in
                self?.activate(window)
            }
        }
    }

    private func activate(_ window: NSWindow) {
        // Since macOS 14 activation is a request and `ignoringOtherApps` is ignored/deprecated.
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
