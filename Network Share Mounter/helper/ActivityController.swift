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
    
    // MARK: - Initialization
    
    /// Initializes the controller and starts monitoring system events
    /// 
    /// - Parameter appDelegate: Reference to the AppDelegate instance
    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        startMonitoring()
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
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(mountSharesWithUserTrigger),
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
        
        Logger.activityController.debug("▶︎ unmountAllShares called by \(notificationName)")
        
        Task {
            await mounter.unmountAllMountedShares()
            Logger.activityController.debug("All shares successfully unmounted")
        }
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
        
        Task {
            await mounter.mountGivenShares()
            Logger.activityController.debug("🐛 Restarting Finder to bypass a presumed bug in macOS")
            
            let finderController = FinderController()
            await finderController.restartFinder()
        }
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
        
        Logger.activityController.debug("▶︎ mountGivenShares called by \(notificationName)")
        
        Task {
            await mounter.mountGivenShares()
            Logger.activityController.debug("All shares successfully mounted")
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
        
        Task {
            Logger.activityController.debug("▶︎ Kerberos realm configured, processing AutomaticSignIn")
            await appDelegate?.automaticSignIn.signInAllAccounts()
            Logger.activityController.info("Automatic sign-in completed successfully")
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
        
        Task {
            await mounter.mountGivenShares(userTriggered: true)
            Logger.activityController.info("Shares successfully mounted after user request")
        }
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
        
        Task { @MainActor in
            await appDelegate?.constructMenu(withMounter: mounter)
            Logger.activityController.debug("Menu successfully updated")
        }
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
        NotificationCenter.default.post(name: Defaults.nsmAuthTriggerNotification, object: nil)
        guard let mounter = appDelegate?.mounter else {
            Logger.activityController.error("Timer processing failed: Mounter not available")
            return
        }
        
        Logger.activityController.debug("⏰ Time goes by so slowly: Timer notification received")
        Logger.activityController.debug("▶︎ ...checking for possible MDM profile changes")
        
        // Check ShareArray for possible changes in MDM profile
        Task {
            await mounter.shareManager.updateShareArray()
            Logger.activityController.debug("▶︎ ...calling mountGivenShares")
            await mounter.mountGivenShares()
            Logger.activityController.debug("Timer processing completed successfully")
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
            Logger.activityController.error("Command execution failed: \(command), error: \(error.localizedDescription)")
            throw error
        }
    }
}
