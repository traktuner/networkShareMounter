//
//  BackgroundManager.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 15.12.23.
//  Copyright © 2020 Orchard & Grove, Inc. All rights reserved.
//  Copyright © 2023 RRZE. All rights reserved.
//

import Foundation

class BackGroundManager {
    
    var automaticSignIn: AutomaticSignIn?
    
    static var shared = BackGroundManager()
    
    // timers
    
    var accountCheckTimer: Timer?
    
    init() {
        setupAutomaticSignIn()
        PKINIT.shared.startWatching()
        nw.setup()
    }
    
    @objc func processAutomaticSignIn() {
            self.automaticSignIn = AutomaticSignIn()
    }
    
    private func setupAutomaticSignIn() {
        accountCheckTimer = Timer(timeInterval: ( 15 * 60 ), target: self, selector: #selector(processAutomaticSignIn), userInfo: nil, repeats: true)
        guard self.accountCheckTimer != nil else { return }
        RunLoop.main.add(accountCheckTimer!, forMode: RunLoop.Mode.common)
        DistributedNotificationCenter.default.addObserver(self, selector: #selector(processAutomaticSignIn), name: "CCAPICCacheChangedNotification" as CFString as NSNotification.Name, object: nil)

    }
}
