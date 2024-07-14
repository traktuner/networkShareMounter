//
//  FAUconstants.swift
//  Network Share Mounter
//
//  Created by Gregor Longariva on 24.01.23.
//  Copyright © 2024 RRZE. All rights reserved.
//

import Foundation
import OSLog
import dogeADAuth

struct FAU {
    static let keyChainServiceFAUIdM = "FAU IdM account"
    static let keyChainComment = "FAU IdM credentials for Kerberos ticket management"
    static let kerberosRealm = "fauad.fau.de"  // this is intentiopnally set to lowercase
    static let authenticationDialogImage = "FAUMac_Logo_512"
}

class Migrator: dogeADUserSessionDelegate {
    var session: dogeADSession?
    var prefs = PreferenceManager()
    let accountsManager = AccountsManager.shared
    
    func dogeADAuthenticationSucceded() async {
        do {
            _ = try await cliTask("kswitch -p \(String(describing: self.session?.userPrincipal))")
        } catch {
            Logger.FAU.error("kswitch -p failed: \(error.localizedDescription)")
        }
        NotificationCenter.default.post(name: .nsmNotification, object: nil, userInfo: ["krbAuthenticated": MounterError.krbAuthSuccessful])
        await session?.userInfo()
    }
    
    func dogeADAuthenticationFailed(error: dogeADAuth.dogeADSessionError, description: String) {
        Logger.FAU.debug("Auth failed after FAU user migration, \(description, privacy: .public)")
    }
    
    func dogeADUserInformation(user: dogeADAuth.ADUserRecord) {
        Logger.FAU.debug("User info: \(user.userPrincipal, privacy: .public)")
    }
    
    /// get keychain entry, create new user and start kerberos authentication
    func migrate() async {
        do {
            // get existing prefix assistant keychain entry
            let keyUtil = KeychainManager()
            let keyChainEntries = try keyUtil.retrieveAllEntries(forService: FAU.keyChainServiceFAUIdM, accessGroup: Defaults.keyChainAccessGroup)
            // use the first found entry (should also be the only one)
            if let firstAccount = keyChainEntries.first {
                // call the keychain migration
                if migrateKeychainEntry(forUsername: firstAccount.username, andPassword: firstAccount.password, toRealm: FAU.kerberosRealm) {
                    // create new DogeAccount (at FAU the migrated account will always stored in keychain)
                    let newAccount = DogeAccount(displayName: firstAccount.username, upn: firstAccount.username + "@" + FAU.kerberosRealm, hasKeychainEntry: true)
                    await accountsManager.addAccount(account: newAccount)
                    // start kerberos authentication
                    self.session = dogeADSession.init(domain: FAU.kerberosRealm, user: firstAccount.username + "@" + FAU.kerberosRealm)
                    self.session?.setupSessionFromPrefs(prefs: prefs)
                    self.session?.userPass = firstAccount.password
                    self.session?.delegate = self
                    await self.session?.authenticate()
                    Logger.FAU.debug("FAU user migrated, NSM account created and authenticated.")
                } else {
                    Logger.FAU.debug("FAU user migration failed.")
                }
            }
        } catch {
            Logger.FAU.error("Keychain access failed, FAU user migration failed.")
        }
    }
    
    /// retrieve keychain entry for a given userName, append kerberos realm and save into
    /// a new keychain entry
    /// - Parameter forUsername: ``username`` login for share
    /// - Parameter toRealm: ``realm`` kerberos realm appended to userName (defaults to FAU.kerberosRealm
    func migrateKeychainEntry(forUsername: String, andPassword pass: String, toRealm realm: String = FAU.kerberosRealm) -> Bool {
        let pwm = KeychainManager()
        var userName = forUsername.removeDomain()
        do {
            userName.appendDomain(domain: realm.lowercased())
            try pwm.saveCredential(forUsername: userName,
                                   andPassword: pass,
                                   withService: Defaults.keyChainService,
                                   accessGroup: Defaults.keyChainAccessGroup,
                                   comment: "FAU IdM Kerberos Account for Network Share Mounter")
            Logger.FAU.debug("Prefix Assistant keychain entry migration for user \(userName, privacy: .public) done")
            prefs.set(for: .keyChainPrefixManagerMigration, value: true)
            NotificationCenter.default.post(name: .nsmNotification, object: nil, userInfo: ["ClearError": MounterError.noError])
            return true
        } catch {
            Logger.FAU.error("Could not save Prefix Assistant migrated keychain entry for user: \(userName, privacy: .public)")
            return false
        }
    }
}

