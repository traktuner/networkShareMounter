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

    /// Builds DogeAccount list from Kerberos AuthProfiles as fallback when AccountsManager has no accounts.
    private func buildAccountsFromKerberosProfiles() async -> [DogeAccount] {
        let profiles = await MainActor.run {
            AuthProfileManager.shared.profiles.filter { $0.useKerberos && $0.username != nil }
        }
        return profiles.compactMap { profile in
            guard let username = profile.username else { return nil }
            let upn: String
            if username.contains("@") {
                upn = username
            } else if let realm = profile.kerberosRealm {
                upn = "\(username)@\(realm.uppercased())"
            } else {
                return nil
            }
            return DogeAccount(displayName: profile.displayName, upn: upn, hasKeychainEntry: true, authProfileID: profile.id)
        }
    }
    
    /// Automatically signs in all relevant accounts
    ///
    /// Based on settings, either all accounts or only the default account will be signed in.
    ///
    /// - Parameter forceAuth: When true, forces re-authentication even if valid tickets exist (used after mount failures). Default is false.
    func signInAllAccounts(forceAuth: Bool = false) async {
        Logger.automaticSignIn.info("🔍 [START] Starting automatic sign-in process (forceAuth: \(forceAuth, privacy: .public))")
        
        do {
            let klist = KlistUtil()
            Logger.automaticSignIn.debug("🔍 KlistUtil initialized")
            
            // Retrieve all available Kerberos principals
            let principals = await klist.klist().map({ $0.principal })
            Logger.automaticSignIn.debug("🔍 Retrieved \(principals.count) principals: \(principals.joined(separator: ", "), privacy: .public)")
            
            let defaultPrinc = await klist.defaultPrincipal
            Logger.automaticSignIn.debug("🔍 Default principal: \(defaultPrinc ?? "None", privacy: .public)")
            
            // Retrieve accounts: try AccountsManager first, fall back to AuthProfile Kerberos profiles
            var accounts = await accountsManager.accounts
            Logger.automaticSignIn.debug("🔍 Retrieved \(accounts.count) accounts from AccountsManager: \(accounts.map { $0.upn }, privacy: .public)")

            if accounts.isEmpty {
                Logger.automaticSignIn.info("ℹ️ No accounts in AccountsManager, checking AuthProfile Kerberos profiles")
                accounts = await buildAccountsFromKerberosProfiles()
                Logger.automaticSignIn.debug("🔍 Built \(accounts.count) accounts from Kerberos profiles")
            } else {
                // AccountsManager accounts lack authProfileID. Enrich from Kerberos AuthProfiles
                // so auth() can look up the password via profile UUID in the new keychain format.
                let kerberosProfiles = await MainActor.run {
                    AuthProfileManager.shared.profiles.filter { $0.useKerberos }
                }
                Logger.automaticSignIn.debug("🔍 Found \(kerberosProfiles.count, privacy: .public) Kerberos profiles for enrichment (with username: \(kerberosProfiles.filter { $0.username != nil }.count, privacy: .public))")
                if !kerberosProfiles.isEmpty {
                    accounts = accounts.map { account in
                        guard account.authProfileID == nil else { return account }
                        let accountUPNLower = account.upn.lowercased()
                        let accountLocalPart = accountUPNLower.components(separatedBy: "@").first ?? accountUPNLower
                        let accountRealm = accountUPNLower.components(separatedBy: "@").last ?? ""

                        var matchedProfile = kerberosProfiles.first { profile in
                            guard let username = profile.username else { return false }
                            let profileUPNLower = username.lowercased()
                            let profileLocalPart = profileUPNLower.components(separatedBy: "@").first ?? profileUPNLower
                            if profileUPNLower == accountUPNLower { return true }
                            if profileLocalPart == accountLocalPart {
                                if let realm = profile.kerberosRealm {
                                    return realm.lowercased() == accountRealm
                                }
                                return true
                            }
                            return false
                        }
                        // Fallback: if only one Kerberos profile exists, assume it's the right one
                        if matchedProfile == nil && kerberosProfiles.count == 1 {
                            matchedProfile = kerberosProfiles.first
                            Logger.automaticSignIn.debug("🔗 Using single Kerberos profile for account \(account.upn, privacy: .public) (no UPN match)")
                        }
                        guard let match = matchedProfile else { return account }
                        var enriched = account
                        enriched.authProfileID = match.id
                        Logger.automaticSignIn.debug("🔗 Enriched account \(account.upn, privacy: .public) with authProfileID from Kerberos profile")
                        return enriched
                    }
                }
            }

            if accounts.isEmpty {
                Logger.automaticSignIn.warning("⚠️ No accounts found, nothing to sign in")
                return
            }

            for (index, account) in accounts.enumerated() {
                Logger.automaticSignIn.debug("🔍 Processing account \(index+1)/\(accounts.count): \(account.upn, privacy: .public)")
                let singleUserMode = prefs.bool(for: .singleUserMode)
                let shouldProcess = !singleUserMode || account.upn == defaultPrinc || accounts.count == 1
                
                if shouldProcess {
                    Logger.automaticSignIn.info("🔍 Creating worker for account: \(account.upn, privacy: .public)")
                    let worker = AutomaticSignInWorker(account: account, forceAuth: forceAuth)
                    Logger.automaticSignIn.debug("🔍 Worker created, calling checkUser")

                    await worker.checkUser()
                    Logger.automaticSignIn.debug("🔍 checkUser completed for: \(account.upn, privacy: .public)")
                } else {
                    Logger.automaticSignIn.debug("🔍 Skipping account due to single user mode: \(account.upn, privacy: .public)")
                }
            }
            
            // Restore default principal
            if let defPrinc = defaultPrinc {
                do {
                    Logger.automaticSignIn.debug("🔍 Switching back to default principal: \(defPrinc, privacy: .public)")
                    let output = try await cliTask("/usr/bin/kswitch -p \(defPrinc)")
                    Logger.automaticSignIn.debug("🔍 kswitch output: \(output, privacy: .public)")
                } catch {
                    Logger.automaticSignIn.error("❌ Error switching to default principal: \(error.localizedDescription, privacy: .public)")
                }
            }
            
            Logger.automaticSignIn.info("🔍 [END] Automatic sign-in process completed")
        }
    }

    /// Changes the AD password for the given user principal via kpasswd.
    ///
    /// Finds the matching account (from AccountsManager or Kerberos AuthProfiles),
    /// delegates to `AutomaticSignInWorker.changePassword`, and updates the Keychain on success.
    ///
    /// - Parameters:
    ///   - userPrincipal: The UPN whose password is being changed.
    ///   - oldPass: The current (old) password.
    ///   - newPass: The desired new password.
    func changePassword(for userPrincipal: String, oldPass: String, newPass: String) async throws {
        var accounts = await accountsManager.accounts
        if accounts.isEmpty {
            accounts = await buildAccountsFromKerberosProfiles()
        }
        guard let account = accounts.first(where: { $0.upn.lowercased() == userPrincipal.lowercased() }) else {
            throw AutoSignInError.authenticationFailed("No Kerberos account found for \(userPrincipal)")
        }
        let worker = AutomaticSignInWorker(account: account)
        try await worker.changePassword(oldPass: oldPass, newPass: newPass)
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
    
    /// Flag to distinguish between authentication and user info retrieval modes
    /// When true, we're only retrieving user info and server unavailability should not be treated as auth failure
    var isInUserInfoMode: Bool = false

    /// Flag to force re-authentication even if valid tickets exist
    /// Used after mount failures to obtain fresh Kerberos tickets
    let forceAuth: Bool

    /// Continuation held during an in-progress in-app password change; nil at all other times.
    private var passwordChangeContinuation: CheckedContinuation<Void, Error>?

    /// The new password supplied for a pending in-app password change, cleared after keychain update.
    private var pendingNewPassword = ""

    /// Initializes a new worker with a user account
    ///
    /// - Parameters:
    ///   - account: The user account for sign-in
    ///   - forceAuth: When true, forces re-authentication even if valid tickets exist. Default is false.
    init(account: DogeAccount, forceAuth: Bool = false) {
        self.account = account
        self.forceAuth = forceAuth
        domain = account.upn.userDomain() ?? ""
        self.session = dogeADSession(domain: domain, user: account.upn.user())
        self.session.setupSessionFromPrefs(prefs: prefs)

        Logger.automaticSignIn.debug("Worker initialized for user: \(account.upn, privacy: .public), domain: \(self.domain, privacy: .public), forceAuth: \(forceAuth, privacy: .public)")
    }
    
    /// Checks the user and performs sign-in
    ///
    /// The process includes:
    /// 1. Checking existing Kerberos tickets
    /// 2. Optionally validating SRV records (non-blocking)
    /// 3. Retrieving user information or authentication
    ///
    /// When forceAuth is true, authentication is always performed regardless of existing tickets.
    /// This is used after mount failures to obtain fresh Kerberos tickets.
    func checkUser() async {
        Logger.automaticSignIn.debug("🔍 [Worker] checkUser started for account: \(self.account.upn, privacy: .public)")

        let klist = KlistUtil()
        Logger.automaticSignIn.debug("🔍 [Worker] KlistUtil initialized")

        let princs = await klist.klist().map({ $0.principal })
        Logger.automaticSignIn.debug("🔍 [Worker] Retrieved \(princs.count) principals: \(princs.joined(separator: ", "), privacy: .public)")

        // Check for existing valid ticket and extract the actual principal with correct case
        let actualPrincipal = princs.first(where: { $0.lowercased() == self.account.upn.lowercased() })

        if forceAuth {
            Logger.automaticSignIn.info("🔄 [Worker] Force authentication requested - ignoring existing tickets")

            // Optionally try SRV validation (non-blocking, fires and forgets)
            await attemptSRVValidation()

            Logger.automaticSignIn.debug("🔍 [Worker] Calling auth()")
            await auth()
            Logger.automaticSignIn.debug("🔍 [Worker] auth() completed")
        } else if let actualPrincipal = actualPrincipal {
            Logger.automaticSignIn.info("✅ [Worker] Valid ticket found for: \(self.account.upn, privacy: .public)")
            Logger.automaticSignIn.debug("🔍 [Worker] Using actual principal from klist: \(actualPrincipal, privacy: .public)")

            Logger.automaticSignIn.debug("🔍 [Worker] Calling getUserInfo()")
            await getUserInfo(actualPrincipal: actualPrincipal)
            Logger.automaticSignIn.debug("🔍 [Worker] getUserInfo() completed")
        } else {
            Logger.automaticSignIn.info("🔍 [Worker] No valid ticket found, starting authentication")

            // Optionally try SRV validation (non-blocking, fires and forgets)
            await attemptSRVValidation()

            Logger.automaticSignIn.debug("🔍 [Worker] Calling auth()")
            await auth()
            Logger.automaticSignIn.debug("🔍 [Worker] auth() completed")
        }

        Logger.automaticSignIn.debug("🔍 [Worker] checkUser finished for account: \(self.account.upn, privacy: .public)")
    }
    
    /// Attempts SRV validation in the background (non-blocking)
    /// 
    /// This is purely informational and doesn't affect the authentication flow
    private func attemptSRVValidation() async {
        Logger.automaticSignIn.debug("🔍 [Worker] Starting optional SRV validation for domain: \(self.domain, privacy: .public)")
        
        // Fire and forget - don't block authentication on this
        Task.detached { [domain] in
            let resolver = SRVResolver()
            let query = "_ldap._tcp." + domain.lowercased()
            
            resolver.resolve(query: query) { result in
                switch result {
                case .success(let records):
                    if !records.SRVRecords.isEmpty {
                        Logger.automaticSignIn.info("✅ [Worker] SRV validation successful: found \(records.SRVRecords.count) LDAP servers for domain: \(domain, privacy: .public)")
                    } else {
                        Logger.automaticSignIn.info("ℹ️ [Worker] SRV validation: no LDAP servers found for domain: \(domain, privacy: .public)")
                    }
                case .failure(let error):
                    Logger.automaticSignIn.debug("🔍 [Worker] SRV validation failed for domain: \(domain, privacy: .public) - \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        
        Logger.automaticSignIn.debug("🔍 [Worker] SRV validation task started (non-blocking)")
    }
    
    /// Authenticates the user with keychain credentials
    /// 
    /// Retrieves the password from keychain and starts the authentication process
    func auth() async {
        Logger.automaticSignIn.debug("🔍 [Worker] Starting auth() for account: \(self.account.upn, privacy: .public)")
        let keyUtil = KeychainManager()
        
        do {
            // Retrieve password: new AuthProfile keychain format (by profile ID) or legacy format (by UPN)
            var pass: String?
            if let profileID = account.authProfileID {
                let profileService = Bundle.main.bundleIdentifier ?? Defaults.defaultsDomain
                Logger.automaticSignIn.debug("🔍 [Worker] Retrieving password from AuthProfile keychain (profileID: \(profileID, privacy: .public))")
                pass = try keyUtil.retrievePassword(forUsername: profileID, andService: profileService)

                // Fallback: try UPN in legacy format (accounts created before password was saved, or after UserDefaults reset)
                if pass == nil {
                    Logger.automaticSignIn.debug("🔍 [Worker] No AuthProfile password found, trying legacy UPN formats")
                    let upnVariants = [account.upn, account.upn.lowercased()]
                    for upn in upnVariants {
                        if let found = try keyUtil.retrievePassword(forUsername: upn, andService: Defaults.keyChainService) {
                            pass = found
                            Logger.automaticSignIn.info("✅ [Worker] Found password in legacy keychain for: \(upn, privacy: .public)")
                            break
                        }
                    }
                }
            } else {
                Logger.automaticSignIn.debug("🔍 [Worker] Retrieving password from legacy keychain for: \(self.account.upn, privacy: .public)")
                pass = try keyUtil.retrievePassword(forUsername: account.upn, andService: Defaults.keyChainService)
            }

            if let pass = pass {
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
                // NOTE: Authentication result will be posted by delegate methods
                // Do NOT post success notification here - delegate handles success/failure
            } else {
                Logger.automaticSignIn.warning("⚠️ [Worker] No password found in keychain for: \(self.account.upn, privacy: .public)")
                account.hasKeychainEntry = false
                Logger.automaticSignIn.debug("🔍 [Worker] Posting KrbAuthError notification")
                Logger.automaticSignIn.debug("🔔 [DEBUG-Worker] Posting KrbAuthError notification")
                NotificationCenter.default.post(name: .nsmNotification, object: nil, userInfo: ["KrbAuthError": MounterError.authenticationError])
            }
        } catch {
            Logger.automaticSignIn.error("❌ [Worker] Error accessing keychain: \(error.localizedDescription, privacy: .public)")
            account.hasKeychainEntry = false
            Logger.automaticSignIn.debug("🔍 [Worker] Posting KrbAuthError notification due to keychain error")
            Logger.automaticSignIn.debug("🔔 [DEBUG-Worker] Posting KrbAuthError notification due to keychain error")
            NotificationCenter.default.post(name: .nsmNotification, object: nil, userInfo: ["KrbAuthError": MounterError.authenticationError])
        }
        
        Logger.automaticSignIn.debug("🔍 [Worker] auth() finished for account: \(self.account.upn, privacy: .public)")
    }
    
    /// Retrieves user information from Active Directory
    ///
    /// Switches to the user principal and retrieves detailed information
    /// - Parameter actualPrincipal: The actual principal name from klist with correct case sensitivity
    func getUserInfo(actualPrincipal: String) async {
        Logger.automaticSignIn.debug("🔍 [Worker] getUserInfo started for user: \(self.account.upn, privacy: .public)")
        Logger.automaticSignIn.debug("🔍 [Worker] Using actual principal: \(actualPrincipal, privacy: .public)")

        // Set flag to indicate we're in user info mode (not authentication mode)
        isInUserInfoMode = true

        do {
            // Switch to actual principal from klist (preserves correct case)
            Logger.automaticSignIn.debug("🔍 [Worker] Executing kswitch for principal: \(actualPrincipal, privacy: .public)")
            let output = try await cliTask("/usr/bin/kswitch -p \(actualPrincipal)")
            Logger.automaticSignIn.debug("🔍 [Worker] kswitch output: \(output, privacy: .public)")

            // Since we have a valid ticket (verified by klist), post success notification
            Logger.automaticSignIn.debug("🔍 [Worker] Valid ticket confirmed, posting success notification")
            Logger.automaticSignIn.debug("🔔 [DEBUG-Worker] Posting krbAuthenticated notification for valid ticket")
            NotificationCenter.default.post(name: .nsmNotification, object: nil, userInfo: ["krbAuthenticated": MounterError.krbAuthSuccessful])

            // Retrieve user data (best effort - failure won't affect authentication status)
            Logger.automaticSignIn.debug("🔍 [Worker] Setting delegate and retrieving user info (best effort)")
            session.delegate = self
            await session.userInfo()
            Logger.automaticSignIn.debug("🔍 [Worker] userInfo() call completed")
        } catch {
            Logger.automaticSignIn.error("❌ [Worker] Error retrieving user information: \(error.localizedDescription, privacy: .public)")
            // Even if kswitch fails, we know we had a valid ticket, so post success
            Logger.automaticSignIn.debug("🔔 [DEBUG-Worker] Posting krbAuthenticated notification despite kswitch error")
            NotificationCenter.default.post(name: .nsmNotification, object: nil, userInfo: ["krbAuthenticated": MounterError.krbAuthSuccessful])
        }

        // Reset flag when done
        isInUserInfoMode = false
        Logger.automaticSignIn.debug("🔍 [Worker] getUserInfo completed for user: \(self.account.upn, privacy: .public)")
    }
    
    // MARK: - dogeADUserSessionDelegate Methods
    
    /// Changes the AD password via kpasswd and updates the keychain on success.
    ///
    /// Bridges the delegate-based `dogeADSession.changePassword()` into an async/throws call.
    func changePassword(oldPass: String, newPass: String) async throws {
        pendingNewPassword = newPass
        session.delegate = self
        session.oldPass = oldPass
        session.newPass = newPass
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            passwordChangeContinuation = continuation
            Task { await self.session.changePassword() }
        }
    }

    // MARK: - dogeADUserSessionDelegate Methods

    /// Called when authentication was successful
    func dogeADAuthenticationSucceeded() async {
        // Password-change path: update keychain and resume the caller's continuation.
        if let continuation = passwordChangeContinuation {
            passwordChangeContinuation = nil
            let keyUtil = KeychainManager()
            if let profileID = account.authProfileID {
                let service = Bundle.main.bundleIdentifier ?? Defaults.defaultsDomain
                try? keyUtil.saveCredential(forUsername: profileID, andPassword: pendingNewPassword, withService: service)
            } else {
                try? keyUtil.saveCredential(forUsername: account.upn, andPassword: pendingNewPassword)
            }
            Logger.passwordExpiration.info("✅ Keychain updated after password change for \(self.account.upn, privacy: .public)")
            pendingNewPassword = ""
            continuation.resume(returning: ())
            return
        }

        Logger.automaticSignIn.info("✅ [Delegate] Authentication successful for: \(self.account.upn, privacy: .public)")

        do {
            // After successful authentication, get the actual principal from klist
            let klist = KlistUtil()
            let princs = await klist.klist().map({ $0.principal })
            Logger.automaticSignIn.debug("🔍 [Delegate] Retrieved \(princs.count, privacy: .public) principals after auth")

            // Find the actual principal with correct case
            if let actualPrincipal = princs.first(where: { $0.lowercased() == self.account.upn.lowercased() }) {
                Logger.automaticSignIn.debug("🔍 [Delegate] Using actual principal from klist: \(actualPrincipal, privacy: .public)")
                Logger.automaticSignIn.debug("🔍 [Delegate] Switching to authenticated user")
                let output = try await cliTask("/usr/bin/kswitch -p \(actualPrincipal)")
                Logger.automaticSignIn.debug("🔍 [Delegate] kswitch output: \(output, privacy: .public)")
            } else {
                // Fallback to session.userPrincipal if we can't find the ticket (shouldn't happen)
                Logger.automaticSignIn.warning("⚠️ [Delegate] Could not find actual principal in klist, using session principal")
                let output = try await cliTask("/usr/bin/kswitch -p \(session.userPrincipal)")
                Logger.automaticSignIn.debug("🔍 [Delegate] kswitch output: \(output, privacy: .public)")
            }

            Logger.automaticSignIn.debug("🔍 [Delegate] Posting success notification")
            Logger.automaticSignIn.debug("🔔 [DEBUG-Delegate] Posting krbAuthenticated notification")
            NotificationCenter.default.post(name: .nsmNotification, object: nil, userInfo: ["krbAuthenticated": MounterError.krbAuthSuccessful])

            Logger.automaticSignIn.debug("🔍 [Delegate] Retrieving user information")
            await session.userInfo()
            Logger.automaticSignIn.debug("🔍 [Delegate] User information retrieved")
        } catch {
            Logger.automaticSignIn.error("❌ [Delegate] Error after successful authentication: \(error.localizedDescription, privacy: .public)")
        }

        Logger.automaticSignIn.debug("🔍 [Delegate] dogeADAuthenticationSucceeded completed")
    }
    
    /// Called when authentication failed
    /// 
    /// - Parameters:
    ///   - error: Error type
    ///   - description: Error description
    func dogeADAuthenticationFailed(error: dogeADSessionError, description: String) async {
        // Password-change path: surface the error to the caller's continuation.
        if let continuation = passwordChangeContinuation {
            passwordChangeContinuation = nil
            pendingNewPassword = ""
            continuation.resume(throwing: AutoSignInError.authenticationFailed(description))
            return
        }

        Logger.automaticSignIn.warning("⚠️ [Delegate] Authentication failed for: \(self.account.upn, privacy: .public), Error: \(description, privacy: .public)")

        // If we're in user info mode (we already have a valid ticket), don't treat server unavailability as auth failure
        if isInUserInfoMode {
            Logger.automaticSignIn.info("ℹ️ [Delegate] In user info mode - treating server error as availability issue, not auth failure")
            Logger.automaticSignIn.debug("🔍 [Delegate] Error type: \(error, privacy: .public), Description: \(description, privacy: .public)")
            // Don't post any error notifications - we already posted success notification in getUserInfo()
            Logger.automaticSignIn.debug("🔍 [Delegate] Ignoring error since we already have valid ticket")
            return
        }
        
        switch error {
        case .AuthenticationFailure, .PasswordExpired, .KerbError, .unknownPrincipal, .wrongRealm:
            Logger.automaticSignIn.debug("🔍 [Delegate] Handling authentication failure or expired password")
            Logger.automaticSignIn.debug("🔔 [DEBUG-Delegate] Posting KrbAuthError notification")
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
            Logger.automaticSignIn.debug("🔔 [DEBUG-Delegate] Posting krbOffDomain notification")
            NotificationCenter.default.post(name: .nsmNotification, object: nil, userInfo: ["krbOffDomain": MounterError.offDomain])
    
        case .SiteError, .StateError, .UnAuthenticated:
            Logger.automaticSignIn.debug("🔍 [Delegate] Handling network/reachability error")
            Logger.automaticSignIn.debug("🔔 [DEBUG-Delegate] Posting krbUnreachable notification")
            NotificationCenter.default.post(name: .nsmNotification, object: nil, userInfo: ["krbUnreachable": MounterError.offDomain])
        }
        
        Logger.automaticSignIn.debug("🔍 [Delegate] dogeADAuthenticationFailed completed")
    }
    
    /// Called when user information was successfully retrieved
    ///
    /// - Parameter user: Retrieved user information
    func dogeADUserInformation(user: ADUserRecord) async {
        Logger.automaticSignIn.debug("🔍 [Delegate] User information received for: \(user.userPrincipal, privacy: .public)")

        prefs.setADUserInfo(user: user)
        NotificationCenter.default.post(
            name: .nsmNotification,
            object: nil,
            userInfo: ["kerberosUserAuthenticated": user.userPrincipal]
        )
        checkPasswordExpiration(for: user)

        Logger.automaticSignIn.debug("🔍 [Delegate] User information saved to preferences")
    }

    // MARK: - Password Expiration

    /// Checks whether the password is close to expiring and posts the appropriate notifications.
    ///
    /// Behaviour mirrors Apple's Kerberos SSO Extension and Jamf Connect:
    /// - Within `ExpirationCountdownStartDay` days: always posts `passwordExpirationWarning`
    ///   so the menu shows a countdown item.
    /// - Within `ExpirationNotificationStartDay` days: additionally posts
    ///   `showPasswordExpirationDialog` once per calendar day.
    /// - If password aging is disabled or the "never expires" UAC flag is set: posts
    ///   `clearPasswordExpiration` so any previous warning is removed from the menu.
    private func checkPasswordExpiration(for user: ADUserRecord) {
        guard !user.isPasswordNeverExpires,
              let aging = user.passwordAging, aging,
              let expireDate = user.computedExpireDate else {
            NotificationCenter.default.post(
                name: .nsmNotification,
                object: nil,
                userInfo: ["clearPasswordExpiration": true]
            )
            return
        }

        let daysRemaining = Calendar.current.dateComponents([.day], from: Date(), to: expireDate).day ?? Int.max
        let countdownThreshold = prefs.int(for: .expirationCountdownStartDay)

        guard countdownThreshold > 0 else {
            NotificationCenter.default.post(
                name: .nsmNotification,
                object: nil,
                userInfo: ["clearPasswordExpiration": true]
            )
            return
        }

        guard daysRemaining <= countdownThreshold else {
            NotificationCenter.default.post(
                name: .nsmNotification,
                object: nil,
                userInfo: ["clearPasswordExpiration": true]
            )
            return
        }

        Logger.passwordExpiration.info("⚠️ Password expires in \(daysRemaining) days for \(user.userPrincipal, privacy: .public)")

        NotificationCenter.default.post(
            name: .nsmNotification,
            object: nil,
            userInfo: [
                "passwordExpirationWarning": daysRemaining,
                "passwordExpirationUser": user.userPrincipal
            ]
        )

        let notificationThreshold = prefs.int(for: .expirationNotificationStartDay)
        guard daysRemaining <= notificationThreshold else { return }

        let lastWarning = prefs.date(for: .lastPasswordExpirationWarningDate)
        let alreadyWarnedToday = lastWarning.map { Calendar.current.isDateInToday($0) } ?? false
        guard !alreadyWarnedToday else { return }

        prefs.set(for: .lastPasswordExpirationWarningDate, value: Date())

        NotificationCenter.default.post(
            name: .nsmNotification,
            object: nil,
            userInfo: ["showPasswordExpirationDialog": true]
        )
    }
}

