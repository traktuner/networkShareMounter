//
//  ShareManager.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 10.08.23.
//  Copyright © 2023 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation

/// class `ShareManager` to manage the shares (array fo Share)
class ShareManager {
    private var sharesLock = os_unfair_lock()
    private var _shares: [Share] = []
    
    /// Add a share
    func addShare(_ share: Share) {
        os_unfair_lock_lock(&sharesLock)
        if !allShares.contains(where: { $0.networkShare == share.networkShare }) {
            _shares.append(share)
        }
        os_unfair_lock_unlock(&sharesLock)
    }
    
    /// Remove a share at a specific index
    func removeShare(at index: Int) {
        os_unfair_lock_lock(&sharesLock)
        _shares.remove(at: index)
        os_unfair_lock_unlock(&sharesLock)
    }
    
    /// Get all shares
    var allShares: [Share] {
        return _shares
    }
    
    /// Update a share at a specific index
    func updateShare(at index: Int, withUpdatedShare updatedShare: Share) {
        os_unfair_lock_lock(&sharesLock)
        guard index >= 0 && index < _shares.count else {
            os_unfair_lock_unlock(&sharesLock)
            return
        }
        _shares[index] = updatedShare
        os_unfair_lock_unlock(&sharesLock)
    }
    
    /// Update the mount status of a share at a specific index
    /// - Parameters:
    ///   - index: The index of the share to update
    ///   - newMountStatus: The new mount status to set
    func updateMountStatus(at index: Int, to newMountStatus: MountStatus) {
        os_unfair_lock_lock(&sharesLock)
        defer { os_unfair_lock_unlock(&sharesLock) }
        
        guard index >= 0 && index < _shares.count else {
            return
        }
        _shares[index].updateMountStatus(to: newMountStatus)
    }
    
    /// Update the mountPoint of a share at a specific index
    /// - Parameters:
    ///   - index: The index of the share to update
    ///   - mountPoint: The mount point where the share should be mounted
    func updateMountPoint(at index: Int, to mountPoint: String?) {
        os_unfair_lock_lock(&sharesLock)
        defer { os_unfair_lock_unlock(&sharesLock) }
        
        guard index >= 0 && index < _shares.count else {
            return
        }
        _shares[index].updateMountPoint(to: mountPoint)
    }
    
    /// Update the actual used mountPoint of a share at a specific index
    /// - Parameters:
    ///   - index: The index of the share to update
    ///   - actualMountPoint: The mount point where the share is mounted
    func updateActualMountPoint(at index: Int, to actualMountPoint: String?) {
        os_unfair_lock_lock(&sharesLock)
        defer { os_unfair_lock_unlock(&sharesLock) }
        
        guard index >= 0 && index < _shares.count else {
            return
        }
        _shares[index].updateActualMountPoint(to: actualMountPoint)
    }
    
    /// read dictionary of string containig definitions for the share to be mounted
    /// - Parameter forShare shareElement: Array of String dictionary `[String:String]`
    /// - Returns: optional `Share?` element
    func getMDMShareConfig(forShare shareElement: [String:String]) -> Share? {
        guard let shareUrlString = shareElement[Settings.networkShare] else {
            return nil
        }
        //
        // check if there is a mdm defined username. If so, replace possible occurencies of %USERNAME% with that
        var userName: String = ""
        if let username = shareElement[Settings.username] {
            userName = username.replacingOccurrences(of: "%USERNAME%", with: NSUserName())
            userName = NSString(string: userName).expandingTildeInPath
        }
        
        //
        // replace possible %USERNAME occurencies with local username - must be the same as directory service username!
        let shareRectified = shareUrlString.replacingOccurrences(of: "%USERNAME%", with: NSUserName())
        guard let shareURL = URL(string: shareRectified) else {
            return nil
        }
        let shareAuthType = AuthType(rawValue: shareElement[Settings.authType] ?? AuthType.krb.rawValue) ?? AuthType.krb
        
        let newShare = Share.createShare(networkShare: shareURL, authType: shareAuthType, mountStatus: MountStatus.unmounted, username: userName, mountPoint: shareElement[Settings.mountPoint])
        return(newShare)
    }
    
    /// read Network Share Mounter version 2 configuration and return an optional Share element
    /// - Parameter forShare shareElement: an array of strings containig a list of network shares
    /// - Returns: optional `Share?` element
    func getLegacyShareConfig(forShare shareElement: String) -> Share? {
        /// then look if we have some legacy mdm defined share definitions which will be read **only** if there is no `Settings.mdmNetworkSahresKey` defined!
        //
        // replace possible %USERNAME occurencies with local username - must be the same as directory service username!
        let shareRectified = shareElement.replacingOccurrences(of: "%USERNAME%", with: NSUserName())
        guard let shareURL = URL(string: shareRectified) else {
            return nil
        }
        let newShare = Share.createShare(networkShare: shareURL, authType: AuthType.krb, mountStatus: MountStatus.unmounted)
        return(newShare)
    }
    
    /// read user defined share configuration and return an optional Share element
    /// - Parameter forShare shareElement: an array of a dictionary (key-value) containing the share definitions
    /// - Returns: optional `Share?` element
    func getUserShareConfigs(forShare shareElement: [String: String]) -> Share? {
        guard let shareUrlString = shareElement[Settings.networkShare] else {
            return nil
        }
        guard let shareURL = URL(string: shareUrlString) else {
            return nil
        }
        let shareAuthType = AuthType(rawValue: shareElement[Settings.authType] ?? AuthType.krb.rawValue) ?? AuthType.krb
        let newShare = Share.createShare(networkShare: shareURL, authType: shareAuthType, mountStatus: MountStatus.unmounted, username: shareElement[Settings.username])
        return(newShare)
    }
}
