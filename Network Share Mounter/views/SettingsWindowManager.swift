//
//  GeneralSettingsView.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 10.04.25.
//  Copyright © 2024 RRZE. All rights reserved.
//

import SwiftUI
import AppKit

/// Manager for controlling the settings window lifecycle
class SettingsWindowManager: NSObject, NSWindowDelegate {
    /// The singleton instance of the manager
    static let shared = SettingsWindowManager()
    
    /// The settings window instance
    private var settingsWindow: NSWindow?
    
    /// Private initializer to enforce singleton pattern
    private override init() {
        super.init()
    }
    
    /// Shows the settings window or brings it to front if already open
    func showSettingsWindow() {
        // If window exists, just bring it to front
        if let window = settingsWindow {
            if window.isVisible {
                window.orderFrontRegardless()
            } else {
                window.makeKeyAndOrderFront(nil)
            }
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // Create a new window
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 850, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        // Configure the window
        window.title = "Einstellungen"
        window.center()
        window.setFrameAutosaveName("SettingsWindow")
        window.identifier = NSUserInterfaceItemIdentifier("SettingsWindow")
        window.isReleasedWhenClosed = false
        window.delegate = self
        
        // Set minimum size to match the constraints in SettingsView
        window.minSize = NSSize(width: 850, height: 500)
        
        // Use Core Animation for smooth transitions
        window.animationBehavior = .documentWindow
        
        // Create and set the SwiftUI content view
        let contentView = SettingsView()
        window.contentView = NSHostingView(rootView: contentView)
        
        // Show the window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        
        // Store the reference
        self.settingsWindow = window
    }
    
    /// Closes the settings window if it's open
    func closeSettingsWindow() {
        settingsWindow?.close()
    }
    
    // MARK: - NSWindowDelegate
    
    func windowWillClose(_ notification: Notification) {
        // We keep the window around for performance reasons
        // but could clean up resources here if needed
    }
} 
