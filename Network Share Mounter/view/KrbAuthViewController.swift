//
//  KrbAuthViewController.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 05.01.24.
//  Copyright © 2024 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation
import Cocoa
import OSLog
import dogeADAuth

/// Timeout error for async operations
struct TimeoutError: Error, LocalizedError {
    let seconds: TimeInterval

    var errorDescription: String? {
        return "Operation timed out after \(seconds) seconds"
    }
}

/// Execute an async operation with a timeout
/// - Parameters:
///   - seconds: Timeout duration in seconds
///   - operation: The async operation to execute
/// - Returns: The result of the operation
/// - Throws: TimeoutError if the operation times out
func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
    return try await withThrowingTaskGroup(of: T.self) { group in
        // Add the operation task
        group.addTask {
            try await operation()
        }

        // Add the timeout task
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw TimeoutError(seconds: seconds)
        }

        // Return the first task that completes
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

class KrbAuthViewController: NSViewController, AccountUpdate, NSTextFieldDelegate {
    func updateAccounts(accounts: [DogeAccount]) {
        Task { @MainActor in
            await buildAccountsMenu()
        }
    }
    
    
    // MARK: - Properties
    var session: dogeADSession?
    var prefs = PreferenceManager()
    let accountsManager = AccountsManager.shared
    
    // UI Outlets
    @IBOutlet weak var logo: NSImageView!
    @IBOutlet weak var usernameText: NSTextField!
    @IBOutlet weak var passwordText: NSTextField!
    @IBOutlet weak var username: NSTextField!
    @IBOutlet weak var password: NSSecureTextField!
    @IBOutlet weak var authenticateButtonText: NSButton!
    @IBOutlet weak var removeButtonText: NSButton!
    @IBOutlet weak var cancelButtonText: NSButton!
    @IBOutlet weak var spinner: NSProgressIndicator!
    @IBOutlet weak var accountsList: NSPopUpButton!
    @IBOutlet weak var krbAuthViewTitle: NSTextField!
    @IBOutlet weak var krbAuthViewInfoText: NSTextField!
    
    // Help messages
    var helpText = [
        NSLocalizedString("Sorry, no help available", comment: "this should not happen"),
        NSLocalizedString("authui-infotext", comment: "")
    ]
    
    // MARK: - View Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Configure UI synchronously first
        configureSynchronousUI()
        
        // Add observer for username field changes
        username.target = self
        username.action = #selector(usernameDidChange)
        
        // Add observer for password field changes
        password.target = self
        password.action = #selector(passwordDidChange)
        
        // Set the delegate for the password field
        password.delegate = self
        
