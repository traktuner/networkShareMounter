//
//  Menu.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 20.12.23.
//  Copyright © 2024 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation

enum MenuImageName: String {
    case normal = "networkShareMounterMenu"
    case green = "networkShareMounterMenuGreen"
    case yellow = "networkShareMounterMenuYellow"
    case red = "networkShareMounterMenuRed"
    
    var imageName: String {
        #if DEBUG
        // Im Debug-Modus einen Suffix oder Präfix anhängen
        return self.rawValue + "Debug"
        #else
        return self.rawValue
        #endif
    }
}
