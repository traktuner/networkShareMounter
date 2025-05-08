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
        Logger.automaticSignIn.info("🔍 [START] Starting automatic sign-in process")
        
        do {
            let klist = KlistUtil()
            Logger.automaticSignIn.debug("🔍 KlistUtil initialized")
            
            // Retrieve all available Kerberos principals
            let principals = await klist.klist().map({ $0.principal })
            Logger.automaticSignIn.debug("🔍 Retrieved \(principals.count) principals: \(principals.joined(separator: ", "), privacy: .public)")
            
            let defaultPrinc = await klist.defaultPrincipal
            Logger.automaticSignIn.debug("🔍 Default principal: \(defaultPrinc ?? "None", privacy: .public)")
            
            // Retrieve accounts and determine sign-in strategy
            let accounts = await accountsManager.accounts
            let accountsCount = accounts.count
            Logger.automaticSignIn.debug("🔍 Retrieved \(accountsCount) accounts")
            
            if accounts.isEmpty {
                Logger.automaticSignIn.warning("⚠️ No accounts found, nothing to sign in")
                return
            }
            
            for (index, account) in accounts.enumerated() {
                Logger.automaticSignIn.debug("🔍 Processing account \(index+1)/\(accountsCount): \(account.upn, privacy: .public)")
                let singleUserMode = prefs.bool(for: .singleUserMode)
                let shouldProcess = !singleUserMode || account.upn == defaultPrinc || accountsCount == 1
                
                if shouldProcess {
                    Logger.automaticSignIn.info("🔍 Creating worker for account: \(account.upn, privacy: .public)")
                    let worker = AutomaticSignInWorker(account: account)
                    Logger.automaticSignIn.debug("🔍 Worker created, calling checkUser")
                    
                    do {
                        await worker.checkUser()
                        Logger.automaticSignIn.debug("🔍 checkUser completed for: \(account.upn, privacy: .public)")
                    } catch {
                        Logger.automaticSignIn.error("❌ Error in checkUser for account \(account.upn, privacy: .public): \(error.localizedDescription)")
                    }
                } else {
                    Logger.automaticSignIn.debug("🔍 Skipping account due to single user mode: \(account.upn, privacy: .public)")
                }
            }
            
            // Restore default principal
            if let defPrinc = defaultPrinc {
                do {
                    Logger.automaticSignIn.debug("🔍 Switching back to default principal: \(defPrinc, privacy: .public)")
                    let output = try await cliTask("kswitch -p \(defPrinc)")
                    Logger.automaticSignIn.debug("🔍 kswitch output: \(output, privacy: .public)")
                } catch {
                    Logger.automaticSignIn.error("❌ Error switching to default principal: \(error.localizedDescription, privacy: .public)")
                }
            }
            
            Logger.automaticSignIn.info("🔍 [END] Automatic sign-in process completed")
        } catch {
            Logger.automaticSignIn.error("❌ Unexpected error in signInAllAccounts: \(error.localizedDescription)")
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
        Logger.automaticSignIn.debug("🔍 [Worker] checkUser started for account: \(self.account.upn, privacy: .public)")
        
        do {
            let klist = KlistUtil()
            Logger.automaticSignIn.debug("🔍 [Worker] KlistUtil initialized")
            
            let princs = await klist.klist().map({ $0.principal })
            Logger.automaticSignIn.debug("🔍 [Worker] Retrieved \(princs.count) principals: \(princs.joined(separator: ", "), privacy: .public)")
            
            Logger.automaticSignIn.debug("🔍 [Worker] Attempting to resolve SRV records for domain: \(self.domain, privacy: .public)")
            let records = try await resolveSRVRecordsWithTimeout()
            
            if !records.SRVRecords.isEmpty {
                Logger.automaticSignIn.debug("🔍 [Worker] Successfully resolved \(records.SRVRecords.count) SRV records")
                
                let hasValidTicket = princs.contains(where: { $0.lowercased() == self.account.upn.lowercased() })
                
                if hasValidTicket {
                    Logger.automaticSignIn.info("✅ [Worker] Valid ticket found for: \(self.account.upn, privacy: .public)")
                    
                    Logger.automaticSignIn.debug("🔍 [Worker] Calling getUserInfo()")
                    await getUserInfo()
                    Logger.automaticSignIn.debug("🔍 [Worker] getUserInfo() completed")
                } else {
                    Logger.automaticSignIn.info("🔍 [Worker] No valid ticket found, starting authentication")
                    
                    Logger.automaticSignIn.debug("🔍 [Worker] Calling auth()")
                    await auth()
                    Logger.automaticSignIn.debug("🔍 [Worker] auth() completed")
                }
            } else {
                Logger.automaticSignIn.warning("⚠️ [Worker] No SRV records found for domain: \(self.domain, privacy: .public)")
                throw AutoSignInError.noSRVRecords(domain)
            }
        } catch let error as AutoSignInError {
            Logger.automaticSignIn.error("❌ [Worker] AutoSignInError in checkUser: \(error.localizedDescription)")
            
            if case .noSRVRecords = error {
                Logger.automaticSignIn.debug("🔍 [Worker] Continuing with auth() despite SRV record error")
                await auth()
            }
        } catch {
            Logger.automaticSignIn.error("❌ [Worker] Unexpected error in checkUser: \(error.localizedDescription)")
            
            Logger.automaticSignIn.debug("🔍 [Worker] Calling auth() despite error")
            await auth()
        }
        
        Logger.automaticSignIn.debug("🔍 [Worker] checkUser finished for account: \(self.account.upn, privacy: .public)")
    }
    
    /// Resolves SRV records with a timeout protection to prevent hanging
    /// - Returns: The SRV records result
    /// - Throws: Error if resolution fails or times out
    func resolveSRVRecordsWithTimeout() async throws -> SRVResult {
        Logger.automaticSignIn.debug("🔍 [Worker] Starting SRV record resolution with timeout protection")
        
        // Create a task with timeout
        return try await withTimeout(seconds: 10) {
            try await self.resolveSRVRecords()
        }
    }
    
    /// Implements a timeout mechanism for async operations
    /// - Parameters:
    ///   - seconds: Timeout duration in seconds
    ///   - operation: The async operation to execute with timeout protection
    /// - Returns: The result of the operation if successful before timeout
    /// - Throws: Error from the operation or timeout error
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        return try await withThrowingTaskGroup(of: T.self) { group in
            // Main operation
            group.addTask {
                return try await operation()
            }
            
            // Timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw NSError(domain: "TimeoutError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Operation timed out after \(seconds) seconds"])
            }
            
            // Take the first result (operation or timeout)
            let result = try await group.next()!
            
            // Cancel all remaining tasks
            group.cancelAll()
            
            return result
        }
    }
    
    /// Resolves SRV records for LDAP services
    /// 
    /// - Returns: The found SRV records
    /// - Throws: Error if no records are found
    private func resolveSRVRecords() async throws -> SRVResult {
        Logger.automaticSignIn.debug("🔍 [Worker] resolveSRVRecords started")
        
        // Flag to ensure the continuation is only resumed once
        var continuationResumed = false
        let lock = NSLock() // Use a lock for thread safety

        return try await withCheckedThrowingContinuation { continuation in
            let query = "_ldap._tcp." + domain.lowercased()
            Logger.automaticSignIn.debug("🔍 [Worker] Resolving SRV records for query: \(query, privacy: .public)")

            resolver.resolve(query: query) { result in
                lock.lock() // Acquire lock before checking/modifying the flag
                // Check if already resumed
                guard !continuationResumed else {
                    lock.unlock() // Release lock if already resumed
                    Logger.automaticSignIn.warning("⚠️ [Worker] Continuation for SRV query '\(query, privacy: .public)' already resumed. Ignoring duplicate callback.")
                    return
                }
                // Mark as resumed
                continuationResumed = true
                lock.unlock() // Release lock after modifying the flag

                Logger.automaticSignIn.debug("🔍 [Worker] SRV resolver returned for query: \(query, privacy: .public)")
                
                switch result {
                case .success(let records):
                    Logger.automaticSignIn.debug("✅ [Worker] SRV resolution successful with \(records.SRVRecords.count) records")
                    continuation.resume(returning: records)
                case .failure(let error):
                    Logger.automaticSignIn.error("❌ [Worker] SRV resolution failed: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(throwing: error)
                }
            }
            
            Logger.automaticSignIn.debug("🔍 [Worker] SRV resolution request submitted, waiting for callback")
        }
    }
    
    /// Authenticates the user with keychain credentials
    /// 
    /// Retrieves the password from keychain and starts the authentication process
    func auth() async {
        Logger.automaticSignIn.debug("🔍 [Worker] Starting auth() for account: \(self.account.upn, privacy: .public)")
        let keyUtil = KeychainManager()
        
        do {
            // Retrieve password from keychain
            let username = account.upn.lowercaseDomain()
            Logger.automaticSignIn.debug("🔍 [Worker] Retrieving password from keychain for: \(username, privacy: .public)")
            
            if let pass = try keyUtil.retrievePassword(forUsername: username, andService: Defaults.keyChainService) {
                Logger.automaticSignIn.debug("✅ [Worker] Password retrieved from keychain")
                account.hasKeychainEntry = true
                session.userPass = pass
                
                // Important: Set delegate before authentication
                Logger.automaticSignIn.debug("🔍 [Worker] Setting delegate and starting authentication")
                session.delegate = self
                
                // Start authentication
                Logger.automaticSignIn.debug("🔍 [Worker] Calling session.authenticate()")
                await session.authenticate()
                Logger.automaticSignIn.debug("🔍 [Worker] session.authenticate() returned")
            } else {
                Logger.automaticSignIn.warning("⚠️ [Worker] No password found in keychain for: \(username, privacy: .public)")
                account.hasKeychainEntry = false
                Logger.automaticSignIn.debug("🔍 [Worker] Posting KrbAuthError notification")
                NotificationCenter.default.post(name: .nsmNotification, object: nil, userInfo: ["KrbAuthError": MounterError.authenticationError])
            }
        } catch {
            Logger.automaticSignIn.error("❌ [Worker] Error accessing keychain: \(error.localizedDescription, privacy: .public)")
            account.hasKeychainEntry = false
            Logger.automaticSignIn.debug("🔍 [Worker] Posting KrbAuthError notification due to keychain error")
            NotificationCenter.default.post(name: .nsmNotification, object: nil, userInfo: ["KrbAuthError": MounterError.authenticationError])
        }
        
        Logger.automaticSignIn.debug("🔍 [Worker] auth() finished for account: \(self.account.upn, privacy: .public)")
    }
    
    /// Retrieves user information from Active Directory
    /// 
    /// Switches to the user principal and retrieves detailed information
    func getUserInfo() async {
        Logger.automaticSignIn.debug("🔍 [Worker] getUserInfo started for user: \(self.account.upn, privacy: .public)")
        do {
            // Switch to user principal
            Logger.automaticSignIn.debug("🔍 [Worker] Executing kswitch for principal: \(self.session.userPrincipal)")
            let output = try await cliTask("kswitch -p \(session.userPrincipal)")
            Logger.automaticSignIn.debug("🔍 [Worker] kswitch output: \(output, privacy: .public)")
            
            // Retrieve user data
            Logger.automaticSignIn.debug("🔍 [Worker] Setting delegate and retrieving user info")
            session.delegate = self
            await session.userInfo()
            Logger.automaticSignIn.debug("🔍 [Worker] userInfo() call completed")
        } catch {
            Logger.automaticSignIn.error("❌ [Worker] Error retrieving user information: \(error.localizedDescription, privacy: .public)")
        }
        Logger.automaticSignIn.debug("🔍 [Worker] getUserInfo completed for user: \(self.account.upn, privacy: .public)")
    }
    
    // MARK: - dogeADUserSessionDelegate Methods
    
    /// Called when authentication was successful
    func dogeADAuthenticationSucceded() async {
        Logger.automaticSignIn.info("✅ [Delegate] Authentication successful for: \(self.account.upn, privacy: .public)")
        
        do {
            Logger.automaticSignIn.debug("🔍 [Delegate] Switching to authenticated user")
            let output = try await cliTask("kswitch -p \(session.userPrincipal)")
            Logger.automaticSignIn.debug("🔍 [Delegate] kswitch output: \(output, privacy: .public)")
            
            Logger.automaticSignIn.debug("🔍 [Delegate] Posting success notification")
            NotificationCenter.default.post(name: .nsmNotification, object: nil, userInfo: ["krbAuthenticated": MounterError.krbAuthSuccessful])
            
            Logger.automaticSignIn.debug("🔍 [Delegate] Retrieving user information")
            await session.userInfo()
            Logger.automaticSignIn.debug("🔍 [Delegate] User information retrieved")
        } catch {
            Logger.automaticSignIn.error("❌ [Delegate] Error after successful authentication: \(error.localizedDescription, privacy: .public)")
        }
        
        Logger.automaticSignIn.debug("🔍 [Delegate] dogeADAuthenticationSucceded completed")
    }
    
    /// Called when authentication failed
    /// 
    /// - Parameters:
    ///   - error: Error type
    ///   - description: Error description
    func dogeADAuthenticationFailed(error: dogeADSessionError, description: String) {
        Logger.automaticSignIn.warning("⚠️ [Delegate] Authentication failed for: \(self.account.upn, privacy: .public), Error: \(description, privacy: .public)")
        
        switch error {
        case .AuthenticationFailure, .PasswordExpired:
            Logger.automaticSignIn.debug("🔍 [Delegate] Handling authentication failure or expired password")
            NotificationCenter.default.post(name: .nsmNotification, object: nil, userInfo: ["KrbAuthError": MounterError.krbAuthenticationError])
            
            Logger.automaticSignIn.info("🔍 [Delegate] Removing invalid password from Keychain")
            let keyUtil = KeychainManager()
            do {
                try keyUtil.removeCredential(forUsername: account.upn)
                Logger.automaticSignIn.info("✅ [Delegate] Keychain entry successfully removed")
            } catch {
                Logger.automaticSignIn.error("❌ [Delegate] Error removing keychain entry: \(error.localizedDescription, privacy: .public)")
            }
            
        case .OffDomain:
            Logger.automaticSignIn.info("🔍 [Delegate] Outside the Kerberos Realm network")
            NotificationCenter.default.post(name: .nsmNotification, object: nil, userInfo: ["krbOffDomain": MounterError.offDomain])
            
        default:
            Logger.automaticSignIn.warning("⚠️ [Delegate] Unhandled Authentication Error: \(error, privacy: .public)")
        }
        
        Logger.automaticSignIn.debug("🔍 [Delegate] dogeADAuthenticationFailed completed")
    }
    
    /// Called when user information was successfully retrieved
    /// 
    /// - Parameter user: Retrieved user information
    func dogeADUserInformation(user: ADUserRecord) {
        Logger.automaticSignIn.debug("🔍 [Delegate] User information received for: \(user.userPrincipal, privacy: .public)")
        
        // Save user information in PreferenceManager
        prefs.setADUserInfo(user: user)
        
        Logger.automaticSignIn.debug("🔍 [Delegate] User information saved to preferences")
    }
}
