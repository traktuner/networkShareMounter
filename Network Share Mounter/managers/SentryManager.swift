//
//  SentryManager.swift
//  Network Share Mounter
//
//  Created by AI Assistant on 16.09.25.
//  Copyright © 2024 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation
import Sentry
import OSLog

/// Centralized manager for Sentry crash reporting and diagnostics
///
/// This class provides a single point of control for Sentry SDK configuration,
/// respecting user preferences for diagnostic data collection. It ensures
/// consistent behavior between app startup and runtime preference changes.
class SentryManager {

    /// Shared singleton instance
    static let shared = SentryManager()

    /// Private initializer to enforce singleton pattern
    private init() {}

    /// Preference manager for accessing user settings
    private let prefs = PreferenceManager()

    /// Tracks whether Sentry is currently active
    private var isSentryActive = false

    /// Configures Sentry based on current user preferences and build configuration
    ///
    /// This method should be called:
    /// - During app initialization (AppDelegate)
    /// - When user changes diagnostic preferences (GeneralSettingsView)
    ///
    /// The method respects both debug builds and user preferences:
    /// - Debug builds: Sentry is always disabled
    /// - Release builds: Sentry state follows `.sendDiagnostics` preference
    func configureSentry() {
        #if DEBUG
        Logger.app.debug("🐛 Debug build - Sentry diagnostics disabled")
        if isSentryActive {
            stopSentry()
        }
        #else
        let shouldEnableSentry = prefs.bool(for: .sendDiagnostics)

        if shouldEnableSentry && !isSentryActive {
            startSentry()
        } else if !shouldEnableSentry && isSentryActive {
            stopSentry()
        } else if shouldEnableSentry && isSentryActive {
            Logger.app.debug("📊 Sentry already active - no changes needed")
        } else {
            Logger.app.debug("📊 Sentry already inactive - no changes needed")
        }
        #endif
    }

    /// Initializes and starts the Sentry SDK
    private func startSentry() {
        Logger.app.debug("📊 Starting Sentry SDK for diagnostic data collection...")

        SentrySDK.start { options in
            options.dsn = Defaults.sentryDSN
            options.debug = false
            options.tracesSampleRate = 0.1

            // Set additional options for better privacy and performance
            options.enableAutoSessionTracking = true
            options.sessionTrackingIntervalMillis = 30000
            options.attachStacktrace = true
            options.maxBreadcrumbs = 100

            // Privacy: Don't capture personally identifiable information
            options.beforeSend = { event in
                // Remove any potentially sensitive data
                event.user = nil
                return event
            }
        }

        isSentryActive = true
        Logger.app.info("✅ Sentry SDK initialized successfully")
    }

    /// Stops the Sentry SDK and cleans up resources
    private func stopSentry() {
        Logger.app.debug("📊 Stopping Sentry SDK - diagnostic data collection disabled")

        SentrySDK.close()
        isSentryActive = false

        Logger.app.info("✅ Sentry SDK stopped successfully")
    }

    /// Returns current Sentry activation state
    /// - Returns: True if Sentry is currently active, false otherwise
    var isActive: Bool {
        return isSentryActive
    }
}