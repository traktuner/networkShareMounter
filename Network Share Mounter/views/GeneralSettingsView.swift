//
//  GeneralSettingsView.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 10.04.25.
//  Copyright © 2024 RRZE. All rights reserved.
//

import SwiftUI
import Sparkle // Keep import for SPUUpdaterController access via AppDelegate
import LaunchAtLogin // Import for Start at Login toggle

/// A view for configuring general application settings.
///
/// This view allows users to modify settings such as:
/// - Starting the application at login.
/// - Sending anonymous diagnostic data.
/// - Managing software update preferences (checking automatically, installing automatically).
///
/// It interacts with `PreferenceManager` to load and save settings from `UserDefaults`,
/// uses the `LaunchAtLogin` library to manage the login item status, and interacts
/// with the `AppDelegate` to trigger Sparkle update checks.
/// MDM settings like disabling the update framework or preventing changes to the login item
/// are respected.
struct GeneralSettingsView: View {
    // Use PreferenceManager to interact with UserDefaults
    private var prefs = PreferenceManager()
    
    /// Controls whether the application starts automatically when the user logs in.
    /// Initialized from `prefs.bool(for: .autostart)` in `.onAppear`.
    /// Changes are saved back to `prefs` and applied via `LaunchAtLogin.isEnabled` in `.onChange`,
    /// respecting the `.canChangeAutostart` preference.
    @State private var startAtLogin: Bool = false
    
    /// Controls whether anonymous diagnostic data should be sent.
    /// Initialized from `prefs.bool(for: .sendDiagnostics)` in `.onAppear`.
    /// Changes are saved back to `prefs` in `.onChange`.
    @State private var sendDiagnosticData: Bool = false
    
    /// Controls whether Sparkle should automatically check for updates.
    /// Initialized from `prefs.bool(for: .SUEnableAutomaticChecks)` in `.onAppear`.
    /// Changes are saved back to `prefs` in `.onChange`,
    /// respecting the `isUpdateFrameworkDisabled` state.
    @State private var automaticallyChecksForUpdates: Bool = false
    
    /// Controls whether Sparkle should automatically download and install updates.
    /// Initialized from `prefs.bool(for: .SUAutomaticallyUpdate)` in `.onAppear`.
    /// Changes are saved back to `prefs` in `.onChange`,
    /// respecting the `isUpdateFrameworkDisabled` and `automaticallyChecksForUpdates` states.
    @State private var automaticallyDownloadsUpdates: Bool = false
    
    /// Computed property indicating if the update framework is globally disabled via MDM.
    /// Reads the `.disableAutoUpdateFramework` preference.
    private var isUpdateFrameworkDisabled: Bool {
        prefs.bool(for: .disableAutoUpdateFramework)
    }
    
    // MARK: - Computed Properties for Bundle Info
    
