//
//  FAUconstants.swift
//  Network Share Mounter
//
//  Created by Gregor Longariva on 24.01.23.
//  Copyright © 2024 RRZE. All rights reserved.
//

import Foundation
import OSLog

struct FAU {
    static let keyChainServiceFAUIdM = "FAU IdM account"
    static let keyChainComment = "FAU IdM credentials for Kerberos ticket management"
    static let kerberosRealm = "fauad.fau.de"  // this is intentiopnally set to lowercase
    static let authenticationDialogImage = "FAUMac_Logo_512"
}

struct Migrator {
    var prefs = PreferenceManager()
    
    /// retrieve keychain entry for a given userName, append kerberos realm and save into
    /// a new keychain entry
    /// - Parameter forUsername: ``username`` login for share
    /// - Parameter toRealm: ``realm`` kerberos realm appended to userName (defaults to FAU.kerberosRealm
    func migrateKeychainEntry(forUsername: String, toRealm realm: String = FAU.kerberosRealm) -> Bool {
        let pwm = KeychainManager()
        var userName = forUsername.removeDomain()
        do {
            if let pass = try pwm.retrievePassword(forUsername: userName, andService: FAU.keyChainServiceFAUIdM, accessGroup: Defaults.keyChainAccessGroup, iCloudSync: true) {
                do {
                    userName.appendDomain(domain: realm.lowercased())
                    try pwm.saveCredential(forUsername: userName, 
                                           andPassword: pass,
                                           withService: Defaults.keyChainService,
                                           accessGroup: Defaults.keyChainAccessGroup,
                                           comment: "FAU IdM Kerberos Account for Network Share Mounter")
                    Logger.FAU.debug("Prefix Assistant keychain entry migration for user \(userName, privacy: .public) done")
                    prefs.set(for: .keyChainPrefixManagerMigration, value: true)
                    NotificationCenter.default.post(name: .nsmNotification, object: nil, userInfo: ["ClearError": MounterError.authenticationError])
                    return true
                } catch {
                    Logger.FAU.error("Could not save Prefix Assistant migrated keychain entry for user: \(userName, privacy: .public)")
                    return false
                }
            }
        } catch {
            Logger.FAU.warning("Unable to find Prefix Assistant keychain item for user \(userName, privacy: .public), no migration done")
            prefs.set(for: .keyChainPrefixManagerMigration, value: true)
            return false
        }
        return false
    }
}

