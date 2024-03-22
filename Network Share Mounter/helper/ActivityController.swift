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
    
    var mounter: Mounter
    var prefs = PreferenceManager()
    let appDelegate = NSApplication.shared.delegate as! AppDelegate
    
    init(withMounter: Mounter) {
        mounter = withMounter
        startMonitoring(mounter: mounter)
        Logger.activityController.debug("🎯 ActivityController initialized")
    }
    
    /// initialize observers to get notifications
    func startMonitoring(mounter: Mounter) {
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
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(mountShares), name: NSWorkspace.didWakeNotification, object: nil)
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
        
        // get notification for "CCAPICCacheChangedNotification" (as defined in kcm.h) changes
        DistributedNotificationCenter.default.addObserver(self, selector: #selector(processAutomaticSignIn), name: "CCAPICCacheChangedNotification" as CFString as NSNotification.Name, object: nil)
    }
    
    // call unmount shares on NSWorkspace notification
    @objc func unmountShares() {
        Logger.activityController.debug(" ▶︎ unmountAllShares called by willSleepNotification")
        Task {
            await self.mounter.unmountAllMountedShares()
        }
    }
    
    // call mount shares on NSWorkspace notification
    @objc func mountShares() {
        Logger.activityController.debug(" ▶︎ mountAllShares called by didWakeNotification")
        Task {
            // await self.mounter.mountAllShares(userTriggered: true)
            await self.mounter.mountAllShares()
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
                Logger.activityController.debug(" ▶︎ kerberos realm configured, processing AutomaticSignIn")
                appDelegate.automaticSignIn = AutomaticSignIn()
            }
        }
    }
    
    // call mount shares with manually parameter and, if configured, renew kerberos tickets
    @objc func mountSharesWithUserTrigger() {
        // renew tickets
        self.processAutomaticSignIn()
        // mount shares
        Logger.activityController.debug(" ▶︎ mountAllShares with user-trigger called")
        Task {
            await self.mounter.mountAllShares(userTriggered: true)
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
        Logger.activityController.debug("⏰ Time goes by so slowly: got timer notification")
        Logger.activityController.debug(" ▶︎ ...check for possible MDM profile changes")
        // call updateShareArray() to reflect possible changes in MDM profile?
        self.mounter.shareManager.updateShareArray()
        Logger.activityController.debug(" ▶︎ ...finally call mountAllShares.")
        Task {
            await self.mounter.mountAllShares()
        }
    }
}
