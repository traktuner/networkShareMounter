//
//  Date.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 15.12.23.
//  Copyright © 2020 Orchard & Grove, Inc. All rights reserved.
//  Copyright © 2023 RRZE. All rights reserved.
//

import Foundation

extension Date {
    
    var daysToGo: Int? {
        get {
            if self.timeIntervalSinceNow > 0 {
                return Int(self.timeIntervalSinceNow / 60 / 60 / 24)
            } else {
                return nil
            }
        }
    }
}
