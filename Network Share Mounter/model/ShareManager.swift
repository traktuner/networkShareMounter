//
//  ShareManager.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 10.08.23.
//  Copyright © 2023 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation
import OSLog

/// class `ShareManager` to manage the shares (array fo Share)
class ShareManager {
    let logger = Logger(subsystem: "NetworkShareMounter", category: "ShareManager")
    private var sharesLock = os_unfair_lock()
    private var _shares: [Share] = []
    private let userDefaults = UserDefaults.standard
    
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
    
    /// delete all shares, delete array entries is not already empty
    func removeAllShares() {
        os_unfair_lock_lock(&sharesLock)
        if !_shares.isEmpty {
            _shares.removeAll()
        }
        os_unfair_lock_unlock(&sharesLock)
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
        let shareAuthType = AuthType(rawValue: shareElement[Settings.authType] ?? AuthType.krb.rawValue) ?? AuthType.krb
        var password: String?
        var mountStatus = MountStatus.unmounted
        if shareAuthType == AuthType.pwd {
            do {
                if let keychainPassword = try PasswordManager().retrievePassword(forShare: URL(string: shareRectified)!, withUsername: userName) {
                    password = keychainPassword
                }
            } catch {
                logger.warning("Password for share \(shareRectified, privacy: .public) not found in user's keychain")
                mountStatus = MountStatus.missingPassword
                password = nil
            }
        }
        
        let newShare = Share.createShare(networkShare: shareRectified, 
                                         authType: shareAuthType,
                                         mountStatus: mountStatus,
                                         username: userName,
                                         password: password,
                                         mountPoint: shareElement[Settings.mountPoint],
                                         managed: true)
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
        let newShare = Share.createShare(networkShare: shareRectified, authType: AuthType.krb, mountStatus: MountStatus.unmounted, managed: true)
        return(newShare)
    }
    
    /// read user defined share configuration and return an optional Share element
    /// - Parameter forShare shareElement: an array of a dictionary (key-value) containing the share definitions
    /// - Returns: optional `Share?` element
    func getUserShareConfigs(forShare shareElement: [String: String]) -> Share? {
        guard let shareUrlString = shareElement[Settings.networkShare] else {
            return nil
        }
        var password: String?
        var mountStatus = MountStatus.unmounted
        if let username = shareElement[Settings.username] {
            do {
                if let keychainPassword = try PasswordManager().retrievePassword(forShare: URL(string: shareUrlString)!, withUsername: username) {
                    password = keychainPassword
                }
            } catch {
                logger.warning("Password for share \(shareUrlString, privacy: .public) not found in user's keychain")
                mountStatus = MountStatus.missingPassword
                password = nil
            }
        }
        let shareAuthType = AuthType(rawValue: shareElement[Settings.authType] ?? AuthType.krb.rawValue) ?? AuthType.krb
        let newShare = Share.createShare(networkShare: shareUrlString, authType: shareAuthType, mountStatus: mountStatus, username: shareElement[Settings.username], password: password, managed: false)
        return(newShare)
    }
    
    func reReadShares() {
        
    }
    
    ///
    func createShareArray() {
        /// create an array from values configured in UserDefaults
        /// import configured shares from userDefaults for both mdm defined (legacy)`Settings.networkSharesKey`
        /// or `Settings.mdmNetworkSahresKey` and user defined `Settings.customSharesKey`.
        ///
        /// **Important**:
        /// - read only `Settings.mdmNetworkSahresKey` *OR* `Settings.networkSharesKey`, NOT both arrays
        /// - then read user defined `Settings.customSharesKey`
        ///
        var usedNewMDMprofile = false
        if let sharesDict = userDefaults.array(forKey: Settings.managedNetworkSharesKey) as? [[String: String]] {
            for shareElement in sharesDict {
                if let newShare = self.getMDMShareConfig(forShare: shareElement) {
                    usedNewMDMprofile = true
                    addShare(newShare)
                }
            }
        }
        /// alternatively try to get configured shares with now obsolete
        /// Network Share Mounter 2 definitions
        if !usedNewMDMprofile {
            if let nwShares: [String] = userDefaults.array(forKey: Settings.networkSharesKey) as? [String] {
                for share in nwShares {
                    if let newShare = self.getLegacyShareConfig(forShare: share) {
                        addShare(newShare)
                    }
                }
            }
        }
        /// next look if there are some user-defined shares to import
        if let privSharesDict = userDefaults.array(forKey: Settings.userNetworkShares) as? [[String: String]] {
            for share in privSharesDict {
                if let newShare = self.getUserShareConfigs(forShare: share) {
                    addShare(newShare)
                }
            }
        }
        /// at last there may be legacy user defined share definitions
        else if let nwShares: [String] = userDefaults.array(forKey: Settings.customSharesKey) as? [String] {
            for share in nwShares {
                addShare(Share.createShare(networkShare: share, authType: AuthType.krb, mountStatus: MountStatus.unmounted, managed: false))
            }
            removeLegacyShareConfigs()
        }
    }
    
    /// write user defined share configuration
    /// - Parameter forShare shareElement: an array of a dictionary (key-value) containing the share definitions
    func writeUserShareConfigs() {
        var userDefaultsConfigs: [[String: String]] = []
        
        
        for share in _shares {
            //
            // save MDM non-managed shares
            if share.managed == false {
                var shareConfig: [String: String] = [:]
                
                shareConfig[Settings.networkShare] = share.networkShare
                
                shareConfig[Settings.authType] = share.authType.rawValue
                shareConfig[Settings.username] = share.username
                if let mountPoint = share.mountPoint {
                    shareConfig[Settings.mountPoint] = mountPoint
                }
                if let username = share.username {
                    shareConfig[Settings.username] = username
                }
//                shareConfig[Settings.location] = share.location
                
                // Nur Passwort speichern, wenn es in der Keychain gefunden wurde
                if let password = share.password {
                    if let username = share.username {
                        let pwm = PasswordManager()
                        do {
                            try pwm.saveCredential(forShare: URL(string: share.networkShare)!, withUsername: username, andPpassword: password)
                        } catch {
                            logger.error("🛑 Cannot store password for share \(share.networkShare, privacy: .public) in user's keychain")
                        }
                    }
                }
                
                userDefaultsConfigs.append(shareConfig)
            }
        }
        
        userDefaults.set(userDefaultsConfigs, forKey: Settings.userNetworkShares)
        userDefaults.synchronize()
    }
    
    private func removeLegacyShareConfigs() {
        userDefaults.removeObject(forKey: Settings.customSharesKey)
        userDefaults.synchronize()
    }

}
