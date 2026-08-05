//
//  Network_Share_MounterApp.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 17.05.26.
//  Copyright © 2026 RRZE. All rights reserved.
//

import SwiftUI
import AppKit
import OSLog
import AppIntents

// MARK: - Notification Extensions
extension Notification.Name {
    static let showSettingsScene = Notification.Name("showSettingsScene")
}

// MARK: - Window Hider

/// NSView subclass that hides its host window the instant it joins the window hierarchy.
///
/// `viewDidMoveToWindow()` fires synchronously during SwiftUI's view setup — before the
/// window server has committed a frame — so the window is never visible on screen, not
/// even for a single frame. Setting `alphaValue = 0` first makes it doubly invisible in
/// case the window server and SwiftUI race on the very first frame.
private final class _ImmediatelyHiddenView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.alphaValue = 0
        window?.orderOut(nil)
    }
}

private struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> _ImmediatelyHiddenView { _ImmediatelyHiddenView() }
    func updateNSView(_ nsView: _ImmediatelyHiddenView, context: Context) {}
}

// MARK: - Settings Manager
@MainActor
class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @Published var pendingAutoOpenProfileCreation: Bool = false
    @Published var pendingMDMRealm: String? = nil

    // Callback to open window from SwiftUI App
    var openWindowCallback: ((String) -> Void)?

    private init() {
        // Listen for external requests to show the Settings scene
        NotificationCenter.default.addObserver(
            forName: .showSettingsScene,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Logger.app.debug("🔧 [DEBUG] Received showSettingsScene notification")
            let autoOpen = (notification.userInfo?["autoOpenProfileCreation"] as? Bool) ?? false
            let realm = notification.userInfo?["mdmRealm"] as? String
            Logger.app.debug("🔧 [DEBUG] autoOpen=\(autoOpen), realm=\(realm ?? "nil")")
            self?.pendingAutoOpenProfileCreation = autoOpen
            self?.pendingMDMRealm = realm
            self?.requestShowSettings()
        }
    }

    func requestShowSettings() {
        Logger.app.debug("🔧 [DEBUG] requestShowSettings() called")
        guard let openWindow = openWindowCallback else {
            Logger.app.error("🔧 [ERROR] openWindowCallback is nil!")
            return
        }
        Logger.app.debug("🔧 [DEBUG] Calling openWindow callback")
        NSApp.setActivationPolicy(.regular)
        openWindow("settings")
        // openWindow is async — defer activation until the window exists
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first(where: { $0.title == "Settings" })?.makeKeyAndOrderFront(nil)
        }
    }
}

@main
struct Network_Share_MounterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var settingsManager = SettingsManager.shared
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // Ghost window: immediately hidden by WindowAccessor, exists solely to obtain
        // the openWindow environment value and pass it to SettingsManager's callback.
        WindowGroup(id: "main-hidden") {
            Color.clear
                .frame(width: 0, height: 0)
                .background(WindowAccessor())
                .environmentObject(settingsManager)
                .onAppear {
                    settingsManager.openWindowCallback = { windowId in
                        openWindow(id: windowId)
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1, height: 1)
        .commandsRemoved()

        // Settings window.
        // Note: .commands {} is an app-wide modifier — it can technically be attached to
        // any scene. We attach it here as this is the only scene requiring custom commands.
        Window("Settings", id: "settings") {
            if let mounter = appDelegate.mounter {
                SettingsView(
                    autoOpenProfileCreation: settingsManager.pendingAutoOpenProfileCreation,
                    mdmRealm: settingsManager.pendingMDMRealm
                )
                .frame(minWidth: 900, minHeight: 580)
                .environmentObject(settingsManager)
                .environmentObject(mounter)
            } else {
                Text("Initializing…")
            }
        }
        .defaultSize(width: 900, height: 600)
        .windowResizability(.contentSize)
        .handlesExternalEvents(matching: ["settings"])
        .commands {
            // Replace the default app settings menu entry with our own scene-based one.
            // Important: do not use openWindow here — it creates a circular Environment
            // dependency during body evaluation (→ stack overflow). Instead, use the
            // SettingsManager callback, which is set safely after the first render (onAppear).
            CommandGroup(replacing: .appSettings) {
                Button("Settings\u{2026}") {
                    SettingsManager.shared.requestShowSettings()
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
    }
}

