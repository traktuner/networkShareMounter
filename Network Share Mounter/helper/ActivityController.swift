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


///
/// class to handle system (NSWorkspace) notifications when system starts sleeping
class ActivityController {
    
    var prefs = PreferenceManager()
    var appDelegate: AppDelegate

    init(appDelegate: AppDelegate) {
        self.appDelegate = appDelegate
        startMonitoring()
    }
       
    /// initialize observers to get notifications
    func startMonitoring() {
        // create an observer for NSWorkspace notifications
        // first stop possible exitisting observers
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default.removeObserver(self)
        
        // trigger if macOS sleep will be started
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(unmountShares), name: NSWorkspace.willSleepNotification, object: nil)
        // trigger if session becomes inactive
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(unmountShares), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        // trigger if user logs out or shuts down macOS
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(unmountShares), name: NSWorkspace.willPowerOffNotification, object: nil)
        // trigger if Mac wakes up from sleep
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wakeupFromSleep), name: NSWorkspace.didWakeNotification, object: nil)
        // trigger if user session becomes active
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(mountShares), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        // time trigger to reauthenticate
        NotificationCenter.default.addObserver(self, selector: #selector(processAutomaticSignIn), name: Defaults.nsmAuthTriggerNotification, object: nil)
        // time trigger to mount shares/check for new profile
        NotificationCenter.default.addObserver(self, selector: #selector(timeGoesBySoSlowly), name: Defaults.nsmTimeTriggerNotification, object: nil)
        // trigger to mount shares
        NotificationCenter.default.addObserver(self, selector: #selector(mountShares), name: Defaults.nsmMountTriggerNotification, object: nil)
        // triogger to unmount shares
        NotificationCenter.default.addObserver(self, selector: #selector(unmountShares), name: Defaults.nsmUnmountTriggerNotification, object: nil)
        // trigger to manually mount shares
        NotificationCenter.default.addObserver(self, selector: #selector(mountSharesWithUserTrigger), name: Defaults.nsmMountManuallyTriggerNotification, object: nil)
        // trigger on network change to mount shares
        NotificationCenter.default.addObserver(self, selector: #selector(mountSharesWithUserTrigger), name: Defaults.nsmNetworkChangeTriggerNotification, object: nil)
        // triger reconstruct menu
        NotificationCenter.default.addObserver(self, selector: #selector(reconstructMenuTrigger), name: Defaults.nsmReconstructMenuTriggerNotification, object: nil)
        
        // get notification for "CCAPICCacheChangedNotification" (as defined in kcm.h) changes
        DistributedNotificationCenter.default.addObserver(self, selector: #selector(processAutomaticSignIn), name: "CCAPICCacheChangedNotification" as CFString as NSNotification.Name, object: nil)
    }
    
    // call unmount shares on NSWorkspace notification
    @objc func unmountShares() {
        if let mounter = appDelegate.mounter {
            Logger.activityController.debug(" ▶︎ unmountAllShares called by willSleepNotification.")
            Task {
                await mounter.unmountAllMountedShares()
            }
        }
    }
    
    // functions called after wake up
    @objc func wakeupFromSleep() {
        if let mounter = appDelegate.mounter {
            Logger.activityController.debug(" ▶︎ mountAllShares called by didWakeNotification.")
            Task {
                // await self.mounter.mountAllShares(userTriggered: true)
                await mounter.mountAllShares()
                Logger.activityController.debug(" 🐛 Restart Finder to bypass a presumed bug in macOS.")
                mounter.restartFinder()
            }
        }
    }
    
    // call mount shares on NSWorkspace notification
    @objc func mountShares() {
        if let mounter = appDelegate.mounter {
            Logger.activityController.debug(" ▶︎ mountAllShares called by didWakeNotification.")
            Task {
                // await self.mounter.mountAllShares(userTriggered: true)
                await mounter.mountAllShares()
            }
        }
    }
    
    // call automatic sign in on notification
    @objc func processAutomaticSignIn() {
        // run authenticaction only if kerberos auth is enabled
        // forcing unwrapping the optional is OK, since values are "registered"
        // and set to empty string if not set
        // check if a kerberos domain/realm is set and is not empty
        if let krbRealm = self.prefs.string(for: .kerberosRealm), !krbRealm.isEmpty {
            Task {
                Logger.activityController.debug(" ▶︎ kerberos realm configured, processing AutomaticSignIn.")
                await appDelegate.automaticSignIn.signInAllAccounts()
            }
        }
    }
    
    // call mount shares with manually parameter and, if configured, renew kerberos tickets
    @objc func mountSharesWithUserTrigger() {
        // renew tickets
        processAutomaticSignIn()
        // mount shares
        if let mounter = appDelegate.mounter {
            Logger.activityController.debug(" ▶︎ mountAllShares with user-trigger called.")
            Task {
                await mounter.mountAllShares(userTriggered: true)
            }
        }
    }
    
    @objc func reconstructMenuTrigger() {
        if let mounter = appDelegate.mounter {
            Logger.activityController.debug(" ▶︎ reconstruct menu trigger called.")
            Task { @MainActor in
                await appDelegate.constructMenu(withMounter: mounter)
            }
        }
    }
    
    /// perform some actions now and then, such as renew Kerberos tickets,
    /// mount shares etc.
    ///
    /// Time goes by so slowly
    /// Time goes by so slowly
    /// Time goes by so slowly for those who wait
    /// No time to hesitate
    /// Those who run seem to have all the fun
    /// I'm caught up, I don't know what to do
    @objc func timeGoesBySoSlowly() {
        if let mounter = appDelegate.mounter {
            Logger.activityController.debug("⏰ Time goes by so slowly: got timer notification.")
            Logger.activityController.debug(" ▶︎ ...check for possible MDM profile changes.")
            // call updateShareArray() to reflect possible changes in MDM profile?
            Task {
                await mounter.shareManager.updateShareArray()
                Logger.activityController.debug(" ▶︎ ...finally call mountAllShares.")
                await mounter.mountAllShares()
            }
        }
    }
}
