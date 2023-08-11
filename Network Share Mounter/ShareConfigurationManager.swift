//
//  ShareConfigurationManager.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 10.08.23.
//  Copyright © 2023 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation

struct ShareConfigurationManager {
    
    /// convenience variable for `UserDefaults.standard`
    private let userDefaults = UserDefaults.standard
    
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
    
    func getUserShareConfigs() {
        for shareElement in sharesDict {
            guard let shareUrlString = shareElement[Settings.networkShare] else {
                continue
            }
            guard let shareURL = URL(string: shareUrlString) else {
                continue
            }
            let shareAuthType = AuthType(rawValue: shareElement[Settings.authType] ?? AuthType.krb.rawValue) ?? AuthType.krb
            let newShare = Share.createShare(networkShare: shareURL, authType: shareAuthType, mountStatus: MountStatus.unmounted, username: shareElement[Settings.username])
            addShareIfNotDuplicate(newShare)
        }
        // maybe even here we may have legacy user defined share definitions
        if let nwShares: [String] = userDefaults.array(forKey: Settings.customSharesKey) as? [String] {
            for share in nwShares {
                guard let shareURL = URL(string: share) else {
                    continue
                }
                let newShare = Share.createShare(networkShare: shareURL, authType: AuthType.krb, mountStatus: MountStatus.unmounted)
                addShareIfNotDuplicate(newShare)
            }
        }
    }
    
    /// TODO:
    /// - read obsolte MDM configs
    /// - read modern mdm configs
    /// - read user configs
    /// - save userConfigs
    /// - see if there is a user home directory provided by AD
    ///
    /// From "Mounter":
    /// create an array from values configured in UserDefaults
    /// import configured shares from userDefaults for both mdm defined (legacy)`Settings.networkSharesKey`
    /// or `Settings.mdmNetworkSahresKey` und user defined `Settings.customSharesKey`.
    ///
    /// **Imprtant**:
    /// - read only `Settings.mdmNetworkSahresKey` *OR* `Settings.networkSharesKey`, not both arays
    /// - then read user defined `Settings.customSharesKey`
    ///
    /// first look if we have mdm share definitions
//    if let sharesDict = userDefaults.array(forKey: Settings.managedNetworkSharesKey) as? [[String: String]] {
//        
//    } else if let nwShares: [String] = userDefaults.array(forKey: Settings.networkSharesKey) as? [String] {
//
//    }
//    // finally get shares defined by the user
//    if let sharesDict = userDefaults.array(forKey: Settings.customSharesKey) as? [[String: String]] {
//
//    }
//    // maybe even here we may have legacy user defined share definitions
//    if let nwShares: [String] = userDefaults.array(forKey: Settings.customSharesKey) as? [String] {
//        for share in nwShares {
//            guard let shareURL = URL(string: share) else {
//                continue
//            }
//            let newShare = Share.createShare(networkShare: shareURL, authType: AuthType.krb, mountStatus: MountStatus.unmounted)
//            addShareIfNotDuplicate(newShare)
//        }
//    }
    func importConfiguredShares() {
        var importedShares: [Share]
        /// first look if we have mdm share definitions
        if let sharesDict = userDefaults.array(forKey: Settings.managedNetworkSharesKey) as? [[String: String]] {
            for shareElement in sharesDict {
                if let newShare = getMDMShareConfig(forShare: shareElement) {
                    importedShares.append(newShare)
                }
            }
        } else if let nwShares: [String] = userDefaults.array(forKey: Settings.networkSharesKey) as? [String] {
            for share in nwShares {
                if let newShare = getLegacyShareConfig(forShare: share) {
                    importedShares.append(newShare)
                }
            }
        }
    }
}
