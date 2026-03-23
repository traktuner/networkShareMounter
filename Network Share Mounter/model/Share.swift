//
//  Share.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 10.08.23.
//  Copyright © 2024 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation

/// describes the different properties and states of a share
/// - Parameter networkShare: ``URL`` containing the exporting server and share
/// - Parameter authType: ``authTyoe`` defines if the mount uses kerberos or username/password for authentication
/// - Parameter username: optional ``String`` containing the username needed to mount a share
/// - Parameter mountStatus: Optional ``MountStatus`` describing the actual mount status
/// - Parameter password: optional ``String`` containing the password to mount the share. Both username and password are retrieved from user's keychain
/// - Parameter mountpoint: optional ``String`` specific mountpoint for the share
/// - Parameter actualMountPoint: optional ``String`` containig the full path of the mountpoint where the
///   share is actually mounted. This value is set by the mount routine if the mount is successfully mounted and should be removed when the share is
///   unmounted
///
/// *The following variables could be useful in future versions:*
/// - options: array of parameters for the mount command
/// - autoMount: for future use, the possibility to not mount shares automatically
/// - localMountPoint: for future use, define a mount point for the share
struct Share: Identifiable {
    var networkShare: String
    var authType: AuthType
    var username: String?
    var password: String?
    var mountStatus: MountStatus
    var mountPoint: String?
    var actualMountPoint: String?
    var managed: Bool
    var id = UUID().uuidString
    
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
    
    /// Update the mount point of a share
    mutating func updateMountPoint(to mountPoint: String?) {
        modify { share in
            share.mountPoint = mountPoint
        }
    }
    
    /// Update the mount point of a share
    mutating func updateActualMountPoint(to actualMountPoint: String?) {
        modify { share in
            share.actualMountPoint = actualMountPoint
        }
    }
    
    /// Returns the effective mount point name for this share.
        /// Uses mountPoint if set, otherwise auto-generates from networkShare URL.
        var effectiveMountPoint: String {
            if let mountPoint = mountPoint, !mountPoint.isEmpty {
                return mountPoint
            }
            return extractShareName(from: networkShare)
        }
    
    /// factory-method, to create a new Share object
    static func createShare(networkShare: String, authType: AuthType, mountStatus: MountStatus, username: String? = nil, password: String? = nil, mountPoint: String? = nil, managed: Bool = true) -> Share {
        return Share(networkShare: networkShare, authType: authType, username: username, password: password, mountStatus: mountStatus, mountPoint: mountPoint, managed: managed, id: UUID().uuidString)
    }
    
    /// Extracts the share name from a network path.
    ///
    /// Handles paths like:
    /// - `smb://server/share` → "share"
    /// - `afp://server/share` → "share"
    ///
    /// - Parameter networkPath: The full network share URL.
    /// - Returns: The extracted share name, or the full path if extraction fails.
    private func extractShareName(from networkPath: String) -> String {
        // Remove protocol
        let path = networkPath
            .replacingOccurrences(of: "smb://", with: "")
            .replacingOccurrences(of: "afp://", with: "")
            .replacingOccurrences(of: "nfs://", with: "")
        
        // Get the last component
        let components = path.split(separator: "/")
        if let lastComponent = components.last {
            return String(lastComponent)
        }
        
        return networkPath
    }

}
