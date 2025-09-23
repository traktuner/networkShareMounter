//
//  GeneralSettingsView.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 10.04.25.
//  Copyright © 2024 RRZE. All rights reserved.
//

import SwiftUI
import AppKit
import Sparkle // Keep import for SPUUpdaterController access via AppDelegate
import LaunchAtLogin // Import for Start at Login toggle
import OSLog
import Sentry
import Compression
import zlib

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

    /// Hidden debug feature: enables log export functionality for current session only
    @State private var debugLogExportEnabled: Bool = false

    /// Counter for taps on "Diagnosedaten" header to enable hidden debug feature
    @State private var diagnoseTapCount: Int = 0

    /// State for log export operation
    @State private var isExportingLogs: Bool = false
    @State private var exportResult: String? = nil
    
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
                        .onTapGesture {
                            diagnoseTapCount += 1
                            if diagnoseTapCount >= 5 {
                                debugLogExportEnabled = true
                            }
                        }
                    Toggle("Anonyme Diagnosedaten senden", isOn: $sendDiagnosticData) // Updated to German

                    // Hidden debug feature: only shown after 5 taps on "Diagnosedaten"
                    if debugLogExportEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            Button {
                                Task {
                                    await exportDebugLogs()
                                }
                            } label: {
                                HStack {
                                    if isExportingLogs {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text("Logs werden gesendet...")
                                    } else {
                                        Image(systemName: "doc.text.fill")
                                        Text("Debug-Logs an Support senden")
                                    }
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(isExportingLogs)

                            // Show result message
                            if let result = exportResult {
                                Text(result)
                                    .font(.caption)
                                    .foregroundColor(result.contains("erfolgreich") ? .green : .red)
                                    .onAppear {
                                        // Clear message after 5 seconds
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                                            exportResult = nil
                                        }
                                    }
                            }
                        }
                        .padding(.top, 8)
                    }
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

            // Reconfigure Sentry based on the new preference
            SentryManager.shared.configureSentry()
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

    // MARK: - Debug Log Export Function

    /// Exports debug logs and sends them as Sentry attachment
    @MainActor
    private func exportDebugLogs() async {
        isExportingLogs = true
        exportResult = nil

        do {
            Logger.app.info("🔄 Starting debug log export...")

            // Check if Sentry is active
            guard SentryManager.shared.isActive else {
                Logger.app.warning("⚠️ Sentry not active - cannot send logs. Enable 'Anonyme Diagnosedaten senden' first.")
                exportResult = "Fehler: Diagnosedaten-Übertragung ist deaktiviert"
                isExportingLogs = false
                return
            }

            Logger.app.info("✓ Sentry is active")

            // Get logs from last 30 minutes - run in background
            let thirtyMinutesAgo = Date().addingTimeInterval(-30 * 60)
            Logger.app.info("📋 Collecting logs since: \(thirtyMinutesAgo)")

            let logs = try await Task.detached {
                try await self.collectLogs(since: thirtyMinutesAgo)
            }.value

            Logger.app.info("📋 Collected \(logs.count) bytes of raw log data")

            let compressedLogs = try await Task.detached {
                try self.compressLogs(logs)
            }.value

            Logger.app.info("🗜️ Compressed to \(compressedLogs.count) bytes")

            let filename = "debug-logs-\(DateFormatter.yyyyMMddHHmmss.string(from: Date())).txt.gz"

            // Send as Sentry attachment - run in background
            await Task.detached {
                SentrySDK.configureScope { scope in
                    let attachment = Attachment(
                        data: compressedLogs,
                        filename: filename
                    )
                    scope.addAttachment(attachment)
                    Logger.app.info("📎 Attachment added to scope: \(filename)")
                }

                // Send event with context
                Logger.app.info("📤 Sending event to Sentry...")
                SentrySDK.capture(message: "Debug logs exported by user") { scope in
                    scope.setTag(value: "manual", key: "log_export")
                    scope.setExtra(value: 30, key: "log_duration_minutes")
                    scope.setExtra(value: filename, key: "attachment_filename")
                }

                // Force flush to ensure data is sent
                SentrySDK.flush(timeout: 10.0)
                Logger.app.info("🚀 Sentry flush completed")
            }.value

            Logger.app.info("✅ Debug logs exported successfully - check Sentry dashboard")
            exportResult = "Logs erfolgreich gesendet!"

        } catch {
            Logger.app.error("❌ Failed to export debug logs: \(error.localizedDescription)")
            exportResult = "Fehler beim Senden der Logs: \(error.localizedDescription)"
        }

        isExportingLogs = false
    }

    /// Collects logs from OSLogStore since specified date
    private func collectLogs(since date: Date) async throws -> Data {
        let logStore = try OSLogStore(scope: .currentProcessIdentifier)
        let position = logStore.position(date: date)
        let entries = try logStore.getEntries(at: position)

        var logLines: [String] = []

        for entry in entries {
            if let logEntry = entry as? OSLogEntryLog {
                let timestamp = DateFormatter.logFormat.string(from: logEntry.date)
                let level = logLevelString(from: logEntry.level)
                let line = "\(timestamp) [\(level)] \(logEntry.category): \(logEntry.composedMessage)"
                logLines.append(line)
            }
        }

        let logText = logLines.joined(separator: "\n")
        return logText.data(using: .utf8) ?? Data()
    }

    /// Converts OSLogEntryLog.Level to readable string
    private func logLevelString(from level: OSLogEntryLog.Level) -> String {
        switch level {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .notice: return "NOTICE"
        case .error: return "ERROR"
        case .fault: return "FAULT"
        default: return "UNKNOWN"
        }
    }

    /// Compresses log data using gzip
    private func compressLogs(_ data: Data) throws -> Data {
        return try data.gzipped()
    }
}

