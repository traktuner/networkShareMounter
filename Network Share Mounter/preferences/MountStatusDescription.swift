//
//  MountStatusHelp.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 12.07.24.
//  Copyright © 2024 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation
import Cocoa

enum MountStatusDescription: String {
    case mounted = "mounted"
    case queued = "queued"
    case invalidCredentials = "invalidCredentials"
    case errorOnMount = "errorOnMount"
    case obstructingDirectory = "obstructingDirectory"
    case unreachable = "unreachable"
    case unknown = "unknown"
    
    var localizedDescription: String {
        return NSLocalizedString(self.rawValue, comment: "")
    }
    
    var symbolName: String {
        switch self {
        case .mounted:
            return "externaldrive.fill.badge.checkmark"
        case .queued:
            return "externaldrive.fill.badge.plus"
        case .invalidCredentials:
            return "externaldrive.fill.badge.person.crop"
        case .errorOnMount:
            return "externaldrive.fill.badge.xmarkks"
        case .obstructingDirectory:
            return "externaldrive.fill.trianglebadge.exclamationmark"
        case .unreachable:
            return "externaldrive.fill.badge.questionmarkk"
        case .unknown:
            return "externaldrive.badge.minus"
        }
    }
    
    var color: NSColor {
        switch self {
        case .mounted:
            return .green
        case .queued:
            return .orange
        case .invalidCredentials:
            return .red
        case .errorOnMount:
            return .red
        case .obstructingDirectory:
            return .purple
        case .unreachable:
            return .labelColor
        case .unknown:
            return .darkGray
        }
    }
}
