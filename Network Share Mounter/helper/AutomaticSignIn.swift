//
//  AutomaticSignIn.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 15.12.23.
//  Copyright © 2020 Orchard & Grove, Inc. All rights reserved.
//  Copyright © 2024 RRZE. All rights reserved.
//

import Foundation
import OSLog
import dogeADAuth

/// Possible errors during automatic sign-in
public enum AutoSignInError: Error, LocalizedError {
    case noSRVRecords(String)
    case noActiveTickets
    case keychainAccessFailed(Error)
    case authenticationFailed(String)
    case networkError(String)
    
    public var errorDescription: String? {
        switch self {
        case .noSRVRecords(let domain):
            return "No SRV records found for domain: \(domain)"
        case .noActiveTickets:
            return "No active Kerberos tickets available"
        case .keychainAccessFailed(let error):
            return "Keychain access failed: \(error.localizedDescription)"
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}

/// User session object with authentication information
public struct Doge_SessionUserObject {
    /// User principal (e.g. user@DOMAIN.COM)
    var userPrincipal: String
    /// Active Directory session
    var session: dogeADSession
    /// Indicates if password aging is enabled
    var aging: Bool
    /// Password expiration date, if available
    var expiration: Date?
    /// Remaining days until password expiration
    var daysToGo: Int?
    /// User information from Active Directory
    var userInfo: ADUserRecord?
}

/// Actor for automatic sign-in to Active Directory
/// 
/// Manages automatic sign-ins for multiple accounts
actor AutomaticSignIn {
    /// Shared instance (Singleton)
    static let shared = AutomaticSignIn()
    
    /// Preference Manager for settings
    var prefs = PreferenceManager()
    
    /// Accounts Manager for user account management
    let accountsManager = AccountsManager.shared
    
    /// Private initialization for Singleton pattern
    private init() {}
    
    /// Automatically signs in all relevant accounts
    /// 
    /// Based on settings, either all accounts or only the default account will be signed in.
    func signInAllAccounts() async {
        Logger.automaticSignIn.info("Starting automatic sign-in process")
        
        let klist = KlistUtil()
        // Retrieve all available Kerberos principals
        let principals = await klist.klist().map({ $0.principal })
        let defaultPrinc = await klist.defaultPrincipal
        
        Logger.automaticSignIn.debug("Found principals: \(principals.joined(separator: ", "), privacy: .public)")
        Logger.automaticSignIn.debug("Default principal: \(defaultPrinc ?? "None", privacy: .public)")
        
        // Retrieve accounts and determine sign-in strategy:
        // - If single-user mode is active, only sign in default account
        // - Otherwise sign in all accounts
        let accounts = await accountsManager.accounts
        let accountsCount = accounts.count
        
        for account in accounts {
            if !prefs.bool(for: .singleUserMode) || account.upn == defaultPrinc || accountsCount == 1 {
                Logger.automaticSignIn.info("Automatic sign-in for account: \(account.upn, privacy: .public)")
                let worker = AutomaticSignInWorker(account: account)
                await worker.checkUser()
            }
        }
        
        // Restore default principal
        if let defPrinc = defaultPrinc {
            do {
                let output = try await cliTask("kswitch -p \(defPrinc)")
                Logger.automaticSignIn.debug("kswitch output: \(output, privacy: .public)")
            } catch {
                Logger.automaticSignIn.error("Error switching to default principal: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

/// Worker-Actor for signing in a single account
/// 
/// Implements the delegate methods for dogeADUserSessionDelegate
actor AutomaticSignInWorker: dogeADUserSessionDelegate {
    
    /// Preference Manager for settings
    var prefs = PreferenceManager()
    
    /// The user account to manage
    var account: DogeAccount
    
    /// Active Directory session
    var session: dogeADSession
    
    /// DNS resolver for SRV entries
    var resolver = SRVResolver()
    
    /// The domain of the user account
    let domain: String
    
    /// Initializes a new worker with a user account
    /// 
    /// - Parameter account: The user account for sign-in
    init(account: DogeAccount) {
        self.account = account
        domain = account.upn.userDomain() ?? ""
        self.session = dogeADSession(domain: domain, user: account.upn.user())
        self.session.setupSessionFromPrefs(prefs: prefs)
        
        Logger.automaticSignIn.debug("Worker initialized for user: \(account.upn, privacy: .public), domain: \(self.domain, privacy: .public)")
    }
    
    /// Checks the user and performs sign-in
    /// 
    /// The process includes:
    /// 1. Resolving SRV records for LDAP servers
    /// 2. Checking existing Kerberos tickets
    /// 3. Retrieving user information or authentication
    func checkUser() async {
        let klist = KlistUtil()
        let princs = await klist.klist().map({ $0.principal })
        
        // Resolve SRV records for LDAP
        do {
            let records = try await resolveSRVRecords()
            
            // If SRV records were found and the account has a valid ticket
            if !records.SRVRecords.isEmpty {
                if princs.contains(where: { $0.lowercased() == self.account.upn }) {
                    Logger.automaticSignIn.info("Valid ticket found for: \(self.account.upn, privacy: .public)")
                    await getUserInfo()
                } else {
                    Logger.automaticSignIn.info("No valid ticket found, starting authentication")
                    await auth()
                }
            } else {
                Logger.automaticSignIn.warning("No SRV records found for domain: \(self.domain, privacy: .public)")
                throw AutoSignInError.noSRVRecords(domain)
            }
        } catch {
            Logger.automaticSignIn.error("Error resolving SRV records: \(error.localizedDescription, privacy: .public)")
            // Try authentication despite errors
            await auth()
        }
    }
    
    /// Resolves SRV records for LDAP services
    /// 
    /// - Returns: The found SRV records
    /// - Throws: Error if no records are found
    private func resolveSRVRecords() async throws -> SRVResult {
        // Flag to ensure the continuation is only resumed once
        var continuationResumed = false
        let lock = NSLock() // Use a lock for thread safety

        return try await withCheckedThrowingContinuation { continuation in
            let query = "_ldap._tcp." + domain.lowercased()
            Logger.automaticSignIn.debug("Resolving SRV records for: \(query, privacy: .public)")

            resolver.resolve(query: query) { result in
                lock.lock() // Acquire lock before checking/modifying the flag
                // Check if already resumed
                guard !continuationResumed else {
                    lock.unlock() // Release lock if already resumed
                    Logger.automaticSignIn.warning("Continuation for SRV query '\(query)' already resumed. Ignoring duplicate callback.")
                    return
                }
                // Mark as resumed
                continuationResumed = true
                lock.unlock() // Release lock after modifying the flag

                Logger.automaticSignIn.info("SRV response for: \(query, privacy: .public)")
                switch result {
                case .success(let records):
                    continuation.resume(returning: records)
                case .failure(let error):
                    Logger.automaticSignIn.error("No DNS results for domain \(self.domain, privacy: .public), automatic sign-in not possible. Error: \(error, privacy: .public)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Authenticates the user with keychain credentials
    /// 
    /// Retrieves the password from keychain and starts the authentication process
    func auth() async {
        let keyUtil = KeychainManager()
        
        do {
            // Retrieve password from keychain
            if let pass = try keyUtil.retrievePassword(forUsername: account.upn.lowercaseDomain(), andService: Defaults.keyChainService) {
                Logger.automaticSignIn.debug("Password for \(self.account.upn, privacy: .public) retrieved from keychain")
                account.hasKeychainEntry = true
                session.userPass = pass
                session.delegate = self
                
                // Start authentication
                await session.authenticate()
            } else {
                Logger.automaticSignIn.warning("No password found in keychain for: \(self.account.upn, privacy: .public)")
                account.hasKeychainEntry = false
                NotificationCenter.default.post(name: .nsmNotification, object: nil, userInfo: ["KrbAuthError": MounterError.authenticationError])
            }
        } catch {
            Logger.automaticSignIn.error("Error accessing keychain: \(error.localizedDescription, privacy: .public)")
            account.hasKeychainEntry = false
            NotificationCenter.default.post(name: .nsmNotification, object: nil, userInfo: ["KrbAuthError": MounterError.authenticationError])
        }
    }
    
    /// Retrieves user information from Active Directory
    /// 
    /// Switches to the user principal and retrieves detailed information
    func getUserInfo() async {
        do {
            // Switch to user principal
            let output = try await cliTask("kswitch -p \(session.userPrincipal)")
            Logger.automaticSignIn.debug("kswitch output: \(output, privacy: .public)")
            
            // Retrieve user data
            session.delegate = self
            await session.userInfo()
        } catch {
            Logger.automaticSignIn.error("Error retrieving user information: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    // MARK: - dogeADUserSessionDelegate Methods
    
    /// Called when authentication was successful
    func dogeADAuthenticationSucceded() async {
        Logger.automaticSignIn.info("Authentication successful for: \(self.account.upn, privacy: .public)")
        
        do {
            // Switch to authenticated user
            let output = try await cliTask("kswitch -p \(session.userPrincipal)")
            Logger.automaticSignIn.debug("kswitch output: \(output, privacy: .public)")
            
            // Notify success
            NotificationCenter.default.post(name: .nsmNotification, object: nil, userInfo: ["krbAuthenticated": MounterError.krbAuthSuccessful])
            
            // Retrieve user information
            await session.userInfo()
        } catch {
            Logger.automaticSignIn.error("Error after successful authentication: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    /// Called when authentication failed
    /// 
    /// - Parameters:
    ///   - error: Error type
    ///   - description: Error description
    func dogeADAuthenticationFailed(error: dogeADSessionError, description: String) {
        Logger.automaticSignIn.info("Authentication failed for: \(self.account.upn, privacy: .public), Error: \(description, privacy: .public)")
        
        switch error {
        case .AuthenticationFailure, .PasswordExpired:
            // For authentication errors or expired passwords:
            // - Send notification
            // - Remove incorrect password from keychain
            NotificationCenter.default.post(name: .nsmNotification, object: nil, userInfo: ["KrbAuthError": MounterError.krbAuthenticationError])
            Logger.automaticSignIn.info("Remove invalid password from Keychain")
            
            let keyUtil = KeychainManager()
            do {
                try keyUtil.removeCredential(forUsername: account.upn)
                Logger.automaticSignIn.info("Keychain entry successfully removed.")
            } catch {
                Logger.automaticSignIn.error("Error removing the keychain entry for: \(self.account.upn, privacy: .public), Error: \(error.localizedDescription, privacy: .public)")
            }
            
        case .OffDomain:
            // When outside the Kerberos domain
            Logger.automaticSignIn.info("Outside the Kerberos Realm network")
            NotificationCenter.default.post(name: .nsmNotification, object: nil, userInfo: ["krbOffDomain": MounterError.offDomain])
            
        default:
            Logger.automaticSignIn.warning("Unhandled Authentication Error: \(error, privacy: .public)")
            break
        }
    }
    
    /// Called when user information was successfully retrieved
    /// 
    /// - Parameter user: Retrieved user information
    func dogeADUserInformation(user: ADUserRecord) {
        Logger.automaticSignIn.debug("Retrieve user information for: \(user.userPrincipal, privacy: .public)")
        
        // Save user information in PreferenceManager
        prefs.setADUserInfo(user: user)
    }
}
