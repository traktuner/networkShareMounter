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
        NotificationCenter.default.addObserver(self, selector: #selector(timeGoesBySoSlowly), name: Defaults.nsmTriggerNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(unmountShares), name: Defaults.nsmUnmountTriggerNotification, object: nil)
        
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
        Task {
            self.automaticSignIn = AutomaticSignIn()
        }
    }
    
    @objc func timeGoesBySoSlowly() {
        Logger.activityController.debug("time passed notification called by Timer:")
        // run authenticaction only if kerberos auth is enabled
        // forcing unwrapping the optional is OK, since values are "registered"
        // and set to empty string if not set
        // check if a kerberos domain/realm is set and is not empty
        if let krbRealm = self.prefs.string(for: .kerberosRealm), !krbRealm.isEmpty {
            Logger.activityController.debug("-> Kerberos Realm configured, processing automatic AutomaticSignIn")
            self.processAutomaticSignIn()
        }
        Logger.activityController.debug("-> Check for possible MDM profile changes")
        // call updateShareArray() to reflect possible changes in MDM profile
        self.mounter.shareManager.updateShareArray()
        Logger.activityController.debug("-> Finally call mountAllShares.")
        Task {
            await self.mounter.mountAllShares()
        }
    }
}