        // Then handle async operations
        Task {
            await setupAsynchronousUI()
        }
    }
    
    // MARK: - Setup Methods
    private func configureSynchronousUI() {
        krbAuthViewTitle.stringValue = NSLocalizedString("authui-krb-title", comment: "title of kerberos auth window")
        krbAuthViewInfoText.stringValue = NSLocalizedString("authui-krb-infotext", comment: "informative text for kerberos auth window")
        
        authenticateButtonText.title = NSLocalizedString("authui-button-text", comment: "text on authenticate button")
        removeButtonText.title = NSLocalizedString("authui-remove-text", comment: "text on remove button")
        cancelButtonText.title = NSLocalizedString("cancel", comment: "cancel")
        spinner.isHidden = true
        
        // Configure UI based on environment
        configureUIForEnvironment()
        
        accountsList.action = #selector(popUpChange)
    }
    
    private func setupAsynchronousUI() async {
        await buildAccountsMenu()
        await accountsManager.addDelegate(delegate: self)
    }
    
    
    private func configureUIForEnvironment() {
        if prefs.string(for: .kerberosRealm)?.lowercased() == FAU.kerberosRealm.lowercased() {
            usernameText.stringValue = NSLocalizedString("authui-username-text-FAU", comment: "value shown as FAU username")
            passwordText.stringValue = NSLocalizedString("authui-password-text-FAU", comment: "value shown as FAU password")
            logo.image = NSImage(named: FAU.authenticationDialogImage)
        } else {
            usernameText.stringValue = NSLocalizedString("authui-username-text", comment: "value shown as username")
            passwordText.stringValue = NSLocalizedString("authui-password-text", comment: "value shown as password")
            logo.image = NSImage(named: prefs.string(for: .authenticationDialogImage)!)
        }
    }
    
    // MARK: - Actions
    @IBAction func authenticateKlicked(_ sender: Any) {
        authenticateUser(userPassword: self.password.stringValue)
    }
    
    @IBAction func cancelKlicked(_ sender: Any) {
        dismiss(nil)
    }
    
    @IBAction func helpButtonClicked(_ sender: NSButton) {
        showHelpPopover(for: sender)
    }
    
    @IBAction func removeKlicked(_ sender: Any) {
        Task {
            // Ensure the operation is performed on the main thread
            await MainActor.run {
                // Get the selected item title
                guard let selectedTitle = accountsList.selectedItem?.title else {
                    Logger.KrbAuthViewController.debug("No account selected for removal")
                    return
                }
                
                // Remove the indicator if present
                let accountTitle = selectedTitle.replacingOccurrences(of: " ◀︎", with: "")
                
                // Find the corresponding DogeAccount
                Task {
                    let accounts = await accountsManager.accounts
                    if let accountToRemove = accounts.first(where: { $0.displayName == accountTitle }) {
                        await accountsManager.deleteAccount(account: accountToRemove)
                        Logger.KrbAuthViewController.debug("Account removed: \(accountToRemove.displayName)")
                        
                        // Rebuild the accounts menu to reflect the changes
                        await buildAccountsMenu()
                    } else {
                        Logger.KrbAuthViewController.debug("Account not found for removal: \(accountTitle)")
                    }
                }
            }
        }
    }
    
    // MARK: - Authentication
    private func authenticateUser(userPassword: String) {
        Task {
            // Set up the session with the provided username and domain
            let kerberosRealm = prefs.string(for: .kerberosRealm) ?? ""
            let sessionDomain = username.stringValue.userDomain() ?? kerberosRealm
            session = dogeADSession(domain: sessionDomain, user: username.stringValue)
            
            // Configure the session with preferences
            session?.setupSessionFromPrefs(prefs: prefs)
            
            // Set the user password
            session?.userPass = userPassword
            
            // Assign the delegate to self to handle authentication callbacks
            session?.delegate = self
            
            // Start the authentication process
            await session?.authenticate(authTestOnly: false)
        }
    }
    
    private func handleSuccessfulAuthentication() async {
        Logger.authUI.debug("🔍 [DEBUG-AUTH] handleSuccessfulAuthentication started")
        Logger.authUI.debug("🔍 [DEBUG-AUTH] Session userPrincipal: \(self.session?.userPrincipal ?? "nil")")

        if let principal = session?.userPrincipal {
            Logger.authUI.debug("🔍 [DEBUG-AUTH] Checking if account exists for principal: \(principal)")

            if var account = await accountsManager.accountForPrincipal(principal: principal) {
                Logger.authUI.debug("🔍 [DEBUG-AUTH] Existing account found, updating password in keychain")

                // Lazy migration: Update account UPN if case differs
                if account.upn != principal {
                    Logger.authUI.debug("🔄 [DEBUG-AUTH] Migrating account UPN case from \(account.upn) to \(principal)")
                    account.upn = principal
                    account.displayName = principal
                    await accountsManager.updateAccount(account)
                }

                let pwm = KeychainManager()
                do {
                    try pwm.saveCredential(forUsername: principal, andPassword: password.stringValue)
                    Logger.authUI.debug("✅ [DEBUG-AUTH] Password successfully updated in keychain for: \(principal, privacy: .public)")
                } catch {
                    Logger.authUI.error("❌ [DEBUG-AUTH] Failed saving password in keychain: \(error.localizedDescription)")
                }
            } else {
                Logger.authUI.debug("🔍 [DEBUG-AUTH] No existing account found, creating new account")
                let newAccount = DogeAccount(displayName: principal, upn: principal, hasKeychainEntry: prefs.bool(for: .useKeychain))
                Logger.authUI.debug("🔍 [DEBUG-AUTH] Created new account: \(newAccount.upn), hasKeychainEntry: \(newAccount.hasKeychainEntry ?? false)")

                let pwm = KeychainManager()
                do {
                    try pwm.saveCredential(forUsername: principal, andPassword: password.stringValue)
                    Logger.authUI.debug("✅ [DEBUG-AUTH] New account successfully added to keychain for: \(principal, privacy: .public)")
                } catch {
                    Logger.authUI.error("❌ [DEBUG-AUTH] Error adding account to Keychain: \(error.localizedDescription)")
                }

                Logger.authUI.debug("🔍 [DEBUG-AUTH] Adding account to AccountsManager...")
                await accountsManager.addAccount(account: newAccount)
                Logger.authUI.debug("✅ [DEBUG-AUTH] Account added to AccountsManager")

                // Verify the account was added
                let accountCount = await accountsManager.accounts.count
                Logger.authUI.debug("🔍 [DEBUG-AUTH] Total accounts after adding: \(accountCount)")
            }
        } else {
            Logger.authUI.error("❌ [DEBUG-AUTH] No userPrincipal available from session")
        }

        Logger.authUI.debug("🔍 [DEBUG-AUTH] Posting krbAuthenticated notification")
        NotificationCenter.default.post(name: .nsmNotification, object: nil, userInfo: ["krbAuthenticated": MounterError.krbAuthSuccessful])

        Logger.authUI.debug("✅ [DEBUG-AUTH] handleSuccessfulAuthentication completed - window will be closed by dogeADUserInformation")
    }
    
    // MARK: - UI Operations
    fileprivate func startOperations() {
        Task { @MainActor in
            spinner.isHidden = false
            spinner.startAnimation(nil)
            authenticateButtonText.isEnabled = false
            cancelButtonText.isEnabled = false
            username.isEditable = false
            password.isEditable = false
        }
    }
    
    fileprivate func stopOperations() {
        Task { @MainActor in
            spinner.isHidden = true
            spinner.stopAnimation(nil)
            authenticateButtonText.isEnabled = true
            cancelButtonText.isEnabled = true
            username.isEditable = true
            password.isEditable = true
        }
    }
    
    private func showAlert(message: String) {
        Task { @MainActor in
            let alert = NSAlert()
            alert.messageText = formatAlertMessage(message)
            alert.runModal()
            Logger.authUI.debug("Showing alert with message: \(message)")
        }
    }
    
    private func formatAlertMessage(_ message: String) -> String {
        var text = message
        if message.contains("unable to reach any KDC in realm") {
            text = "Unable to reach any Kerberos servers in this domain. Please check your network connection and try again."
        } else if message.contains("Client") && text.contains("unknown") {
            text = "Your username could not be found. Please check the spelling and try again."
        } else if message.contains("RSA private encrypt failed") {
            text = "Your PIN is incorrect"
        }
        switch message {
        case "Preauthentication failed":
            text = "Incorrect username or password."
        case "Password has expired":
            text = "Password has expired."
        default:
            break
        }
        return text
    }
    
    private func closeWindow() {
        Task { @MainActor in
            dismiss(nil)
        }
    }
    
    private func buildAccountsMenu() async {
        let klist = KlistUtil()
        let tickets = await klist.klist()
        
        // Filter out invalid accounts and remove them
        let accounts = await accountsManager.accounts
        for account in accounts {
            let upnComponents = account.upn.split(separator: "@")
            if upnComponents.count < 2 || upnComponents[0].isEmpty {
                // Invalid account found, remove it
                Logger.KrbAuthViewController.debug("Removing invalid account: \(account.displayName)")
                await accountsManager.deleteAccount(account: account)
            }
        }
        
        if await accountsManager.accounts.count > 1 && !prefs.bool(for: .singleUserMode) {
            accountsList.removeAllItems()
            for account in await accountsManager.accounts {
                let title = account.displayName + (tickets.contains(where: { $0.principal.lowercased() == account.upn.lowercased() }) ? " ◀︎" : "")
                accountsList.addItem(withTitle: title)
            }
            accountsList.addItem(withTitle: "Other...")
            username.isHidden = true
            accountsList.isHidden = false
            accountsList.isEnabled = true
            await popUpChange()
            return
        }
        
        accountsList.isHidden = true
        username.isHidden = false
        if let lastUser = prefs.string(for: .lastUser) {
            let keyUtil = KeychainManager()
            do {
                let retrievedPassword = try keyUtil.retrievePassword(forUsername: lastUser) ?? ""
                password.stringValue = retrievedPassword
                username.stringValue = lastUser
                authenticateButtonText.isEnabled = !retrievedPassword.isEmpty
            } catch {
                Logger.KrbAuthViewController.debug("Unable to get user's password")
            }
        }
    }
    
    @objc func popUpChange() async {
        await MainActor.run {
            Logger.KrbAuthViewController.debug("Selected Item is: \(self.accountsList.selectedItem?.title ?? "None")")
            
            // Clear the password field and disable the authenticate button
            password.stringValue = ""
            authenticateButtonText.isEnabled = false
            
            if accountsList.selectedItem?.title == "Other..." {
                accountsList.isHidden = true
                username.isHidden = false
                username.becomeFirstResponder()
                return
            }
            
            guard let selectedTitle = accountsList.selectedItem?.title else { return }

            Task { [weak self] in
                guard let self else { return }
                let accounts = await accountsManager.accounts

                if let account = accounts.first(where: { $0.displayName == selectedTitle.replacingOccurrences(of: " ◀︎", with: "") }) {
                    if let isInKeychain = account.hasKeychainEntry, isInKeychain {
                        let keyUtil = KeychainManager()
                        do {
                            let retrievedPassword = try keyUtil.retrievePassword(forUsername: account.upn) ?? ""
                            await MainActor.run {
                                self.password.stringValue = retrievedPassword
                                self.authenticateButtonText.isEnabled = !retrievedPassword.isEmpty
                            }
                        } catch {
                            Logger.KrbAuthViewController.debug("Unable to get user's password")
                        }
                    }
                }
            }
        }
    }
    
    @objc func usernameDidChange() {
        // Clear the password field and disable the authenticate button
        password.stringValue = ""
        authenticateButtonText.isEnabled = false
    }
    
    @objc func passwordDidChange() {
        // Enable the authenticate button if the password field is not empty
        authenticateButtonText.isEnabled = !password.stringValue.isEmpty
    }
    
    // MARK: - NSTextFieldDelegate
    func controlTextDidChange(_ obj: Notification) {
        // Enable the authenticate button if the password field is not empty
        if obj.object as? NSTextField == password {
            authenticateButtonText.isEnabled = !password.stringValue.isEmpty
        }
    }
    
    private func showHelpPopover(for sender: NSButton) {
        guard let helpPopoverViewController = storyboard?.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("HelpPopoverViewController")) as? HelpPopoverViewController else {
            // Handle the error, e.g., log an error message or show an alert
            Logger.authUI.error("Failed to instantiate HelpPopoverViewController")
            return
        }
        
        let popover = NSPopover()
        popover.contentViewController = helpPopoverViewController
        helpPopoverViewController.helpText = helpText[sender.tag]
        popover.animates = true
        popover.show(relativeTo: sender.frame, of: view, preferredEdge: .minY)
        popover.behavior = .transient
    }
}

