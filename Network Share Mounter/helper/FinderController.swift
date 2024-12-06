//
//  FinderController.swift
//  Network Share Mounter
//
//  Created by Gregor Longariva on 06.12.24.
//  Copyright © 2024 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation

actor FinderController {
    private var isRestarting = false
    
    func restartFinder() async {
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