    /// Fetches the application version (CFBundleShortVersionString) from the bundle's Info.plist.
    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        // Return "N/A" if version is nil OR empty
        return (version?.isEmpty ?? true) ? "N/A" : version!
    }
    
    /// Fetches the build number (CFBundleVersion) from the bundle's Info.plist.
    private var buildNumber: String {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        // Return "N/A" if build is nil OR empty
        return (build?.isEmpty ?? true) ? "N/A" : build!
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                
                // MARK: - Header Section
                HStack(spacing: 12) {
                    Image(systemName: "gearshape") // Icon for General
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Color.gray) // Background color for General
                        .cornerRadius(6)
                        .frame(width: 32, height: 32)
                        
                    VStack(alignment: .leading) {
                        Text("Allgemein") // Updated to German
                            .font(.headline)
                            .fontWeight(.medium)
                        Text("Passen Sie hier allgemeine Einstellungen der Anwendung an.") // Updated to German
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(10)
                .background(.quaternary.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                
                // MARK: - Startup Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Programmstart") // Updated to German
                        .font(.headline)
                    Toggle("Beim Anmelden starten", isOn: $startAtLogin) // Updated to German
                        .disabled(!prefs.bool(for: .canChangeAutostart))
                }
                .padding(.top, 8) // Add consistent spacing between header and first section
                .padding(.bottom, 8) // Add bottom spacing for consistency
                
                // MARK: - Diagnostic Data Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Diagnosedaten") // Updated to German
                        .font(.headline)
                    Toggle("Anonyme Diagnosedaten senden", isOn: $sendDiagnosticData) // Updated to German
                }
                .padding(.vertical, 8) // Add vertical spacing around the section
                
                // MARK: - Update Section
                VStack(alignment: .leading, spacing: 14) {
                    Text("Software-Aktualisierung") // Updated to German
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        // Toggle for enabling automatic update checks.
                        Toggle("Automatisch nach Updates suchen", isOn: $automaticallyChecksForUpdates) // Updated to German
                            .disabled(isUpdateFrameworkDisabled)
                            .padding(.leading, 20)
                        
                        // Toggle for enabling automatic update downloads/installs.
                        Toggle("Updates automatisch installieren", isOn: $automaticallyDownloadsUpdates) // Updated to German
                            .disabled(isUpdateFrameworkDisabled || !automaticallyChecksForUpdates)
                            .padding(.leading, 20)
                                                
                        // Button to manually trigger an update check.
                        HStack {
                            Button {
                                // Access AppDelegate and trigger check for updates
                                if let appDelegate = NSApp.delegate as? AppDelegate,
                                   let updaterController = appDelegate.updaterController {
                                    updaterController.checkForUpdates(nil)
                                } else {
                                    print("Could not find AppDelegate or UpdaterController")
                                }
                            } label: {
                                HStack {
                                    Image(systemName: "arrow.clockwise")
                                    Text("Jetzt nach Updates suchen") // Updated to German
                                }
                            }
                            .disabled(isUpdateFrameworkDisabled)
                        }
                        .padding(.leading, 20)
                        .padding(.top, 4)
                    }
                    
                    // Informational text shown when updates are disabled by MDM.
                    if isUpdateFrameworkDisabled {
                         Text("Die Verwaltung der Software-Aktualisierungen ist durch eine MDM-Richtlinie deaktiviert.") // Updated to German
                             .font(.caption)
                             .foregroundColor(.secondary)
                             .padding(.top, 5)
                    }
                }
                .padding(.vertical, 8) // Add vertical spacing
                
                // MARK: - Version Info Section
                VStack(alignment: .leading, spacing: 14) {
                    Text("Über") // Updated to German
                        .font(.headline)
                    
                    HStack {
                        Text("Version") // Keep as is (same in German)
                        Spacer()
                        // Display dynamic version and build number
                        Text(appVersion + " (" + buildNumber + ")")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8) // Add vertical spacing
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Apply consistent 20pt padding to the entire view, matching other views
        .padding(20)
        .onAppear { 
            // Load initial state from UserDefaults when the view appears.
            startAtLogin = prefs.bool(for: .autostart)
            sendDiagnosticData = prefs.bool(for: .sendDiagnostics)
            automaticallyChecksForUpdates = prefs.bool(for: .SUEnableAutomaticChecks)
            automaticallyDownloadsUpdates = prefs.bool(for: .SUAutomaticallyUpdate)
        }
        // MARK: - State Change Handlers
        .onChange(of: startAtLogin) { newValue in
             // Persist the login item state if allowed.
             if prefs.bool(for: .canChangeAutostart) {
                 LaunchAtLogin.isEnabled = newValue
                 prefs.set(for: .autostart, value: newValue)
             } else {
                 // Revert UI if change is disallowed by MDM.
                 Task { @MainActor in startAtLogin = prefs.bool(for: .autostart) }
             }
        }
        .onChange(of: sendDiagnosticData) { newValue in
            // Persist the diagnostic data preference.
            prefs.set(for: .sendDiagnostics, value: newValue)
            // TODO: Implement logic to start/stop diagnostic reporting based on newValue.
        }
        .onChange(of: automaticallyChecksForUpdates) { newValue in
            // Persist the automatic check preference if allowed.
            if !isUpdateFrameworkDisabled {
                prefs.set(for: .SUEnableAutomaticChecks, value: newValue)
                // Ensure automatic downloads are disabled if checks are disabled.
                if !newValue {
                    if automaticallyDownloadsUpdates { // Update state only if needed
                        automaticallyDownloadsUpdates = false
                    }
                    prefs.set(for: .SUAutomaticallyUpdate, value: false)
                }
            } else {
                 // Revert UI if change is disallowed by MDM.
                 Task { @MainActor in 
                     automaticallyChecksForUpdates = prefs.bool(for: .SUEnableAutomaticChecks)
                 }
            }
        }
        .onChange(of: automaticallyDownloadsUpdates) { newValue in
            // Persist the automatic download preference if allowed and checks are enabled.
            if !isUpdateFrameworkDisabled && automaticallyChecksForUpdates {
                 prefs.set(for: .SUAutomaticallyUpdate, value: newValue)
            } else {
                 // Revert UI if change is disallowed by MDM or checks are disabled.
                 Task { @MainActor in 
                     automaticallyDownloadsUpdates = prefs.bool(for: .SUAutomaticallyUpdate)
                 }
            }
        }
    }
}

#Preview {
    // Preview doesn't need the actual updater logic, just the view structure
    GeneralSettingsView()
} 
