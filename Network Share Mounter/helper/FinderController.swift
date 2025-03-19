//
//  FinderController.swift
//  Network Share Mounter
//
//  Created by Gregor Longariva on 06.12.24.
//  Copyright © 2024 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation
import AppKit

actor FinderController {
    private var isRestarting = false
    
    func restartFinder() async {
        // Überprüfe, ob der Finder läuft
        let runningFinder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder")
        guard !runningFinder.isEmpty else {
            // Finder läuft nicht, daher Neustart überspringen
            return
        }
        
        guard !isRestarting else { return }
        
        isRestarting = true
        defer { isRestarting = false }
        
        let task = Process()
        task.launchPath = "/usr/bin/killall"
        task.arguments = ["Finder"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.launch()
    }
}
