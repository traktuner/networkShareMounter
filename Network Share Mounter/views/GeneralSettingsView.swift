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
import ServiceManagement
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
/// uses the native `SMAppService` API to manage the login item status, and interacts
/// with the `AppDelegate` to trigger Sparkle update checks.
/// MDM settings like disabling the update framework or preventing changes to the login item
/// are respected.
struct GeneralSettingsView: View {
    // Use PreferenceManager to interact with UserDefaults
    private var prefs = PreferenceManager()

    /// Controls whether the application starts automatically when the user logs in.
    /// Initialized directly in `init()` to ensure the correct value is shown on first render,
    /// avoiding the visual glitch of onAppear-based state updates.
    @State private var startAtLogin: Bool

    init() {
        let prefs = PreferenceManager()
        let canChange = prefs.bool(for: .canChangeAutostart)
        if !canChange {
            _startAtLogin = State(initialValue: prefs.bool(for: .autostart))
        } else {
            _startAtLogin = State(initialValue: SMAppService.mainApp.status == .enabled)
        }
    }
    
    /// Controls whether anonymous diagnostic data should be sent.
    /// Initialized from `prefs.bool(for: .sendDiagnostics)` in `.onAppear`.
    /// Changes are saved back to `prefs` in `.onChange`.
    @State private var sendDiagnosticData: Bool = false

    /// Mirrors Sparkle's own SUEnableAutomaticChecks key so the user can change their
    /// mind after the first-run dialog. Sparkle reads the same key from UserDefaults.
    @AppStorage("SUEnableAutomaticChecks") private var automaticallyChecksForUpdates: Bool = true

    /// Hidden debug feature: enables log export functionality for current session only
    @State private var debugLogExportEnabled: Bool = false

    /// Counter for taps on "Diagnosedaten" header to enable hidden debug feature
    @State private var diagnoseTapCount: Int = 0

