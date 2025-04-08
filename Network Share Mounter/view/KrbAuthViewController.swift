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
        Task {
            await setupView()
        }
        
        // Add observer for username field changes
        username.target = self
        username.action = #selector(usernameDidChange)
        
        // Add observer for password field changes
        password.target = self
        password.action = #selector(passwordDidChange)
        
        // Set the delegate for the password field
        password.delegate = self
    }
    
    // MARK: - Setup Methods
    private func setupView() async {
        krbAuthViewTitle.stringValue = NSLocalizedString("authui-krb-title", comment: "title of kerberos auth window")
        krbAuthViewInfoText.stringValue = NSLocalizedString("authui-krb-infotext", comment: "informative text for kerberos auth window")
        
        // Configure UI based on environment
        configureUIForEnvironment()
        
        authenticateButtonText.title = NSLocalizedString("authui-button-text", comment: "text on authenticate button")
        removeButtonText.title = NSLocalizedString("authui-remove-text", comment: "text on remove button")
        cancelButtonText.title = NSLocalizedString("cancel", comment: "cancel")
        spinner.isHidden = true
        
        await buildAccountsMenu()
        accountsList.action = #selector(popUpChange)
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
            session = dogeADSession(domain: username.stringValue.userDomain() ?? prefs.string(for: .kerberosRealm) ?? "", user: username.stringValue)
            
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
        if let principal = session?.userPrincipal {
            if let account = await accountsManager.accountForPrincipal(principal: principal) {
                let pwm = KeychainManager()
                do {
                    try pwm.saveCredential(forUsername: account.upn.lowercased(), andPassword: password.stringValue)
                    Logger.authUI.debug("Password successfully updated in keychain")
                } catch {
                    Logger.authUI.debug("Failed saving password in keychain")
                }
            } else {
                let newAccount = DogeAccount(displayName: principal, upn: principal, hasKeychainEntry: prefs.bool(for: .useKeychain))
                let pwm = KeychainManager()
                do {
                    try pwm.saveCredential(forUsername: principal.lowercased(), andPassword: password.stringValue)
                    Logger.authUI.debug("Account successfully added to keychain")
                } catch {
                    Logger.authUI.debug("Error adding account to Keychain")
                }
                await accountsManager.addAccount(account: newAccount)
            }
        }
        NotificationCenter.default.post(name: .nsmNotification, object: nil, userInfo: ["krbAuthenticated": MounterError.krbAuthSuccessful])
        closeWindow()
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
                let retrievedPassword = try keyUtil.retrievePassword(forUsername: lastUser.lowercased()) ?? ""
                password.stringValue = retrievedPassword
                username.stringValue = lastUser.lowercased()
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
            
            Task {
                let accounts = await accountsManager.accounts
                if let account = accounts.first(where: { $0.displayName == selectedTitle.replacingOccurrences(of: " ◀︎", with: "") }) {
                    if let isInKeychain = account.hasKeychainEntry, isInKeychain {
                        let keyUtil = KeychainManager()
                        do {
                            let retrievedPassword = try keyUtil.retrievePassword(forUsername: account.upn.lowercased()) ?? ""
                            password.stringValue = retrievedPassword
                            authenticateButtonText.isEnabled = !retrievedPassword.isEmpty
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
            // Wechsel zum Benutzer-Principal
            let output = try await cliTask("kswitch -p \(self.session?.userPrincipal ?? "")")
            Logger.authUI.debug("kswitch Ausgabe: \(output)")
            
            await session?.userInfo()
            await handleSuccessfulAuthentication()
        } catch {
            Logger.authUI.warning("Fehler beim Wechseln des Kerberos-Principal: \(error.localizedDescription)")
            // Trotzdem mit Authentifizierung fortfahren, da der primäre Auth-Prozess erfolgreich war
            await session?.userInfo()
            await handleSuccessfulAuthentication()
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
                        try pwm.removeCredential(forUsername: account.upn.lowercased())
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
    
    func dogeADUserInformation(user: ADUserRecord) {
        Logger.authUI.debug("User info: \(user.userPrincipal, privacy: .public)")
        
//        Task { @MainActor in
//            prefs.setADUserInfo(user: user)
//            stopOperations()
//            NotificationCenter.default.post(name: Defaults.nsmReconstructMenuTriggerNotification, object: nil)
//            self.closeWindow()
//        }
    }
}
