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
    
    // MARK: - Initialization
    
    /// Initializes the controller and starts monitoring system events
    /// 
    /// - Parameter appDelegate: Reference to the AppDelegate instance
    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
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
        guard let mounter = appDelegate?.mounter else {
            Logger.activityController.error("Wake-up processing failed: Mounter not available")
            return
        }
        
        Logger.activityController.debug("▶︎ mountGivenShares called by didWakeNotification")
        
        let wakeupTask = Task { @MainActor in
            Logger.activityController.debug("🔄 Wake-up operation - Starting mount process")
            // Update SMBHome from AD/OpenDirectory on network/domain changes
            await mounter.shareManager.updateSMBHome()
            
            await mounter.mountGivenShares()
            Logger.activityController.debug("🔄 Refreshing Finder view to ensure mounted shares are visible")
            
            let finderController = FinderController()
            let mountPaths = await finderController.getActualMountPaths(from: mounter)
            await finderController.refreshFinder(forPaths: mountPaths)
            Logger.activityController.debug("✅ Wake-up operation completed")
        }
        
        _ = wakeupTask
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
    @objc func processAutomaticSignIn() {
        // Check if a Kerberos realm is configured
        guard let krbRealm = self.prefs.string(for: .kerberosRealm), !krbRealm.isEmpty else {
            Logger.activityController.debug("No Kerberos realm configured, skipping AutomaticSignIn")
            return
        }
        
        // Prevent too frequent authentication attempts.
        let lastAuthAttempt = UserDefaults.standard.object(forKey: "lastKrbAuthAttempt") as? Date ?? Date.distantPast
        let timeSinceLastAttempt = Date().timeIntervalSince(lastAuthAttempt)
        
        // wait at least 30 seconds between authentication attempts
        guard timeSinceLastAttempt > 30 else {
            Logger.activityController.debug("Skipping auth attempt - too soon since last attempt (\(timeSinceLastAttempt, privacy: .public)s)")
            return
        }
        
        UserDefaults.standard.set(Date(), forKey: "lastKrbAuthAttempt")
        
        Task { @MainActor in
            Logger.activityController.debug("▶︎ Kerberos realm configured, processing AutomaticSignIn")
            
            do {
                Logger.activityController.debug("🔄 Starting automatic sign-in task")
                await appDelegate?.automaticSignIn.signInAllAccounts()
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
        // Renew Kerberos tickets
        processAutomaticSignIn()
        
        guard let mounter = appDelegate?.mounter else {
            Logger.activityController.error("User request for mounting failed: Mounter not available")
            return
        }
        
        Logger.activityController.debug("▶︎ mountGivenShares with user-trigger called")
        
        let userMountTask = Task { @MainActor in
            Logger.activityController.debug("🔄 Manual mount operation - Starting mount process")
            
            // Update SMBHome from AD/OpenDirectory on network/domain changes
            await mounter.shareManager.updateSMBHome()
            
            await mounter.mountGivenShares(userTriggered: true)
            Logger.activityController.debug("✅ Shares successfully mounted after user request - Operation completed")
        }
        
        _ = userMountTask
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
        // Only trigger auth during timer calls if we're past the startup phase
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
}

