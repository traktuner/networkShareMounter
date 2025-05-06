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
    case invalidURL(String)
}

/// class `ShareManager` to manage the shares (array fo Share)
actor ShareManager {
    private var _shares: [Share] = []
    private let userDefaults = UserDefaults.standard
    private var prefs = PreferenceManager()
    
    /// Add a share
    func addShare(_ share: Share) {
        if !allShares.contains(where: { $0.networkShare == share.networkShare }) {
            _shares.append(share)
            //
            // save password in keychain
            if let password = share.password, let username = share.username {
                savePasswordToKeychain(for: share.networkShare, username: username, password: password)
            }
        }
    }
    
    /// Saves a password to the keychain for a share
    /// - Parameters:
    ///   - shareURL: The network share URL string
    ///   - username: The username for authentication
    ///   - password: The password to save
    private func savePasswordToKeychain(for shareURL: String, username: String, password: String) {
        let pwm = KeychainManager()
        guard let url = URL(string: shareURL) else {
            Logger.shareManager.error("🛑 Cannot create URL from share path: \(shareURL, privacy: .public)")
            return
        }
        
        do {
            try pwm.saveCredential(forShare: url, withUsername: username, andPassword: password)
        } catch {
            Logger.shareManager.error("🛑 Cannot store password for share \(shareURL, privacy: .public) in user's keychain: \(error.localizedDescription)")
        }
    }
    
    /// Remove a share at a specific index
    func removeShare(at index: Int) {
        // remove keychain entry for share
        if let username = _shares[index].username {
            removePasswordFromKeychain(for: _shares[index].networkShare, username: username)
        }
        _shares.remove(at: index)
    }
    
    /// Removes a password from the keychain for a share
    /// - Parameters:
    ///   - shareURL: The network share URL string
    ///   - username: The username for authentication
    private func removePasswordFromKeychain(for shareURL: String, username: String) {
        let pwm = KeychainManager()
        guard let url = URL(string: shareURL) else {
            Logger.shareManager.error("🛑 Cannot create URL from share path: \(shareURL, privacy: .public)")
            return
        }
        
        do {
            Logger.shareManager.debug("Trying to remove keychain entry for \(shareURL, privacy: .public) with username: \(username, privacy: .public)")
            try pwm.removeCredential(forShare: url, withUsername: username)
        } catch {
            Logger.shareManager.error("🛑 Cannot remove keychain entry for share \(shareURL, privacy: .public): \(error.localizedDescription)")
        }
    }
    
    /// Get all shares
    var allShares: [Share] {
        return _shares
    }
    
    /// delete all shares, delete array entries is not already empty
    func removeAllShares() {
        if !_shares.isEmpty {
            _shares.removeAll()
        }
    }
    
    /// Update a share at a specific index
    func updateShare(at index: Int, withUpdatedShare updatedShare: Share) throws {
        guard index >= 0 && index < _shares.count else {
            throw ShareError.invalidIndex(index)
        }
        //
        // remove existing keychain entry first since it wouldn't be found with the new data
        if let username = _shares[index].username {
            removePasswordFromKeychain(for: _shares[index].networkShare, username: username)
        }
        //
        // save password in keychain
        if let password = updatedShare.password, let username = updatedShare.username {
            savePasswordToKeychain(for: updatedShare.networkShare, username: username, password: password)
        }
        _shares[index] = updatedShare
    }
    
    /// Update the mount status of a share at a specific index
    /// - Parameters:
    ///   - index: The index of the share to update
    ///   - newMountStatus: The new mount status to set
    func updateMountStatus(at index: Int, to newMountStatus: MountStatus) throws {
        
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
        
        guard index >= 0 && index < _shares.count else {
            throw ShareError.invalidIndex(index)
        }
        _shares[index].updateActualMountPoint(to: actualMountPoint)
    }
    
    /// Creates and configures a Share object based on MDM configuration dictionary
    /// - Parameter shareElement: Dictionary containing share configuration from MDM
    /// - Returns: Configured Share object or nil if required network share URL is missing
    /// - Note: Handles username resolution, password retrieval from keychain, and share URL expansion
    func getMDMShareConfig(forShare shareElement: [String:String]) -> Share? {
        // Extract network share URL, return nil if not found
        guard let shareUrlString = shareElement[Defaults.networkShare] else {
            Logger.shareManager.error("❌ MDM Config: Missing 'networkShare' key in share element: \(shareElement, privacy: .public)")
            return nil
        }

        // Log received MDM share element data
        let logAuthType = shareElement[Defaults.authType] ?? "(default: krb)"
        let logUsername = shareElement[Defaults.username] ?? "(not set)"
        let logMountPoint = shareElement[Defaults.mountPoint] ?? "(not set)"
        Logger.shareManager.debug("⚙️ Processing MDM Share Config: URL=\(shareUrlString, privacy: .public), Auth=\(logAuthType, privacy: .public), User=\(logUsername, privacy: .public), MountPoint=\(logMountPoint, privacy: .public)")

        // Determine username with following priority:
        // 1. Username override from preferences
        // 2. Username from share configuration dictionary
        // 3. Local system username
        let userName: String
        if let username = prefs.string(for: .usernameOverride) {
            // Hinzugefügtes Logging:
            Logger.shareManager.debug("📝 Setting username via usernameOverride and PreferenceManager: \(username, privacy: .public)")
            userName = username
        } else if let username = shareElement[Defaults.username] {
            Logger.shareManager.debug("📝 Setting username via usernameOverride and shareElement: \(username, privacy: .public)")
            userName = username
        } else {
            userName = NSUserName()
            Logger.shareManager.debug("📝 Setting username to local system username: \(userName, privacy: .public)")
        }
        
        // Replace username placeholder in share URL
        let shareRectified = shareUrlString.replacingOccurrences(of: "%USERNAME%", with: userName)
        
        // Configure authentication type, defaulting to Kerberos if not specified
        let shareAuthType = AuthType(rawValue: shareElement[Defaults.authType] ?? AuthType.krb.rawValue) ?? AuthType.krb
        var password: String?
        var mountStatus = MountStatus.unmounted
        
        // For password authentication, attempt to retrieve from keychain
        if shareAuthType == AuthType.pwd {
            guard let url = URL(string: shareRectified) else {
                Logger.shareManager.error("🛑 Invalid share URL: \(shareRectified, privacy: .public)")
                return nil
            }
            
            do {
                if let keychainPassword = try KeychainManager().retrievePassword(forShare: url, withUsername: userName) {
                    password = keychainPassword
                }
            } catch {
                // Log warning if password retrieval fails and update mount status
                Logger.shareManager.warning("Password for share \(shareRectified, privacy: .public) not found in user's keychain: \(error.localizedDescription)")
                mountStatus = MountStatus.missingPassword
                password = nil
            }
        }
        
        // Create and return new Share object with configured parameters
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
            guard let url = URL(string: shareUrlString) else {
                Logger.shareManager.error("🛑 Invalid share URL: \(shareUrlString, privacy: .public)")
                return nil
            }
            
            do {
                if let keychainPassword = try KeychainManager().retrievePassword(forShare: url, withUsername: username) {
                    password = keychainPassword
                }
            } catch {
                Logger.shareManager.warning("Password for share \(shareUrlString, privacy: .public) not found in user's keychain: \(error.localizedDescription)")
                mountStatus = MountStatus.missingPassword
                password = nil
            }
        }
        
        let shareAuthType = AuthType(rawValue: shareElement[Defaults.authType] ?? AuthType.krb.rawValue) ?? AuthType.krb
        let mountPoint = shareElement[Defaults.mountPoint]

        let newShare = Share.createShare(
            networkShare: shareUrlString,
            authType: shareAuthType,
            mountStatus: mountStatus,
            username: shareElement[Defaults.username],
            password: password,
            mountPoint: mountPoint,
            managed: false
        )
        return(newShare)
    }
    
    func updateShareArray() {
        // Check for and process MDM shares first
        let processingResult = processMDMShares()
        
        // If no MDM shares were processed, try legacy MDM shares
        if !processingResult.usedNewMDMProfile {
            processingLegacyShares()
        }
    }
    
    /// Processes MDM shares and updates the share array
    /// - Returns: A tuple indicating whether MDM profile was used and the processed shares
    private func processMDMShares() -> (usedNewMDMProfile: Bool, newShares: [Share]) {
        Logger.shareManager.debug("📜 Checking possible changes in MDM profile")
        var usedNewMDMProfile = false
        var newShares: [Share] = []
        
        // Process new MDM profile format if available
        if let sharesDict = userDefaults.array(forKey: Defaults.managedNetworkSharesKey) as? [[String: String]], !sharesDict.isEmpty {
            usedNewMDMProfile = true
            
            for shareElement in sharesDict {
                if let newShare = self.getMDMShareConfig(forShare: shareElement) {
                    processShareForUpdate(newShare: newShare, isManaged: true, into: &newShares)
                }
            }
            
            // Remove managed shares that are no longer in the MDM profile
            removeOrphanedManagedShares(newShares: newShares)
        }
        
        return (usedNewMDMProfile, newShares)
    }
    
    /// Processes legacy shares when no MDM shares are present
    private func processingLegacyShares() {
        var newShares: [Share] = []
        
        if let nwShares: [String] = userDefaults.array(forKey: Defaults.networkSharesKey) as? [String], !nwShares.isEmpty {
            for share in nwShares {
                if let newShare = self.getLegacyShareConfig(forShare: share) {
                    processShareForUpdate(newShare: newShare, isManaged: true, into: &newShares)
                }
            }
            
            // Remove managed shares that are no longer in the legacy configuration
            removeOrphanedManagedShares(newShares: newShares)
        }
    }
    
    /// Processes a share for update, adding it if new or updating existing one
    /// - Parameters:
    ///   - newShare: The share to process
    ///   - isManaged: Whether the share is managed by MDM
    ///   - sharesArray: The array to update with processed shares
    private func processShareForUpdate(newShare: Share, isManaged: Bool, into sharesArray: inout [Share]) {
        // Check if share exists
        if !allShares.contains(where: { $0.networkShare == newShare.networkShare }) {
            Logger.shareManager.debug(" ▶︎ Adding new share \(newShare.networkShare, privacy: .public)")
            addShare(newShare)
        } else {
            if let index = allShares.firstIndex(where: { $0.networkShare == newShare.networkShare }) {
                // Update existing share with new configuration while preserving state
                var updatedShare = newShare
                updatedShare.mountStatus = allShares[index].mountStatus
                updatedShare.id = allShares[index].id
                updatedShare.actualMountPoint = allShares[index].actualMountPoint
                
                do {
                    try updateShare(at: index, withUpdatedShare: updatedShare)
                    Logger.shareManager.debug(" ▶︎ Updated existing share \(newShare.networkShare, privacy: .public)")
                } catch ShareError.invalidIndex(let index) {
                    Logger.shareManager.error(" ▶︎ Could not update share \(newShare.networkShare, privacy: .public), index \(index, privacy: .public) is not valid.")
                } catch {
                    Logger.shareManager.error(" ▶︎ Could not update share \(newShare.networkShare, privacy: .public), error: \(error.localizedDescription)")
                }
            }
        }
        
        sharesArray.append(newShare)
    }
    
    /// Removes managed shares that are no longer present in configuration
    /// - Parameter newShares: The current list of shares from configuration
    private func removeOrphanedManagedShares(newShares: [Share]) {
        // Find shares that are in _shares but not in newShares
        let differing = _shares.filter { share in
            !newShares.contains { newShare in
                share.networkShare == newShare.networkShare
            }
        }
        
        // Remove orphaned managed shares
        for orphanedShare in differing {
            if let index = allShares.firstIndex(where: { $0.networkShare == orphanedShare.networkShare }) {
                if _shares[index].managed == true {
                    Logger.shareManager.debug(" ▶︎ Deleting share \(orphanedShare.networkShare, privacy: .public) at index \(index, privacy: .public)")
                    self.removeShare(at: index)
                }
            }
        }
    }
    
    /// create an array from values configured in UserDefaults
    /// import configured shares from userDefaults for both mdm defined (legacy)`Settings.networkSharesKey`
    /// or `Settings.mdmNetworkSahresKey` and user defined `Settings.customSharesKey`.
    func createShareArray() {
        // Process MDM shares first
        let processingResult = processInitialMDMShares()
        
        // If no MDM shares were found, try legacy MDM configuration
        if !processingResult {
            processInitialLegacyMDMShares()
        }
        
        // Process user-defined shares
        processUserDefinedShares()
    }
    
    /// Processes initial MDM shares during application startup
    /// - Returns: Whether MDM shares were processed
    private func processInitialMDMShares() -> Bool {
        var usedNewMDMProfile = false
        
        if let sharesDict = userDefaults.array(forKey: Defaults.managedNetworkSharesKey) as? [[String: String]], !sharesDict.isEmpty {
            for shareElement in sharesDict {
                if let newShare = self.getMDMShareConfig(forShare: shareElement) {
                    usedNewMDMProfile = true
                    addShare(newShare)
                }
            }
        }
        
        return usedNewMDMProfile
    }
    
    /// Processes legacy MDM shares during application startup
    private func processInitialLegacyMDMShares() {
        if let nwShares: [String] = userDefaults.array(forKey: Defaults.networkSharesKey) as? [String], !nwShares.isEmpty {
            for share in nwShares {
                if let newShare = self.getLegacyShareConfig(forShare: share) {
                    addShare(newShare)
                }
            }
        }
    }
    
    /// Processes user-defined shares during application startup
    private func processUserDefinedShares() {
        // Try new user-defined share format first
        if let privSharesDict = userDefaults.array(forKey: Defaults.userNetworkShares) as? [[String: String]], !privSharesDict.isEmpty {
            for share in privSharesDict {
                if let newShare = self.getUserShareConfigs(forShare: share) {
                    addShare(newShare)
                }
            }
        }
        // Fall back to legacy user-defined share format
        else if let nwShares: [String] = userDefaults.array(forKey: Defaults.customSharesKey) as? [String], !nwShares.isEmpty {
            for share in nwShares {
                addShare(Share.createShare(networkShare: share, authType: AuthType.krb, mountStatus: MountStatus.unmounted, managed: false))
            }
            removeLegacyShareConfigs()
        }
    }
    
    /// function to return all shares
    ///    since the class/actor is now asynchron, there is no way to get _shares directly
    func getAllShares() -> [Share] {
        _shares
    }
    
    /// function returning a bool if shares array is empty or not
    func hasShares() -> Bool {
        return !_shares.isEmpty
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
        // synchronize() is deprecated and unnecessary
    }
    
    private func removeLegacyShareConfigs() {
        userDefaults.removeObject(forKey: Defaults.customSharesKey)
        // synchronize() is deprecated and unnecessary
    }
}
