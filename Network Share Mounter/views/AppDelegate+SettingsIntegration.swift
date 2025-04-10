import SwiftUI
import AppKit

/// Extension to integrate the new SwiftUI settings into the existing app
extension AppDelegate {
    /// Opens the settings window using the SettingsWindowManager
    @objc func openSettings() {
        SettingsWindowManager.shared.showSettingsWindow()
    }
    
    /// Updates the application menu to use the new settings window
    func setupSettingsMenuItem() {
        // Find the "Preferences..." menu item in the application menu
        if let appMenu = NSApp.mainMenu?.item(at: 0)?.submenu,
           let preferencesItem = appMenu.item(withTitle: "Einstellungen...") ?? appMenu.item(withTitle: "Preferences...") {
            
            // Replace the existing action with our new settings opener
            preferencesItem.action = #selector(openSettings)
            preferencesItem.target = self
        }
    }
    
    /// Call this method in applicationDidFinishLaunching to set up the new settings integration
    func configureSettingsIntegration() {
        // Update menu items to point to the new settings window
        setupSettingsMenuItem()
        
        // If there are other places in your app that open settings, make sure they call openSettings()
    }
}

// MARK: - Menu Actions Extension
extension AppDelegate {
    /// Method to be called from the status item menu
    @objc func openPreferencesFromStatusMenu(_ sender: NSMenuItem) {
        openSettings()
    }
    
    /// Updates the status item menu to use the new settings
    func updateStatusItemMenuForNewSettings() {
        // This method would update your existing status item menu items to call the new openSettings method
        // Example implementation (adjust based on your actual menu structure):
        
        // Assuming you have a status item menu somewhere in your app:
        if let menu = statusItem.menu,
           let preferencesItem = menu.item(withTitle: "Einstellungen...") ?? menu.item(withTitle: "Preferences...") {
            preferencesItem.action = #selector(openPreferencesFromStatusMenu(_:))
            preferencesItem.target = self
        }
    }
} 