    /// State for log collection and export
    @State private var isExportingLogs: Bool = false
    @State private var exportResult: String? = nil
    @State private var collectedLogs: String? = nil
    @State private var collectedLogData: Data? = nil
    @State private var collectedLogFilename: String = ""
    @State private var showingLogViewer: Bool = false
    
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
                        Text("General")
                            .font(.headline)
                            .fontWeight(.medium)
                        Text("Adjust general application settings here.")
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
                    Text("Startup")
                        .font(.headline)
                    Toggle("Start at login", isOn: $startAtLogin)
                        .disabled(!prefs.bool(for: .canChangeAutostart))
                }
                .padding(.top, 8)
                .padding(.bottom, 8)
                
                // MARK: - Diagnostic Data Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Diagnostics")
                        .font(.headline)
                        .onTapGesture {
                            diagnoseTapCount += 1
                            if diagnoseTapCount >= 5 {
                                debugLogExportEnabled = true
                            }
                        }
                    Toggle("Send anonymous diagnostic data", isOn: $sendDiagnosticData)

                    // Hidden debug feature: only shown after 5 taps on "Diagnostics" heading
                    if debugLogExportEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            if collectedLogs != nil {
                                // Phase 2: logs ready — offer view and send
                                HStack(spacing: 12) {
                                    Button {
                                        showingLogViewer = true
                                    } label: {
                                        Label("Show logs", systemImage: "doc.text.magnifyingglass")
                                    }
                                    .buttonStyle(.bordered)

                                    Button {
                                        Task { await sendCollectedLogs() }
                                    } label: {
                                        HStack {
                                            if isExportingLogs {
                                                ProgressView().scaleEffect(0.8)
                                                Text("Sending...")
                                            } else {
                                                Label("Send to support", systemImage: "paperplane.fill")
                                            }
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(isExportingLogs || !SentryManager.shared.isActive)

                                    Button {
                                        collectedLogs = nil
                                        collectedLogData = nil
                                        exportResult = nil
                                    } label: {
                                        Text("Collect again")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundColor(.secondary)
                                }
                            } else {
                                // Phase 1: initial state — collect first
                                Button {
                                    Task { await collectAndPrepareLogs() }
                                } label: {
                                    HStack {
                                        if isExportingLogs {
                                            ProgressView().scaleEffect(0.8)
                                            Text("Collecting logs...")
                                        } else {
                                            Label("Collect debug logs", systemImage: "doc.text.fill")
                                        }
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(isExportingLogs)
                            }

                            if let result = exportResult {
                                Text(result)
                                    .font(.caption)
                                    .foregroundColor(
                                        result.localizedCaseInsensitiveContains("success") ||
                                        result.localizedCaseInsensitiveContains("erfolgreich")
                                        ? .green : .red
                                    )
                            }
                        }
                        .padding(.top, 8)
                        .sheet(isPresented: $showingLogViewer) {
                            if let logs = collectedLogs {
                                LogViewerView(logs: logs, filename: collectedLogFilename)
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
                
                // MARK: - Update Section
                if !isUpdateFrameworkDisabled {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Software Update")
                            .font(.headline)

                        Toggle("Automatically check for updates", isOn: $automaticallyChecksForUpdates)
                            .padding(.leading, 20)

                        Button {
                            if let appDelegate = NSApp.delegate as? AppDelegate,
                               let updaterController = appDelegate.updaterController {
                                updaterController.checkForUpdates(nil)
                            }
                        } label: {
                            HStack {
                                Image(systemName: "arrow.clockwise")
                                Text("Check for updates now")
                            }
                        }
                        .padding(.leading, 20)
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 8)
                }
                
                // MARK: - Version Info Section
                VStack(alignment: .leading, spacing: 14) {
                    Text("About")
                        .font(.headline)
                    
                    HStack {
                        Text("Version")
                        Spacer()
                        // Display dynamic version and build number
                        Text(appVersion + " (" + buildNumber + ")")
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 8)

                HStack {
                    Spacer()
                    Text(LocalizedStringResource("Developed with ❤️ by FAUmac @ RRZE/FAU"))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Apply consistent 20pt padding to the entire view, matching other views
        .padding(20)
        .onAppear {
            let canChange = prefs.bool(for: .canChangeAutostart)
            let mdmAutostart = prefs.bool(for: .autostart)
            let systemStatus = SMAppService.mainApp.status
            Logger.app.info("⚙️ [GeneralSettingsView] onAppear – canChangeAutostart=\(canChange, privacy: .public), mdmAutostart=\(mdmAutostart, privacy: .public), systemStatus=\(String(describing: systemStatus), privacy: .public), startAtLogin=\(startAtLogin, privacy: .public)")

            sendDiagnosticData = prefs.bool(for: .sendDiagnostics)
        }
        // MARK: - State Change Handlers
        .onChange(of: startAtLogin) { newValue in
            guard prefs.bool(for: .canChangeAutostart) else {
                // MDM controls autostart - ignore all onChange triggers (from onAppear or disabled toggle)
                return
            }

            let service = SMAppService.mainApp
            do {
                if newValue {
                    try service.register()
                    Logger.app.debug("✅ Autostart enabled")
                } else {
                    try service.unregister()
                    Logger.app.debug("✅ Autostart disabled")
                }
            } catch {
                Logger.app.error("❌ Failed to \(newValue ? "enable" : "disable") launch at login: \(error.localizedDescription)")
                // Revert to actual system state on error
                Task { @MainActor in
                    startAtLogin = (service.status == .enabled)
                }
            }
        }
        .onChange(of: sendDiagnosticData) { newValue in
            // Persist the diagnostic data preference.
            prefs.set(for: .sendDiagnostics, value: newValue)

            // Reconfigure Sentry based on the new preference
            SentryManager.shared.configureSentry()
        }
    }

    // MARK: - Debug Log Functions

    /// Collects logs from the last 30 minutes and stores them for display or sending.
    @MainActor
    private func collectAndPrepareLogs() async {
        isExportingLogs = true
        exportResult = nil

        do {
            Logger.app.info("🔄 Collecting debug logs...")
            let since = Date().addingTimeInterval(-30 * 60)

            let raw = try await Task.detached {
                try await self.collectLogs(since: since)
            }.value

            let compressed = try await Task.detached {
                try self.compressLogs(raw)
            }.value

            let filename = "debug-logs-\(DateFormatter.yyyyMMddHHmmss.string(from: Date())).txt.gz"
            collectedLogs = String(data: raw, encoding: .utf8) ?? ""
            collectedLogData = compressed
            collectedLogFilename = filename
            Logger.app.info("✅ Logs collected: \(raw.count) bytes raw, \(compressed.count) bytes compressed")
        } catch {
            Logger.app.error("❌ Failed to collect logs: \(error.localizedDescription)")
            exportResult = String(
                format: NSLocalizedString("Failed to collect logs: %@", comment: "Log collection failure; %@ is the error description"),
                error.localizedDescription
            )
        }

        isExportingLogs = false
    }

    /// Sends the previously collected logs to Sentry as an attachment.
    @MainActor
    private func sendCollectedLogs() async {
        guard let data = collectedLogData, !collectedLogFilename.isEmpty else { return }
        guard SentryManager.shared.isActive else { return }

        isExportingLogs = true
        let filename = collectedLogFilename
        let hasFDA = FullDiskAccessChecker.hasAccess()

        await Task.detached {
            SentrySDK.configureScope { scope in
                scope.addAttachment(Attachment(data: data, filename: filename))
                Logger.app.info("📎 Attachment added to scope: \(filename, privacy: .public)")
            }
            Logger.app.info("📤 Sending event to Sentry...")
            SentrySDK.capture(message: "Debug logs exported by user") { scope in
                scope.setTag(value: "manual", key: "log_export")
                scope.setExtra(value: 30, key: "log_duration_minutes")
                scope.setExtra(value: filename, key: "attachment_filename")
                scope.setExtra(value: hasFDA, key: "full_disk_access")
            }
            SentrySDK.flush(timeout: 10.0)
            Logger.app.info("🚀 Sentry flush completed")
        }.value

        exportResult = NSLocalizedString("Logs sent successfully!", comment: "Log send success confirmation")
        Logger.app.info("✅ Debug logs sent to Sentry")
        isExportingLogs = false
    }

    /// Collects logs from OSLogStore since specified date.
    ///
    /// Tries the `.system` scope first (requires Full Disk Access) so that SMB client,
    /// NetAuthSysAgent, and NetAuthAgent entries are included alongside the app's own logs.
    /// Falls back silently to `.currentProcessIdentifier` when FDA is not available.
    private func collectLogs(since date: Date) async throws -> Data {
        // Predicate targets our app plus the OS subsystems relevant for mount/auth diagnosis.
        // TCC is intentionally omitted — it is extremely verbose and rarely needed.
        let predicate = NSPredicate(
            format: "subsystem == %@ OR subsystem == %@ OR process == %@ OR process == %@",
            "de.fau.rrze.NetworkShareMounter",
            "com.apple.smb.client",
            "NetAuthSysAgent",
            "NetAuthAgent"
        )

        let (logStore, scopeLabel): (OSLogStore, String)
        do {
            logStore = try OSLogStore(scope: .system)
            scopeLabel = "system"
        } catch {
            Logger.app.warning("⚠️ System log scope unavailable (FDA required): \(error.localizedDescription, privacy: .public)")
            logStore = try OSLogStore(scope: .currentProcessIdentifier)
            scopeLabel = "process"
        }

        Logger.app.info("📋 Collecting logs with scope: \(scopeLabel, privacy: .public)")

        let position = logStore.position(date: date)
        let entries = try logStore.getEntries(at: position, matching: predicate)

        var logLines: [String] = ["=== Log scope: \(scopeLabel) ==="]

        for entry in entries {
            if let logEntry = entry as? OSLogEntryLog {
                let timestamp = DateFormatter.logFormat.string(from: logEntry.date)
                let level = logLevelString(from: logEntry.level)
                let line = "\(timestamp) [\(level)] [\(logEntry.subsystem)/\(logEntry.category)] \(logEntry.composedMessage)"
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
    nonisolated private func compressLogs(_ data: Data) throws -> Data {
        return try data.gzipped()
    }
}

// MARK: - Log Viewer

private struct LogViewerView: View {
    let logs: String
    let filename: String
    @Environment(\.dismiss) private var dismiss
    @State private var lines: [String] = []
    @State private var isLoading = true

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(filename)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(logs, forType: .string)
                } label: {
                    Label("Copy", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)
                .disabled(isLoading)
                Button("Close") { dismiss() }
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            Divider()
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal)
                                .padding(.vertical, 1)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .task {
            let text = logs
            let split = await Task.detached {
                text.components(separatedBy: "\n")
            }.value
            lines = split
            isLoading = false
        }
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
