//
//  Network_Share_MounterApp.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 17.05.26.
//  Copyright © 2026 RRZE. All rights reserved.
//

import SwiftUI

@main
struct Network_Share_MounterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // This app owns no SwiftUI-managed windows: Settings and every dialog are AppKit windows
        // created on demand by SettingsWindowManager and AppDelegate, so they exist no matter how
        // macOS launched the app (a scene does not, see SettingsWindowManager). `App` still needs
        // one scene — this one is never presented and only carries the app-wide menu commands.
        Settings {
            EmptyView()
        }
        .commands {
            // Replace the default app settings menu entry with one that opens our own window.
            CommandGroup(replacing: .appSettings) {
                Button("Settings\u{2026}") {
                    SettingsWindowManager.shared.showSettingsWindow(mounter: appDelegate.mounter)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
    }
}