// MARK: - dogeADUserSessionDelegate
extension KrbAuthViewController: dogeADUserSessionDelegate {
    func dogeADAuthenticationSucceded() async {
        Logger.authUI.debug("Auth succeeded")

        do {
            // Get the actual principal from klist to ensure correct case sensitivity
            let klist = KlistUtil()
            let principals = await klist.klist().map({ $0.principal })
            Logger.authUI.debug("Retrieved \(principals.count) principals from klist: \(principals.joined(separator: ", "))")

            // Find the actual principal matching our session (case-insensitive match)
            let sessionPrincipal = self.session?.userPrincipal ?? ""
            guard let actualPrincipal = principals.first(where: { $0.lowercased() == sessionPrincipal.lowercased() }) else {
                Logger.authUI.warning("⚠️ Could not find matching principal in klist for: \(sessionPrincipal)")
                Logger.authUI.info("ℹ️ Continuing without kswitch - ticket was successfully created")

                // Continue with userInfo even without kswitch
                Logger.authUI.debug("🔍 [DEBUG] Starting session.userInfo() call with timeout...")
                let userInfoTask = Task {
                    await session?.userInfo()
                }

                Logger.authUI.debug("🔍 [DEBUG] Waiting for userInfo to complete (5s timeout)...")
                do {
                    _ = try await withTimeout(seconds: 5) {
                        await userInfoTask.value
                    }
                    Logger.authUI.debug("🔍 [DEBUG] userInfo call completed successfully")
                } catch {
                    Logger.authUI.warning("⚠️ [DEBUG] userInfo call timed out or failed: \(error.localizedDescription)")
                    userInfoTask.cancel()
                }

                await handleSuccessfulAuthentication()
                return
            }

            Logger.authUI.debug("Before kswitch execution - Session principal: \(sessionPrincipal)")
            Logger.authUI.debug("Using actual principal from klist for kswitch: \(actualPrincipal)")
            let output = try await cliTask("/usr/bin/kswitch -p \(actualPrincipal)")
            Logger.authUI.debug("kswitch output: \(output)")

            Logger.authUI.debug("After kswitch - before userInfo call")
            Logger.authUI.debug("🔍 [DEBUG] Starting session.userInfo() call with timeout...")

            // Add timeout handling for userInfo call (5 seconds timeout)
            let userInfoTask = Task {
                await session?.userInfo()
            }

            Logger.authUI.debug("🔍 [DEBUG] Waiting for userInfo to complete (5s timeout)...")

            // Wait for userInfo with 5 second timeout
            do {
                _ = try await withTimeout(seconds: 5) {
                    await userInfoTask.value
                }
                Logger.authUI.debug("🔍 [DEBUG] userInfo call completed successfully")
            } catch {
                Logger.authUI.warning("⚠️ [DEBUG] userInfo call timed out or failed: \(error.localizedDescription)")
                Logger.authUI.info("ℹ️ [DEBUG] Continuing with authentication despite userInfo failure - Kerberos auth was successful")
                userInfoTask.cancel()
            }

            Logger.authUI.debug("After userInfo call - before handleSuccessfulAuthentication")
            await handleSuccessfulAuthentication()
            Logger.authUI.debug("After handleSuccessfulAuthentication")
        } catch {
            Logger.authUI.warning("⚠️ Error switching Kerberos principal: \(error.localizedDescription)")
            // Detailed error information
            Logger.authUI.debug("Error type: \(type(of: error))")
            if let nsError = error as NSError? {
                Logger.authUI.debug("NSError Code: \(nsError.code), Domain: \(nsError.domain)")
                Logger.authUI.debug("UserInfo: \(nsError.userInfo)")
            }
            
            Logger.authUI.debug("Despite kswitch error - attempting to continue with userInfo")
            Logger.authUI.debug("Note: kswitch failed but Kerberos ticket was successfully created, continuing with authentication")
            // Continue with authentication anyway, since the primary auth process was successful
            Logger.authUI.debug("🔍 [DEBUG-CATCH] Starting session.userInfo() call in catch block with timeout...")

            let userInfoTaskCatch = Task {
                await session?.userInfo()
            }

            Logger.authUI.debug("🔍 [DEBUG-CATCH] Waiting for userInfo to complete in catch block (5s timeout)...")

            // Wait for userInfo with 5 second timeout in catch block
            do {
                _ = try await withTimeout(seconds: 5) {
                    await userInfoTaskCatch.value
                }
                Logger.authUI.debug("🔍 [DEBUG-CATCH] userInfo call completed in catch block")
            } catch {
                Logger.authUI.warning("⚠️ [DEBUG-CATCH] userInfo call timed out or failed in catch block: \(error.localizedDescription)")
                Logger.authUI.info("ℹ️ [DEBUG-CATCH] Continuing with authentication despite userInfo failure - Kerberos auth was successful")
                userInfoTaskCatch.cancel()
            }

            Logger.authUI.debug("After userInfo call in catch block")
            await handleSuccessfulAuthentication()
            Logger.authUI.debug("After handleSuccessfulAuthentication in catch block")
        }
    }
    
