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
/// Hides the host NSWindow that SwiftUI's WindowGroup creates automatically on launch.
/// Menu-bar apps have no main window; this prevents the blank white window from appearing.
private struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            view.window?.orderOut(nil)
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
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
        if let openWindow = openWindowCallback {
            Logger.app.debug("🔧 [DEBUG] Calling openWindow callback")
            openWindow("settings")
        } else {
            Logger.app.error("🔧 [ERROR] openWindowCallback is nil!")
        }
    }
}

@main
struct Network_Share_MounterApp: App {
    // Bridge den bestehenden AppDelegate in den SwiftUI-Lifecycle
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    // Use StateObject for the settings manager
    @StateObject private var settingsManager = SettingsManager.shared

    // Environment for opening windows
    @Environment(\.openWindow) private var openWindow
    
    // Register App Shortcuts for Siri and Shortcuts app
    static var appShortcutsProvider: some AppShortcutsProvider {
        NetworkShareShortcuts()
    }

    var body: some Scene {
        WindowGroup(id: "main-hidden") {
            // Invisible host view — needed only to obtain the openWindow environment value.
            // WindowAccessor immediately hides the window that SwiftUI creates automatically.
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

        // Settings as window (scene)
        Window("Settings", id: "settings") {
            // SettingsView mit den (ggf. aus Notification) übernommenen Parametern
            if let mounter = appDelegate.mounter {
                SettingsView(
                    autoOpenProfileCreation: settingsManager.pendingAutoOpenProfileCreation,
                    mdmRealm: settingsManager.pendingMDMRealm
                )
                .frame(minWidth: 900, minHeight: 580)
                .environmentObject(settingsManager)
                .environmentObject(mounter)
            } else {
                Text("Initializing...")
            }
        }
        .defaultSize(width: 900, height: 600)
        .windowResizability(.contentSize)
        .handlesExternalEvents(matching: Set(arrayLiteral: "settings"))

        // Menü-Kommandos
        .commands {
            // Ersetze den Standard-App-Einstellungen-Eintrag und öffne unsere Scene.
            // Wichtig: openWindow hier NICHT verwenden – das erzeugt eine zirkuläre
            // Environment-Abhängigkeit während der Body-Auswertung (→ Stack Overflow).
            // Stattdessen den SettingsManager-Callback nutzen, der erst nach dem
            // ersten Render (onAppear) gesetzt wird.
            CommandGroup(replacing: .appSettings) {
                Button("Settings …") {
                    SettingsManager.shared.requestShowSettings()
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
    }
}
