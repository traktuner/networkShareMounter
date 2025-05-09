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

/// Constants specific to FAU (Friedrich-Alexander-Universität) authentication
struct FAU {
    /// Service name for FAU IdM keychain entries
    static let keyChainServiceFAUIdM = "FAU IdM account"
    
    /// Comment for keychain entries
    static let keyChainComment = "FAU IdM credentials for Kerberos ticket management"
    
    /// Kerberos realm for FAU (intentionally lowercase)
    static let kerberosRealm = "fauad.fau.de"
    
    /// Logo image name for authentication dialogs
    static let authenticationDialogImage = "FAUMac_Logo_512"
}

/// Errors that can occur during migration processes
enum MigrationError: Error, LocalizedError {
    case keychainAccessFailed
    case migrationFailed
    
    var errorDescription: String? {
        switch self {
        case .keychainAccessFailed:
            return "Failed to access keychain entries"
        case .migrationFailed:
            return "Migration of user account failed"
        }
    }
}

/// Manages migration of user accounts from legacy format to new format
class Migrator: dogeADUserSessionDelegate {
    /// Current authentication session
    var session: dogeADSession?
    
    /// Access to user preferences
    var prefs = PreferenceManager()
    
    /// Shared accounts manager
    let accountsManager = AccountsManager.shared
    
    /// Called when authentication succeeds
    /// 
    /// Switches to the authenticated Kerberos principal and posts a notification
    func dogeADAuthenticationSucceded() async {
        guard let principal = self.session?.userPrincipal else {
            Logger.FAU.error("Authentication succeeded but userPrincipal is nil")
            return
        }
        
        do {
            let result = try await cliTask("/usr/bin/kswitch -p \(principal)")
            Logger.login.debug("Principal switch result: \(result, privacy: .public)")
        } catch {
            Logger.login.error("Failed to switch principal: \(error.localizedDescription, privacy: .public)")
            // Continue despite error, as authentication still succeeded
        }
        
        NotificationCenter.default.post(
            name: .nsmNotification,
            object: nil,
            userInfo: ["krbAuthenticated": MounterError.krbAuthSuccessful]
        )
        
        await session?.userInfo()
    }
    
    /// Called when authentication fails
    ///
    /// - Parameters:
    ///   - error: The error that occurred during authentication
    ///   - description: Description of the error
    func dogeADAuthenticationFailed(error: dogeADAuth.dogeADSessionError, description: String) {
        Logger.FAU.error("Authentication failed after FAU user migration: \(description, privacy: .public)")
    }
    
    /// Called when user information is retrieved
    ///
    /// - Parameter user: The retrieved user record
    func dogeADUserInformation(user: dogeADAuth.ADUserRecord) {
        Logger.FAU.debug("User information received for: \(user.userPrincipal, privacy: .public)")
    }
    
    /// Migrates legacy keychain entries to the new format
    ///
    /// This method retrieves existing keychain entries from Prefix Assistant,
    /// creates a new user account, and initiates Kerberos authentication.
    func migrate() async {
        Logger.FAU.debug("Starting migration of FAU user accounts")
        
        let keyUtil = KeychainManager()
        
        do {
            // Get existing prefix assistant keychain entries
            let keyChainEntries = try keyUtil.retrieveAllEntries(
                forService: FAU.keyChainServiceFAUIdM,
                accessGroup: Defaults.keyChainAccessGroup
            )
            
            guard let firstAccount = keyChainEntries.first else {
                Logger.FAU.notice("No accounts found to migrate")
                return
            }
            
            // Migrate the keychain entry
            let migrationSuccessful = await migrateKeychainEntry(
                forUsername: firstAccount.username,
                andPassword: firstAccount.password,
                toRealm: FAU.kerberosRealm
            )
            
            if migrationSuccessful {
                // Create new DogeAccount
                let upn = firstAccount.username + "@" + FAU.kerberosRealm
                let newAccount = DogeAccount(
                    displayName: firstAccount.username,
                    upn: upn,
                    hasKeychainEntry: true
                )
                
                await accountsManager.addAccount(account: newAccount)
                
                // Start Kerberos authentication
                self.session = dogeADSession(domain: FAU.kerberosRealm, user: upn)
                self.session?.setupSessionFromPrefs(prefs: prefs)
                self.session?.userPass = firstAccount.password
                self.session?.delegate = self
                
                await self.session?.authenticate()
                Logger.FAU.info("FAU user migrated, NSM account created and authenticated")
            } else {
                Logger.FAU.error("FAU user migration failed")
            }
        } catch {
            Logger.FAU.error("Keychain access failed: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    /// Migrates a keychain entry by adding the Kerberos realm and saving to a new entry
    ///
    /// - Parameters:
    ///   - forUsername: Login username for share
    ///   - andPassword: Password for the account
    ///   - toRealm: Kerberos realm to append (defaults to FAU.kerberosRealm)
    /// - Returns: Whether migration was successful
    func migrateKeychainEntry(
        forUsername: String,
        andPassword pass: String,
        toRealm realm: String = FAU.kerberosRealm
    ) async -> Bool {
        let pwm = KeychainManager()
        var userName = forUsername.removeDomain()
        
        userName.appendDomain(domain: realm.lowercased())
        
        do {
            try pwm.saveCredential(
                forUsername: userName,
                andPassword: pass,
                withService: Defaults.keyChainService,
                accessGroup: Defaults.keyChainAccessGroup,
                comment: "FAU IdM Kerberos Account for Network Share Mounter"
            )
            
            Logger.FAU.debug("Prefix Assistant keychain entry migration for user \(userName, privacy: .public) completed")
            prefs.set(for: .keyChainPrefixManagerMigration, value: true)
            
            NotificationCenter.default.post(
                name: .nsmNotification,
                object: nil,
                userInfo: ["ClearError": MounterError.noError]
            )
            
            return true
        } catch {
            Logger.FAU.error("Could not save migrated keychain entry: \(error.localizedDescription, privacy: .public)")
            Logger.FAU.error("...but setting migration flag anyway")
            prefs.set(for: .keyChainPrefixManagerMigration, value: true)
            return false
        }
    }
}

