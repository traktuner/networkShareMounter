//
//  ActivityController.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 08.11.23.
//  Copyright © 2024 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation
import AppKit
import OSLog

/// Monitors system events and responds with appropriate actions for network shares
///
/// The ActivityController registers for system events such as sleep,
/// logout, wake up, and login. Based on these events, network shares
/// are either mounted or unmounted as appropriate.
class ActivityController {
    
    // MARK: - Properties

    /// Access to user preferences
    private let prefs = PreferenceManager()

    /// Reference to AppDelegate for accessing important app components
    private weak var appDelegate: AppDelegate?

    /// Flag to prevent double authentication triggers during app startup
    private var isInStartupPhase = true

    /// Task for debouncing network change operations
    private var networkChangeTask: Task<Void, Never>?

    /// Thread-safe tracker for authentication retry attempts
    private let retryTracker = AuthRetryTracker()

    /// Flag to prevent parallel mount operations
    private var isMountOperationInProgress = false

    // MARK: - Initialization
    
    /// Initializes the controller and starts monitoring system events
    ///
    /// - Parameter appDelegate: Reference to the AppDelegate instance
    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate

        UserDefaults.standard.set(Date(), forKey: "lastActivityTimestamp")

        startMonitoring()

        // Reset startup flag after a short delay to allow normal timer operations
        Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
            isInStartupPhase = false
            Logger.activityController.debug("✅ Startup phase completed - timer-based auth triggers now enabled")
        }
    }
    
    // MARK: - Observer Management
    
    /// Registers the controller for all relevant system notifications
    ///
    /// This method registers observers for the following categories:
    /// - System events (sleep, wake, shutdown)
    /// - Session events (active, inactive)
    /// - Timer events for regular actions
    /// - Custom app events (mount, unmount)
    /// - Network changes
    func startMonitoring() {
        // Remove existing observers to avoid duplicate registrations
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default.removeObserver(self)
        
        Logger.activityController.debug("Starting monitoring of system events")
        
        // System event observers
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(unmountShares),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(unmountShares),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(unmountShares),
            name: NSWorkspace.willPowerOffNotification,
            object: nil
        )
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(wakeupFromSleep),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(mountShares),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
        
        // App-specific observers
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(processAutomaticSignIn),
            name: Defaults.nsmAuthTriggerNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(timeGoesBySoSlowly),
            name: Defaults.nsmTimeTriggerNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(mountShares),
            name: Defaults.nsmMountTriggerNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(unmountShares),
            name: Defaults.nsmUnmountTriggerNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(mountSharesWithUserTrigger),
            name: Defaults.nsmMountManuallyTriggerNotification,
            object: nil
        )
        
        // CHANGED: Network change now uses a dedicated sequence (revalidate → prepare → mount)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(mountAfterNetworkChange),
            name: Defaults.nsmNetworkChangeTriggerNotification,
            object: nil
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(reconstructMenuTrigger),
            name: Defaults.nsmReconstructMenuTriggerNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            forName: Defaults.nsmKerberosAuthRetryNeeded,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            guard let shareID = notification.userInfo?["shareID"] as? String else {
                Logger.activityController.error("Kerberos retry notification missing shareID")
                return
            }

            Task {
                let currentRetries = await self.retryTracker.incrementAndGet(for: shareID)

                if currentRetries < 1 {
                    Logger.activityController.info("🔄 Kerberos auth retry triggered for share \(shareID, privacy: .public) (attempt \(currentRetries + 1, privacy: .public)/1)")
                    self.performSoftRestart(reason: "kerberos authentication retry")
                } else {
                    Logger.activityController.warning("⚠️ Kerberos retry limit reached for share \(shareID, privacy: .public) - giving up")
                }
            }
        }

        NotificationCenter.default.addObserver(
            forName: Notification.Name("nsmKerberosMountSuccess"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            guard let shareID = notification.userInfo?["shareID"] as? String else { return }

            Task {
                await self.retryTracker.reset(for: shareID)
                Logger.activityController.debug("✅ Reset retry counter for successfully mounted share \(shareID, privacy: .public)")
            }
        }

        // Kerberos cache changes
        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(processAutomaticSignIn),
            name: "CCAPICCacheChangedNotification" as CFString as NSNotification.Name,
            object: nil
        )
        
        // NEW: Observe distributed notifications from the App Intents Extension
        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(unmountShares),
            name: .nsmDistributedUnmountTrigger,
            object: nil
        )
        
        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(mountSharesWithUserTrigger),
            name: .nsmDistributedMountTrigger,
            object: nil
        )
        
        DistributedNotificationCenter.default.addObserver(
            self,
            selector: #selector(renewKerberosTicket),
            name: .nsmDistributedRenewKerberosTrigger,
            object: nil
        )
        
        Logger.activityController.debug("All observers successfully registered")
    }
    
    // MARK: - System Event Handlers
    
    /// Unmounts all network shares
    ///
    /// Called when:
    /// - System enters sleep mode
    /// - Session becomes inactive
    /// - System shuts down
    /// - User manually triggers unmount
    @objc func unmountShares() {
        guard let mounter = appDelegate?.mounter else {
            Logger.activityController.error("Unmount failed: Mounter not available")
            return
        }
        
        let notificationName = (Thread.callStackSymbols.first ?? "Unknown")
            .components(separatedBy: " ")
            .last ?? "Unknown"
        
        Logger.activityController.debug("▶︎ unmountAllShares called by \(notificationName, privacy: .public)")
        
        let unmountTask = Task { @MainActor in
            Logger.activityController.debug("🔄 Unmount task started - Executing unmount operation")
            await mounter.unmountAllMountedShares()
            Logger.activityController.debug("✅ Unmount task completed - All shares successfully unmounted.")
        }
        
        _ = unmountTask
    }
    
    /// Handles system wake up from sleep
    ///
    /// Mounts all configured shares and restarts Finder
    /// to work around known macOS issues
    @objc func wakeupFromSleep() {
        Logger.activityController.debug("▶︎ System wake notification received")
        performSoftRestart(reason: "wake from sleep")
    }
    
    /// Mounts configured network shares
    ///
    /// Called when:
    /// - Session becomes active
    /// - App mount requests
    @objc func mountShares() {
        guard let mounter = appDelegate?.mounter else {
            Logger.activityController.error("Mount failed: Mounter not available")
            return
        }
        
        let notificationName = (Thread.callStackSymbols.first ?? "Unknown")
            .components(separatedBy: " ")
            .last ?? "Unknown"
        
        Logger.activityController.debug("▶︎ mountGivenShares called by \(notificationName, privacy: .public)")
        
        let mountTask = Task { @MainActor in
            // Update SMBHome from AD/OpenDirectory on network/domain changes
            await mounter.shareManager.updateSMBHome()
            Logger.activityController.debug("🔄 Mounting shares - Starting operation on main actor")
            await mounter.mountGivenShares()
            Logger.activityController.debug("✅ All shares successfully mounted - Operation completed")
        }
        
        _ = mountTask
    }
    
    // MARK: - Network change sequence
    
    /// Handles network change (Up) with robust sequence:
    /// 1) Revalidate currently mounted shares, unmount unreachable ones
    /// 2) Prepare mount prerequisites
    /// 3) Mount shares
    ///
    /// Uses debouncing to prevent multiple simultaneous network change operations
    @objc func mountAfterNetworkChange() {
        guard let mounter = appDelegate?.mounter else {
            Logger.activityController.error("Network-change handling failed: Mounter not available")
            return
        }

        // Cancel any existing network change task to prevent parallel operations
        networkChangeTask?.cancel()

        Logger.activityController.debug("▶︎ Network change detected: revalidating mounted shares, then mounting")

        networkChangeTask = Task { @MainActor in
            // Guard against parallel mount operations
            guard !isMountOperationInProgress else {
                Logger.activityController.info("⏭️ Mount operation already running, skipping network-triggered mount")
                return
            }

            isMountOperationInProgress = true
            defer { isMountOperationInProgress = false }

            // Small delay to debounce rapid network change events
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

            // Check if task was cancelled during delay
            guard !Task.isCancelled else {
                Logger.activityController.debug("🚫 Network change task was cancelled during debounce period")
                return
            }

            Logger.activityController.debug("🔄 Starting network change operations after debounce")

            // Update SMBHome from AD/OpenDirectory on network/domain changes
            await mounter.shareManager.updateSMBHome()

            guard !Task.isCancelled else { return }

            await mounter.revalidateMountedSharesAfterNetworkChange()
            Logger.activityController.debug("🔄 Revalidation completed, preparing mount prerequisites")

            guard !Task.isCancelled else {
                Logger.activityController.debug("🚫 Task cancelled after revalidation")
                return
            }

            await mounter.prepareMountPrerequisites()
            Logger.activityController.debug("🔄 Mount prerequisites completed, starting mount operations")

            guard !Task.isCancelled else {
                Logger.activityController.debug("🚫 Task cancelled after preparation")
                return
            }

            await mounter.mountGivenShares(networkTriggered: true)
            Logger.activityController.debug("🔄 Mount operations completed, refreshing Finder")

            guard !Task.isCancelled else {
                Logger.activityController.debug("🚫 Task cancelled after mounting")
                return
            }

            // Optional: gentle Finder refresh after mounts
            let finderController = FinderController()
            let mountPaths = await finderController.getActualMountPaths(from: mounter)
            await finderController.refreshFinder(forPaths: mountPaths)

            Logger.activityController.debug("✅ Network change operations completed")
        }
    }
    
    // MARK: - Authentication Handlers
    
    /// Starts the automatic sign-in process for Kerberos
    ///
    /// Only executes when Kerberos authentication is configured.
    ///
    /// - Parameter notification: Optional notification containing userInfo with forceAuth flag
    @objc func processAutomaticSignIn(_ notification: Notification? = nil) {
        // Check if a Kerberos realm is configured
        guard let krbRealm = self.prefs.string(for: .kerberosRealm), !krbRealm.isEmpty else {
            Logger.activityController.debug("No Kerberos realm configured, skipping AutomaticSignIn")
            return
        }

        // Extract forceAuth flag from notification userInfo
        let forceAuth = notification?.userInfo?["forceAuth"] as? Bool ?? false

        // Prevent too frequent authentication attempts (but allow forced auth to bypass this)
        if !forceAuth {
            let lastAuthAttempt = UserDefaults.standard.object(forKey: "lastKrbAuthAttempt") as? Date ?? Date.distantPast
            let timeSinceLastAttempt = Date().timeIntervalSince(lastAuthAttempt)

            // wait at least 30 seconds between authentication attempts
            guard timeSinceLastAttempt > 30 else {
                Logger.activityController.debug("Skipping auth attempt - too soon since last attempt (\(timeSinceLastAttempt, privacy: .public)s)")
                return
            }
        }

        UserDefaults.standard.set(Date(), forKey: "lastKrbAuthAttempt")

        Task { @MainActor in
            Logger.activityController.debug("▶︎ Kerberos realm configured, processing AutomaticSignIn (forceAuth: \(forceAuth, privacy: .public))")

            do {
                Logger.activityController.debug("🔄 Starting automatic sign-in task")
                await appDelegate?.automaticSignIn.signInAllAccounts(forceAuth: forceAuth)
                Logger.activityController.info("✅ Automatic sign-in completed successfully")
            } catch {
                Logger.activityController.error("❌ Automatic sign-in failed with error: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Mounts shares after user request
    ///
    /// First performs Kerberos authentication, then mounts the shares
    @objc func mountSharesWithUserTrigger() {
        processAutomaticSignIn()

        guard let mounter = appDelegate?.mounter else {
            Logger.activityController.error("User request for mounting failed: Mounter not available")
            return
        }

        Logger.activityController.debug("▶︎ mountGivenShares with user-trigger called")

        let userMountTask = Task { @MainActor in
            await retryTracker.resetAll()
            Logger.activityController.debug("🔄 Reset auth retry counters for manual mount")

            Logger.activityController.debug("🔄 Manual mount operation - Starting mount process")
            
            // Update SMBHome from AD/OpenDirectory on network/domain changes
            await mounter.shareManager.updateSMBHome()
            
            await mounter.mountGivenShares(userTriggered: true)
            Logger.activityController.debug("✅ Shares successfully mounted after user request - Operation completed")
        }
        
        _ = userMountTask
    }
    
    /// Renews Kerberos tickets via soft reset
    ///
    /// Triggered by the RenewKerberosTicketIntent from Shortcuts/Siri.
    /// Performs the same soft restart as after system wake.
    @objc func renewKerberosTicket() {
        Logger.activityController.info("🎫 Kerberos ticket renewal requested via App Intent")
        performSoftRestart(reason: "Kerberos ticket renewal via Shortcuts")
    }
    
    /// Updates the app menu
    ///
    /// Rebuilds the app menu based on current status
    @objc func reconstructMenuTrigger() {
        guard let mounter = appDelegate?.mounter else {
            Logger.activityController.error("Menu update failed: Mounter not available")
            return
        }
        
        Logger.activityController.debug("▶︎ Menu reconstruction called")
        
        let menuTask = Task { @MainActor in
            Logger.activityController.debug("🔄 Starting menu reconstruction")
            await appDelegate?.constructMenu(withMounter: mounter)
            Logger.activityController.debug("✅ Menu successfully updated")
        }
        
        _ = menuTask
    }
    
    /// Performs periodic tasks
    ///
    /// This method is called by a timer and checks:
    /// - Changes in MDM profile
    /// - Status of mounted shares
    /// 
    /// Time goes by so slowly
    /// Time goes by so slowly
    /// Time goes by so slowly for those who wait
    /// No time to hesitate
    /// Those who run seem to have all the fun
    /// I'm caught up, I don't know what to do
    @objc func timeGoesBySoSlowly() {
        let lastActivity = UserDefaults.standard.object(forKey: "lastActivityTimestamp") as? Date ?? Date()
        let timeSinceLastActivity = Date().timeIntervalSince(lastActivity)
        let threshold = Defaults.mountTriggerTimer * 2

        if timeSinceLastActivity > threshold {
            Logger.activityController.warning("⚠️ Detected long inactivity (\(timeSinceLastActivity, privacy: .public)s > \(threshold, privacy: .public)s) - performing soft restart")
            UserDefaults.standard.set(Date(), forKey: "lastActivityTimestamp")
            performSoftRestart(reason: "long inactivity detected")
            return
        }

        UserDefaults.standard.set(Date(), forKey: "lastActivityTimestamp")

        // Daily heartbeat logging
        if shouldLogDailyHeartbeat() {
            appDelegate?.logAppVersion(context: "❤️ Daily heartbeat")
            UserDefaults.standard.set(Date(), forKey: "lastHeartbeatLogDate")
        }

        if !isInStartupPhase {
            NotificationCenter.default.post(name: Defaults.nsmAuthTriggerNotification, object: nil)
        } else {
            Logger.activityController.debug("⏰ Skipping auth trigger during startup phase to prevent double authentication")
        }

        guard let mounter = appDelegate?.mounter else {
            Logger.activityController.error("Timer processing failed: Mounter not available")
            return
        }

        Logger.activityController.debug("⏰ Time goes by so slowly: Timer notification received")
        Logger.activityController.debug("▶︎ ...checking for possible MDM profile changes")

        let timerTask = Task { @MainActor in
            Logger.activityController.debug("🔄 Timer-triggered mount operation - Updating share array")
            await mounter.shareManager.updateShareArray()
            Logger.activityController.debug("🔄 Timer-triggered mount operation - checking for SMBhome shares")
            await mounter.shareManager.updateSMBHome()
            Logger.activityController.debug("▶︎ ...calling mountGivenShares")
            await mounter.mountGivenShares()
            Logger.activityController.debug("✅ Timer processing completed successfully")
        }

        _ = timerTask
    }

    // MARK: - Soft Restart

    /// Performs a soft restart of the app after sleep or long inactivity
    ///
    /// This resets authentication state and remounts shares without full app reinitialization.
    /// Handles both Kerberos and password-authenticated shares appropriately.
    ///
    /// - Parameter reason: Description of why the soft restart was triggered (for logging)
    private func performSoftRestart(reason: String) {
        guard let mounter = appDelegate?.mounter else {
            Logger.activityController.error("Soft restart failed: Mounter not available")
            return
        }

        Logger.activityController.info("🔄 Performing soft restart: \(reason, privacy: .public)")
        appDelegate?.logAppVersion(context: "🔄 Soft restart (\(reason))")

        UserDefaults.standard.removeObject(forKey: "lastKrbAuthAttempt")
        Logger.activityController.debug("🔄 Reset authentication rate limiter")

        let restartTask = Task { @MainActor in
            if !reason.contains("retry") {
                await retryTracker.resetAll()
                Logger.activityController.debug("🔄 Reset auth retry counters")
            }

            Logger.activityController.debug("🔄 Resetting all share mount stati")
            await mounter.setAllMountStatus(to: .undefined)

            Logger.activityController.debug("🔄 Updating MDM share configuration")
            await mounter.shareManager.updateShareArray()

            Logger.activityController.debug("🔄 Checking for SMBHome shares")
            await mounter.shareManager.updateSMBHome()

            Logger.activityController.debug("🔄 Rescanning existing mounts")
            await mounter.rescanExistingMounts()

            if appDelegate?.enableKerberos == true {
                Logger.activityController.debug("🔄 Kerberos enabled - triggering authentication before mount")
                await performSoftRestartWithKerberosAuth(mounter: mounter)
            } else {
                Logger.activityController.debug("🔄 No Kerberos - mounting shares directly")
                await mounter.mountGivenShares()
            }

            Logger.activityController.debug("🔄 Refreshing Finder view")
            let finderController = FinderController()
            let mountPaths = await finderController.getActualMountPaths(from: mounter)
            await finderController.refreshFinder(forPaths: mountPaths)

            Logger.activityController.info("✅ Soft restart completed successfully")
        }

        _ = restartTask
    }

    /// Performs soft restart with Kerberos authentication wait
    ///
    /// Waits for Kerberos authentication to complete before mounting shares.
    /// Includes a 30-second timeout to prevent indefinite blocking.
    ///
    /// - Parameter mounter: The Mounter instance to use for mounting
    @MainActor
    private func performSoftRestartWithKerberosAuth(mounter: Mounter) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var authObserver: NSObjectProtocol?
            var hasResumed = false

            authObserver = NotificationCenter.default.addObserver(
                forName: .nsmNotification,
                object: nil,
                queue: .main
            ) { notification in
                guard !hasResumed else { return }

                if notification.userInfo?["krbAuthenticated"] is Error {
                    Logger.activityController.debug("✅ Kerberos authentication successful - proceeding with mount")
                    hasResumed = true

                    if let observer = authObserver {
                        NotificationCenter.default.removeObserver(observer)
                    }

                    Task { @MainActor in
                        await mounter.mountGivenShares()
                        continuation.resume()
                    }
                }
            }

            NotificationCenter.default.post(
                name: Defaults.nsmAuthTriggerNotification,
                object: nil,
                userInfo: ["forceAuth": true]
            )

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 30_000_000_000)

                guard !hasResumed else { return }
                hasResumed = true

                if let observer = authObserver {
                    NotificationCenter.default.removeObserver(observer)
                }

                Logger.activityController.warning("⚠️ Kerberos authentication timeout - proceeding with mount anyway")
                await mounter.mountGivenShares()
                continuation.resume()
            }
        }
    }

    // MARK: - Helpers for utilizing the cliTask method

    /// Executes a CLI command asynchronously with error handling
    ///
    /// - Parameter command: The command to execute
    /// - Returns: The command output if successful
    /// - Throws: Any errors that occur during command execution
    private func executeCommand(_ command: String) async throws -> String {
        do {
            return try await cliTask(command)
        } catch {
            Logger.activityController.error("Command execution failed: \(command, privacy: .public), error: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Checks if a daily heartbeat log should be generated
    ///
    /// - Returns: true if the last heartbeat was on a different day
    private func shouldLogDailyHeartbeat() -> Bool {
        let lastHeartbeat = UserDefaults.standard.object(forKey: "lastHeartbeatLogDate") as? Date
        guard let lastHeartbeat = lastHeartbeat else {
            return true
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let lastHeartbeatDay = calendar.startOfDay(for: lastHeartbeat)

        return today > lastHeartbeatDay
    }
}

// MARK: - Authentication Retry Tracker

/// Thread-safe actor for tracking Kerberos authentication retry attempts
///
/// Manages retry counters per share to prevent infinite retry loops while allowing
/// single retry attempts after authentication failures.
actor AuthRetryTracker {
    private var attempts: [String: Int] = [:]

    /// Gets the current retry count for a share and increments it
    ///
    /// - Parameter shareID: The share identifier
    /// - Returns: The retry count BEFORE incrementing
    func incrementAndGet(for shareID: String) -> Int {
        let current = attempts[shareID] ?? 0
        attempts[shareID] = current + 1
        return current
    }

    /// Resets the retry counter for a specific share
    ///
    /// - Parameter shareID: The share identifier
    func reset(for shareID: String) {
        attempts.removeValue(forKey: shareID)
    }

    /// Resets all retry counters
    func resetAll() {
        attempts.removeAll()
    }

    /// Checks if a share has exceeded its retry limit
    ///
    /// - Parameter shareID: The share identifier
    /// - Returns: true if the share has already been retried
    func hasExceededLimit(for shareID: String) -> Bool {
        return (attempts[shareID] ?? 0) >= 1
    }
}