// MARK: - Extensions

extension DateFormatter {
    static let yyyyMMddHHmmss: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

    static let logFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()
}

extension Data {
    /// Compresses data using gzip compression (zlib) safely in chunks
    /// - Returns: GZIP-compressed data
    func gzipped() throws -> Data {
        guard !isEmpty else { return Data() }

        var stream = z_stream()
        var status: Int32

        // Initialize deflate with gzip header/trailer (windowBits = 15 + 16)
        status = deflateInit2_(
            &stream,
            Z_DEFAULT_COMPRESSION,
            Z_DEFLATED,
            15 + 16,
            8,
            Z_DEFAULT_STRATEGY,
            ZLIB_VERSION,
            Int32(MemoryLayout<z_stream>.size)
        )
        guard status == Z_OK else {
            throw NSError(domain: "GZipError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to initialize compression (status \(status))"])
        }

        defer { deflateEnd(&stream) }

        var output = Data()
        let chunkSize = 16 * 1024

        try self.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) in
            guard let baseAddress = rawBuffer.bindMemory(to: Bytef.self).baseAddress else { return }

            // Set input
            stream.next_in = UnsafeMutablePointer<Bytef>(mutating: baseAddress)
            stream.avail_in = uInt(self.count)

            // Compress in chunks until stream ends
            var localStatus: Int32 = Z_OK
            while localStatus == Z_OK {
                var outBuffer = [UInt8](repeating: 0, count: chunkSize)
                outBuffer.withUnsafeMutableBytes { outPtr in
                    stream.next_out = outPtr.bindMemory(to: Bytef.self).baseAddress
                    stream.avail_out = uInt(chunkSize)

                    // If no more input left, finish the stream
                    let flush = (stream.avail_in == 0) ? Z_FINISH : Z_NO_FLUSH
                    localStatus = deflate(&stream, flush)

                    let have = chunkSize - Int(stream.avail_out)
                    if have > 0 {
                        if let outBase = outPtr.baseAddress {
                            output.append(outBase.assumingMemoryBound(to: UInt8.self), count: have)
                        }
                    }
                }

                // If buffer filled but stream not finished, loop continues
                if localStatus == Z_BUF_ERROR && stream.avail_out == 0 {
                    localStatus = Z_OK // continue to write more output
                }
            }

            status = localStatus
        }

        guard status == Z_STREAM_END else {
            throw NSError(domain: "GZipError", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to compress data (status \(status))"])
        }

        return output
    }
}

#Preview {
    // Preview doesn't need the actual updater logic, just the view structure
    GeneralSettingsView()
}
