//
//  MountStatus.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 04.02.24.
//  Copyright © 2024 Regionales Rechenzentrum Erlangen. All rights reserved.
//

/// defines mount states of a share
/// - Parameter unmounted: share is not mounted
/// - Parameter mounted: mounted share
/// - Parameter queued: queued for mounting
/// - Parameter toBeMounted: share should be mounted
/// - Parameter errorOnMount: failed to mount a shared
/// - Parameter undefined: share is in an undefined state, e.g. after a network change notification an needs to be checked
enum MountStatus: String {
    case unmounted = "unmounted"
    case mounted = "mounted"
    case queued = "queued"
    case toBeMounted = "toBeMounted"
    case errorOnMount = "errorOnMount"
    case unreachable = "unreachable"
    case undefined = "undefined"
    case userUnmounted = "userUnmounted"
    case missingPassword = "missingPassword"
    case invalidCredentials = "invalidCredentials"
    case obstructingDirectory = "obstructingDirectory"
    case unassignedProfile = "unassignedProfile"
    case unknown = "unknown"
}
