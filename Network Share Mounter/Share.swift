//
//  Share.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 10.08.23.
//  Copyright © 2023 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation

/// defines mount states of a share
/// - Parameter unmounted: share is not mounted
/// - Parameter mounted: mounted share
/// - Parameter queued: queued for mounting
/// - Parameter toBeMounted: share should be mounted
/// - Parameter errorOnMount: failed to mount a shared
enum MountStatus: String {
    case unmounted = "unmounted"
    case mounted = "mounted"
    case queued = "queued"
    case toBeMounted = "toBeMounted"
    case errorOnMount = "errorOnMount"
}

/// describes the different properties and states of a share
/// - Parameter networkShare: ``URL`` containing the exporting server and share
/// - Parameter authType: ``authTyoe`` defines if the mount uses kerberos or username/password for authentication
/// - Parameter username: optional ``String`` containing the username needed to mount a share
/// - Parameter mountStatus: Optional ``MountStatus`` describing the actual mount status
/// - Parameter password: optional ``String`` containing the password to mount the share. Both username and password are retrieved from user's keychain
///
/// *The following variables could be useful in future versions:*
/// - options: array of parameters for the mount command
/// - autoMount: for future use, the possibility to not mount shares automatically
/// - localMountPoint: for future use, define a mount point for the share
struct Share: Identifiable {
    var networkShare: URL
    var authType: AuthType
    var username: String?
    var mountStatus: MountStatus
    var password: String?
    var mountPoint: String?
    var id = UUID()
    
    /// Lock for thread-safe access to Share properties
    private var lock = os_unfair_lock()
    
    /// Helper function to safely access and modify Share properties
    private mutating func modify(_ modify: (inout Share) -> Void) {
        os_unfair_lock_lock(&lock)
        modify(&self)
        os_unfair_lock_unlock(&lock)
    }
    
    /// updates a share and returns the new instamce
    mutating func updated() -> Share {
        let updatedShare = self
        return updatedShare
    }
    
    /// update
//    mutating func updated(withStatus status: MountStatus) -> Share {
//        var updatedShare = self
//        updatedShare.modify { share in
//            share.mountStatus = status
//        }
//        return updatedShare
//    }
    
    /// Update the mount status of a Share
    mutating func updateMountStatus(to newMountStatus: MountStatus) {
        modify { share in
            share.mountStatus = newMountStatus
        }
    }
    
    /// factory-method, to create a new Share object
    static func createShare(networkShare: URL, authType: AuthType, mountStatus: MountStatus, username: String? = nil, password: String? = nil, mountPoint: String? = nil) -> Share {
        return Share(networkShare: networkShare, authType: authType, username: username, mountStatus: mountStatus, password: password, mountPoint: mountPoint, id: UUID())
    }
}
