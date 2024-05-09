//
//  ShareManager.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 10.08.23.
//  Copyright © 2024 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation
import OSLog

enum ShareError: Error {
    case invalidIndex(Int)
}

/// class `ShareManager` to manage the shares (array fo Share)
class ShareManager {
    private var sharesLock = os_unfair_lock()
    private var _shares: [Share] = []
    private let userDefaults = UserDefaults.standard
    
    /// Add a share
    func addShare(_ share: Share) {
        os_unfair_lock_lock(&sharesLock)
        if !allShares.contains(where: { $0.networkShare == share.networkShare }) {
            _shares.append(share)
            //
            // save password in keychain
            if let password = share.password {
                if let username = share.username {
                    let pwm = KeychainManager()
                    do {
                        try pwm.saveCredential(forShare: URL(string: share.networkShare)!, withUsername: username, andPassword: password)
                    } catch {
                        Logger.shareManager.error("🛑 Cannot store password for share \(share.networkShare, privacy: .public) in user's keychain")
                    }
                }
            }
        }
        os_unfair_lock_unlock(&sharesLock)
    }
    
    /// Remove a share at a specific index
    func removeShare(at index: Int) {
        os_unfair_lock_lock(&sharesLock)
        // remove keychain entry for share
        if let username = _shares[index].username {
            let pwm = KeychainManager()
            do {
                Logger.shareManager.debug("trying to remove keychain entry for \(self._shares[index].networkShare, privacy: .public) with username: \(username, privacy: .public)")
                try pwm.removeCredential(forShare: URL(string: self._shares[index].networkShare)!, withUsername: username)
            } catch {
                Logger.shareManager.error("🛑 Cannot remove keychain entry for share \(self._shares[index].networkShare, privacy: .public)")
            }
        }
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
    func updateShare(at index: Int, withUpdatedShare updatedShare: Share) throws {
        os_unfair_lock_lock(&sharesLock)
        guard index >= 0 && index < _shares.count else {
            os_unfair_lock_unlock(&sharesLock)
            throw ShareError.invalidIndex(index)
        }
        //
        // remove existing keychain entry first since it wouldn't be found with the new data
        if let username = _shares[index].username {
            let pwm = KeychainManager()
            do {
                try pwm.removeCredential(forShare: URL(string: _shares[index].networkShare)!, withUsername: username)
            } catch {
            }
        }
        //
        // save password in keychain
        if let password = updatedShare.password {
            if let username = updatedShare.username {
                let pwm = KeychainManager()
                do {
                    try pwm.saveCredential(forShare: URL(string: updatedShare.networkShare)!, withUsername: username, andPassword: password)
                } catch {
                }
            }
        }
        _shares[index] = updatedShare
        os_unfair_lock_unlock(&sharesLock)
    }
    
    /// Update the mount status of a share at a specific index
    /// - Parameters:
    ///   - index: The index of the share to update
    ///   - newMountStatus: The new mount status to set
    func updateMountStatus(at index: Int, to newMountStatus: MountStatus) throws {
        os_unfair_lock_lock(&sharesLock)
        defer { os_unfair_lock_unlock(&sharesLock) }
        
        guard index >= 0 && index < _shares.count else {
            throw ShareError.invalidIndex(index)
        }
        _shares[index].updateMountStatus(to: newMountStatus)
    }
    
    /// Update the mountPoint of a share at a specific index
    /// - Parameters:
    ///   - index: The index of the share to update
    ///   - mountPoint: The mount point where the share should be mounted
    func updateMountPoint(at index: Int, to mountPoint: String?) throws {
        os_unfair_lock_lock(&sharesLock)
        defer { os_unfair_lock_unlock(&sharesLock) }
        
        guard index >= 0 && index < _shares.count else {
            throw ShareError.invalidIndex(index)
        }
        _shares[index].updateMountPoint(to: mountPoint)
    }
    
    /// Update the actual used mountPoint of a share at a specific index
    /// - Parameters:
    ///   - index: The index of the share to update
    ///   - actualMountPoint: The mount point where the share is mounted
    func updateActualMountPoint(at index: Int, to actualMountPoint: String?) throws {
        os_unfair_lock_lock(&sharesLock)
        defer { os_unfair_lock_unlock(&sharesLock) }
        
        guard index >= 0 && index < _shares.count else {
            throw ShareError.invalidIndex(index)
        }
        _shares[index].updateActualMountPoint(to: actualMountPoint)
    }
    
    /// read dictionary of string containig definitions for the share to be mounted
    /// - Parameter forShare shareElement: Array of String dictionary `[String:String]`
    /// - Returns: optional `Share?` element
    func getMDMShareConfig(forShare shareElement: [String:String]) -> Share? {
        guard let shareUrlString = shareElement[Defaults.networkShare] else {
            return nil
        }
        //
        // check if there is a mdm defined username. If so, replace possible occurencies of %USERNAME% with that
        var userName: String = ""
        if let username = shareElement[Defaults.username] {
            userName = username.replacingOccurrences(of: "%USERNAME%", with: NSUserName())
            userName = NSString(string: userName).expandingTildeInPath
        }
        
        //
        // replace possible %USERNAME occurencies with local username - must be the same as directory service username!
        let shareRectified = shareUrlString.replacingOccurrences(of: "%USERNAME%", with: NSUserName())
        let shareAuthType = AuthType(rawValue: shareElement[Defaults.authType] ?? AuthType.krb.rawValue) ?? AuthType.krb
        var password: String?
        var mountStatus = MountStatus.unmounted
        if shareAuthType == AuthType.pwd {
            do {
                if let keychainPassword = try KeychainManager().retrievePassword(forShare: URL(string: shareRectified)!, withUsername: userName) {
                    password = keychainPassword
                }
            } catch {
                Logger.shareManager.warning("Password for share \(shareRectified, privacy: .public) not found in user's keychain")
                mountStatus = MountStatus.missingPassword
                password = nil
            }
        }
        
        let newShare = Share.createShare(networkShare: shareRectified, 
                                         authType: shareAuthType,
                                         mountStatus: mountStatus,
                                         username: userName,
                                         password: password,
                                         mountPoint: shareElement[Defaults.mountPoint],
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
        guard let shareUrlString = shareElement[Defaults.networkShare] else {
            return nil
        }
        var password: String?
        var mountStatus = MountStatus.unmounted
        if let username = shareElement[Defaults.username] {
            do {
                if let keychainPassword = try KeychainManager().retrievePassword(forShare: URL(string: shareUrlString)!, withUsername: username) {
                    password = keychainPassword
                }
            } catch {
                Logger.shareManager.warning("Password for share \(shareUrlString, privacy: .public) not found in user's keychain")
                mountStatus = MountStatus.missingPassword
                password = nil
            }
        }
        let shareAuthType = AuthType(rawValue: shareElement[Defaults.authType] ?? AuthType.krb.rawValue) ?? AuthType.krb
        let newShare = Share.createShare(networkShare: shareUrlString, authType: shareAuthType, mountStatus: mountStatus, username: shareElement[Defaults.username], password: password, managed: false)
        return(newShare)
    }
    
    func updateShareArray() {
        // read MDM shares
        var usedNewMDMprofile = false
        Logger.shareManager.debug("📜 Checking possible changes in MDM profile")
        if let sharesDict = userDefaults.array(forKey: Defaults.managedNetworkSharesKey) as? [[String: String]], !sharesDict.isEmpty {
            var newShares: [Share] = []
            for shareElement in sharesDict {
                if var newShare = self.getMDMShareConfig(forShare: shareElement) {
                    usedNewMDMprofile = true
                    // check if share exists and if not, add it to array of shares
                    // addShare() would check if an element exists and skips it,
                    // but the new share definition could differ from the new one get from MDM
                    if !allShares.contains(where: { $0.networkShare == newShare.networkShare }) {
                        Logger.shareManager.debug(" ▶︎ Reading MDM profile: adding new share \(newShare.networkShare, privacy: .public)")
                        addShare(newShare)
                    } else {
                        if let index = allShares.firstIndex(where: { $0.networkShare == newShare.networkShare }) {
                            // save some stati from actual share element and save them to new share
                            // read from MDM. Then overwrite the share with the new data
                            Logger.shareManager.debug(" ▶︎ Reading MDM profile: updating status for existing share \(newShare.networkShare, privacy: .public).")
                            newShare.mountStatus = allShares[index].mountStatus
                            newShare.id = allShares[index].id
                            newShare.actualMountPoint  = allShares[index].actualMountPoint
                            do {
                                try updateShare(at: index, withUpdatedShare: newShare)
                            } catch ShareError.invalidIndex(let index) {
                                Logger.shareManager.error(" ▶︎ Reading MDM profile: could not update share \(newShare.networkShare, privacy: .public), index \(index, privacy: .public) is not valid.")
                            } catch {
                                Logger.shareManager.error(" ▶︎ Reading MDM profile: could not update share \(newShare.networkShare, privacy: .public), unknown error.")
                            }
                        }
                    }
                    newShares.append(newShare)
                }
            }
            // get the difference between _shares and the new share read from MDM
            let differing = _shares.filter { _shares in
                !newShares.contains { newShares in
                    _shares.networkShare == newShares.networkShare
                }
            }
            // remove found shares
            for remove in differing {
                if let index = allShares.firstIndex(where: { $0.networkShare == remove.networkShare }) {
                    if _shares[index].managed == true {
                        Logger.shareManager.debug(" ▶︎ Reading MDM profile: deleting share \(remove.networkShare, privacy: .public) at Index \(index, privacy: .public)")
                        removeShare(at: index)
                    }
                }
            }
        }
        if !usedNewMDMprofile {
            // the same as above with the legacy MDM profiles
            if let nwShares: [String] = userDefaults.array(forKey: Defaults.networkSharesKey) as? [String], !nwShares.isEmpty {
                var newShares: [Share] = []
                for share in nwShares {
                    if var newShare = self.getLegacyShareConfig(forShare: share) {
                        usedNewMDMprofile = true
                        // check if share exists and if not, add it to array of shares
                        // addShare() would check if an element exists and skips it,
                        // but the new share definition could differ from the new one get from MDM
                        if !allShares.contains(where: { $0.networkShare == newShare.networkShare }) {
                            addShare(newShare)
                            newShares.append(newShare)
                        } else {
                            if let index = allShares.firstIndex(where: { $0.networkShare == newShare.networkShare }) {
                                // save some stati from actual share element and save them to new share
                                // read from MDM. Then overwrite the share with the new data
                                newShare.mountStatus = allShares[index].mountStatus
                                newShare.id = allShares[index].id
                                newShare.actualMountPoint  = allShares[index].actualMountPoint
                                do {
                                    try updateShare(at: index, withUpdatedShare: newShare)
                                } catch ShareError.invalidIndex(let index) {
                                    Logger.shareManager.error(" ▶︎ Reading MDM profile: could not update share \(newShare.networkShare, privacy: .public), index \(index, privacy: .public) is not valid.")
                                } catch {
                                    Logger.shareManager.error(" ▶︎ Reading MDM profile: could not update share \(newShare.networkShare, privacy: .public), unknown error.")
                                }
                                newShares.append(newShare)
                            }
                        }
                    }
                }
                // get the difference between _shares and the new share read from MDM
                let differing = _shares.filter { _shares in
                    !newShares.contains { newShares in
                        _shares.networkShare == newShares.networkShare
                    }
                }
                // remove found shares
                for remove in differing {
                    if let index = allShares.firstIndex(where: { $0.networkShare == remove.networkShare }) {
                        if _shares[index].managed == true {
                            Logger.shareManager.info(" ▶︎ Reading MDM profile: deleting share: \(remove.networkShare, privacy: .public) at Index \(index, privacy: .public)")
                            removeShare(at: index)
                        }
                    }
                }
            }
        }
    }
    
    /// create an array from values configured in UserDefaults
    /// import configured shares from userDefaults for both mdm defined (legacy)`Settings.networkSharesKey`
    /// or `Settings.mdmNetworkSahresKey` and user defined `Settings.customSharesKey`.
    func createShareArray() {
        /// **Important**:
        /// - read only `Settings.mdmNetworkSahresKey` *OR* `Settings.networkSharesKey`, NOT both arrays
        /// - then read user defined `Settings.customSharesKey`
        ///
        var usedNewMDMprofile = false
        if let sharesDict = userDefaults.array(forKey: Defaults.managedNetworkSharesKey) as? [[String: String]], !sharesDict.isEmpty {
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
            if let nwShares: [String] = userDefaults.array(forKey: Defaults.networkSharesKey) as? [String], !nwShares.isEmpty {
                for share in nwShares {
                    if let newShare = self.getLegacyShareConfig(forShare: share) {
                        addShare(newShare)
                    }
                }
            }
        }
        /// next look if there are some user-defined shares to import
        if let privSharesDict = userDefaults.array(forKey: Defaults.userNetworkShares) as? [[String: String]], !privSharesDict.isEmpty {
            for share in privSharesDict {
                if let newShare = self.getUserShareConfigs(forShare: share) {
                    addShare(newShare)
                }
            }
        }
        /// at last there may be legacy user defined share definitions
        else if let nwShares: [String] = userDefaults.array(forKey: Defaults.customSharesKey) as? [String], !nwShares.isEmpty {
            for share in nwShares {
                addShare(Share.createShare(networkShare: share, authType: AuthType.krb, mountStatus: MountStatus.unmounted, managed: false))
            }
            removeLegacyShareConfigs()
        }
    }
    
    /// write user defined share configuration
    /// - Parameter forShare shareElement: an array of a dictionary (key-value) containing the share definitions
    func saveModifiedShareConfigs() {
        var userDefaultsConfigs: [[String: String]] = []
        
        
        for share in _shares {
            //
            // save non-managed shares in userconfig
            if share.managed == false {
                var shareConfig: [String: String] = [:]
                
                shareConfig[Defaults.networkShare] = share.networkShare
                
                shareConfig[Defaults.authType] = share.authType.rawValue
                shareConfig[Defaults.username] = share.username
                if let mountPoint = share.mountPoint {
                    shareConfig[Defaults.mountPoint] = mountPoint
                }
                if let username = share.username {
                    shareConfig[Defaults.username] = username
                }
                // shareConfig[Settings.location] = share.location
                userDefaultsConfigs.append(shareConfig)
            }
        }
        userDefaults.set(userDefaultsConfigs, forKey: Defaults.userNetworkShares)
        userDefaults.synchronize()
    }
    
    private func removeLegacyShareConfigs() {
        userDefaults.removeObject(forKey: Defaults.customSharesKey)
        userDefaults.synchronize()
    }

}