    func dogeADAuthenticationFailed(error: dogeADSessionError, description: String) async {
        Task {
            Logger.authUI.info("Error: \(description, privacy: .public)")
            
            if error == .UnAuthenticated {
                stopOperations()
                return
            }
            
            for account in await accountsManager.accounts {
                if account.upn.lowercased() == session?.userPrincipal.lowercased() {
                    let pwm = KeychainManager()
                    do {
                        try pwm.removeCredential(forUsername: account.upn)
                        Logger.authUI.debug("Password removed from Keychain")
                    } catch {
                        Logger.authUI.debug("Error removing password from Keychain")
                    }
                }
            }
            stopOperations()
            showAlert(message: description)
        }
    }
    
    func dogeADUserInformation(user: ADUserRecord) async {
        Logger.authUI.debug("🔍 [DEBUG-USERINFO] User info received: \(user.userPrincipal, privacy: .public)")

        Task { @MainActor in
            Logger.authUI.debug("🔍 [DEBUG-USERINFO] Starting @MainActor task in dogeADUserInformation")
            prefs.setADUserInfo(user: user)
            Logger.authUI.debug("✅ [DEBUG-USERINFO] After prefs.setADUserInfo")
            stopOperations()
            Logger.authUI.debug("✅ [DEBUG-USERINFO] After stopOperations")
            NotificationCenter.default.post(name: Defaults.nsmReconstructMenuTriggerNotification, object: nil)
            Logger.authUI.debug("✅ [DEBUG-USERINFO] After notification post, before closeWindow")
            self.closeWindow()
            Logger.authUI.debug("✅ [DEBUG-USERINFO] After closeWindow - dogeADUserInformation completed")
        }
    }
}

