//
//  Share.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 10.08.23.
//  Copyright © 2024 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation
import OSLog

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
    var shareDisplayName: String?
    /// Optional authentication profile ID for shares using the new AuthProfile system
    var authProfileID: String?
    /// When true, Kerberos is managed externally (AD binding, Jamf Connect, etc.).
    /// NSM creates a read-only pseudo-profile for UI consistency and skips ticket management.
    var externalKerberosManagement: Bool = false
    /// When false the share appears in the menu but is never mounted automatically.
    /// The user can mount it on demand by clicking the menu item. Default: true.
    var autoMount: Bool = true
    /// Unique identifier (random UUID). Remains stable for the life-time of the Share instance and
    /// is stored persistently when needed (e.g. associated profiles).
    var id: String = UUID().uuidString
    
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
    
    /// Validates if a mount point value is safe
    ///
    /// Mount points must be simple directory names without path separators.
    /// They are used as relative names appended to the default mount path.
    /// Both MDM and user-configured mount points follow the same rules.
    ///
    /// Valid:   "share", "data", "MyShare", ".hidden" (hidden directories are OK)
    /// Invalid: "/home", "foo/bar", "../etc", "" (empty)
    ///
    /// - Parameter mountPoint: The mount point string to validate
    /// - Returns: true if valid (simple name) or nil, false if invalid (contains path separators)
    static func isValidMountPoint(_ mountPoint: String?) -> Bool {
        guard let mountPoint = mountPoint, !mountPoint.isEmpty else {
            return true
        }

        // Mount point must not contain path separators (/)
        // This prevents absolute paths like "/home" or relative paths like "foo/bar"
        if mountPoint.contains("/") {
            return false
        }

        // Mount point must not be . or .. (directory traversal)
        if mountPoint == "." || mountPoint == ".." {
            return false
        }

        return true
    }

    /// Sanitizes a mount point value by extracting just the final component
    ///
    /// If someone accidentally provides an absolute path like "/Users/test/mount",
    /// this returns just "mount". If the input is already a simple name, returns it unchanged.
    ///
    /// - Parameter mountPoint: The mount point string to sanitize
    /// - Returns: Sanitized mount point (simple directory name) or nil if invalid
    static func sanitizeMountPoint(_ mountPoint: String?) -> String? {
        guard let mountPoint = mountPoint, !mountPoint.isEmpty else {
            return nil
        }

        // If it's already valid, return as-is
        if isValidMountPoint(mountPoint) {
            return mountPoint
        }

        // Extract last component from path (e.g., "/home/test" -> "test")
        let url = URL(fileURLWithPath: mountPoint)
        let lastComponent = url.lastPathComponent

        // Validate the extracted component
        if isValidMountPoint(lastComponent) && !lastComponent.isEmpty {
            return lastComponent
        }

        return nil
    }

    /// Update the mount point of a share with validation
    mutating func updateMountPoint(to mountPoint: String?) {
        modify { share in
            // Sanitize and validate the mount point before storing
            let sanitized = Share.sanitizeMountPoint(mountPoint)
            if let value = sanitized {
                share.mountPoint = value
            } else if mountPoint == nil {
                // Allow explicit nil to clear the mount point
                share.mountPoint = nil
            } else {
                // Invalid mount point - log warning and don't update
                // Avoid capturing 'share' (inout) in logger's autoclosure by copying values first
                let rejectedValue = mountPoint ?? "nil"
                let shareURL = share.networkShare
                Logger.shareManager.warning("⚠️ Invalid mountPoint value rejected: '\(rejectedValue, privacy: .public)' for share: \(shareURL, privacy: .public)")
            }
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

    /// Factory-method that guarantees a **stable, deterministic ID** based on the share URL. This
    /// prevents UI race-conditions where randomly generated UUIDs change between reloads.
    static func createShare(
        networkShare: String,
        authType: AuthType,
        mountStatus: MountStatus,
        username: String? = nil,
        password: String? = nil,
        mountPoint: String? = nil,
        managed: Bool = true,
        shareDisplayName: String? = nil,
        authProfileID: String? = nil,
        externalKerberosManagement: Bool = false,
        autoMount: Bool = true
    ) -> Share {
        // Sanitize mountPoint before creating the share
        let sanitizedMountPoint = sanitizeMountPoint(mountPoint)

        return Share(
            networkShare: networkShare,
            authType: authType,
            username: username,
            password: password,
            mountStatus: mountStatus,
            mountPoint: sanitizedMountPoint,
            actualMountPoint: nil,
            managed: managed,
            shareDisplayName: shareDisplayName,
            authProfileID: authProfileID,
            externalKerberosManagement: externalKerberosManagement,
            autoMount: autoMount,
            id: UUID().uuidString
        )
    }
}
