//
//  Network_Share_MounterApp.swift
//  Network Share Mounter
//
//  Created by AI Assistant on 16.09.25.
//

import SwiftUI
import AppKit
import OSLog

// MARK: - Notification Extensions
extension Notification.Name {
    static let showSettingsScene = Notification.Name("showSettingsScene")
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

    // Single source of truth for Mounter in SwiftUI world
    @StateObject private var mounter = Mounter()

    // Environment for opening windows
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // Hauptszene: Deine App ist menüleistenbasiert, daher ggf. keine Hauptfenster-UI nötig.
        // Wir lassen die Default-WindowGroup leer, damit der AppDelegate weiterhin die Menülogik steuert.
        WindowGroup(id: "main-hidden") {
            // Eine leere, unsichtbare Root-View – AppDelegate steuert das UI über Statusbar.
            EmptyView()
                .frame(width: 0, height: 0)
                .environmentObject(mounter)
                .environmentObject(settingsManager)
                .onAppear {
                    // Wire AppDelegate to use the same Mounter instance
                    appDelegate.mounter = mounter

                    // Set the callback when the app starts
                    Logger.app.debug("🔧 [DEBUG] Setting openWindow callback")
                    settingsManager.openWindowCallback = { windowId in
                        Logger.app.debug("🔧 [DEBUG] Opening window: \(windowId)")
                        openWindow(id: windowId)
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 10, height: 10)
        .commandsRemoved() // keine Standard-Kommandos für diese versteckte Szene

        // Einstellungen als eigenes Fenster (Scene)
        Window("Einstellungen", id: "settings") {
            // SettingsView mit den (ggf. aus Notification) übernommenen Parametern
            SettingsView(
                autoOpenProfileCreation: settingsManager.pendingAutoOpenProfileCreation,
                mdmRealm: settingsManager.pendingMDMRealm
            )
            .frame(minWidth: 900, minHeight: 580) // konsistent mit SettingsView
            .environmentObject(settingsManager)
            .environmentObject(mounter)
            .onAppear {
                Logger.app.debug("🔧 [DEBUG] Settings window appeared")
            }
        }
        .defaultSize(width: 900, height: 600)
        .windowResizability(.contentSize)
        .keyboardShortcut(",", modifiers: [.command])
        .handlesExternalEvents(matching: Set(arrayLiteral: "settings"))

        // Menü-Kommandos
        .commands {
            // Ersetze den Standard-App-Einstellungen-Eintrag und öffne unsere Scene
            CommandGroup(replacing: .appSettings) {
                Button("Einstellungen …") {
                    Logger.app.debug("🔧 [DEBUG] Einstellungen menu button clicked")
                    openWindow(id: "settings")
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
    }
}
