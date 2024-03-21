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
    var automaticSignIn: AutomaticSignIn?
    var prefs = PreferenceManager()
    let appDelegate = NSApplication.shared.delegate as! AppDelegate
    
    init(withMounter: Mounter) {
        mounter = withMounter
        startMonitoring(mounter: mounter)
        Logger.activityController.debug("ActivityController initialized")
    }
    
    /// initialize observers to get notifications
    func startMonitoring(mounter: Mounter) {
        // create an observer for NSWorkspace notifications
        // first stop possible exitisting observers
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        DistributedNotificationCenter.default.removeObserver(self)
        
        // get notification when system sleep is started
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(unmountShares), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(unmountShares), name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(mountShares), name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(mountShares), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(processAutomaticSignIn), name: Defaults.nsmAuthTriggerNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(timeGoesBySoSlowly), name: Defaults.nsmTimeTriggerNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(mountShares), name: Defaults.nsmMountTriggerNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(unmountShares), name: Defaults.nsmUnmountTriggerNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(userTrigger), name: Defaults.nsmMountManuallyTriggerNotification, object: nil)
        
        // get notification for "CCAPICCacheChangedNotification" (as defined in kcm.h) changes
        DistributedNotificationCenter.default.addObserver(self, selector: #selector(processAutomaticSignIn), name: "CCAPICCacheChangedNotification" as CFString as NSNotification.Name, object: nil)
    }
    
    // call unmount shares on NSWorkspace notification
    @objc func unmountShares() {
        Logger.activityController.debug("unmountAllShares called by willSleepNotification")
        Task {
            await self.mounter.unmountAllMountedShares()
        }
    }
    
    // call mount shares on NSWorkspace notification
    @objc func mountShares() {
        Logger.activityController.debug("mountAllShares called by didWakeNotification")
        Task {
            await self.mounter.mountAllShares(userTriggered: true)
        }
    }
    
    // call automatic sign in on notification
    @objc func processAutomaticSignIn() {
        Logger.activityController.debug("processAutomaticSignIn called by CCAPICCacheChangedNotification")
        appDelegate.automaticSignIn = AutomaticSignIn()
    }
    
    // call mount shares with manually parameter and, if configured, renew kerberos tickets
    @objc func userTrigger() {
        Logger.activityController.debug("authenticate/renew kerberos tickets called by nsmMountManuallyTriggerNotification")
        if let krbRealm = self.prefs.string(for: .kerberosRealm), !krbRealm.isEmpty {
            Logger.activityController.debug("-> Kerberos Realm configured, processing automatic AutomaticSignIn")
            self.processAutomaticSignIn()
        }
        Logger.activityController.debug("mountAllShares called by nsmMountManuallyTriggerNotification")
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
        // run authenticaction only if kerberos auth is enabled
        // forcing unwrapping the optional is OK, since values are "registered"
        // and set to empty string if not set
        // check if a kerberos domain/realm is set and is not empty
        if let krbRealm = self.prefs.string(for: .kerberosRealm), !krbRealm.isEmpty {
            Logger.activityController.debug(" ▶︎ ...kerberos realm configured, processing AutomaticSignIn")
            self.processAutomaticSignIn()
        }
        Logger.activityController.debug(" ▶︎ ...check for possible MDM profile changes")
        // call updateShareArray() to reflect possible changes in MDM profile
        self.mounter.shareManager.updateShareArray()
        Logger.activityController.debug(" ▶︎ ...finally call mountAllShares.")
        Task {
            await self.mounter.mountAllShares()
        }
    }
}
