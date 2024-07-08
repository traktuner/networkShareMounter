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

class KrbAuthViewController: NSViewController, AccountUpdate {
    func updateAccounts(accounts: [DogeAccount]) {
        Task { @MainActor in
            await buildAccountsMenu()
        }
    }
    
    // MARK: - help messages
    var helpText = [NSLocalizedString("Sorry, no help available", comment: "this should not happen"),
                    NSLocalizedString("authui-infotext", comment: "")]
    
    var session: dogeADSession?
    var prefs = PreferenceManager()
    
    let accountsManager = AccountsManager.shared
    
    @IBOutlet weak var logo: NSImageView!
    @IBOutlet weak var usernameText: NSTextField!
    @IBOutlet weak var passwordText: NSTextField!
    @IBOutlet weak var username: NSTextField!
    @IBOutlet weak var password: NSSecureTextField!
    @IBOutlet weak var authenticateButtonText: NSButton!
    @IBOutlet weak var cancelButtonText: NSButton!
    @IBOutlet weak var spinner: NSProgressIndicator!
    @IBOutlet weak var accountsList: NSPopUpButton!
    @IBOutlet weak var krbAuthViewTitle: NSTextField!
    @IBOutlet weak var krbAuthViewInfoText: NSTextField!
    
    @IBAction func authenticateKlicked(_ sender: Any) {
        startOperations()
        self.session = dogeADSession(domain: self.username.stringValue.userDomain() ?? prefs.string(for: .kerberosRealm) ?? "", user: self.username.stringValue)
        session?.setupSessionFromPrefs(prefs: prefs)
        session?.userPass = password.stringValue
        session?.delegate = self
        
        Task {
            await session?.authenticate()
        }
    }
    
    @IBAction func cancelKlicked(_ sender: Any) {
        dismiss(nil)
    }
    
    // MARK: - initialize view
    override func viewDidLoad() {
        super.viewDidLoad()
        Task {
            krbAuthViewTitle.stringValue = NSLocalizedString("authui-krb-title", comment: "title of kerberos auth window")
            krbAuthViewInfoText.stringValue = NSLocalizedString("authui-krb-infotext", comment: "informative test for kerberos auth window")
            // if NSM is used in FAU environment use corporate images and labels
            if prefs.string(for: .kerberosRealm)?.lowercased() == FAU.kerberosRealm.lowercased() {
                usernameText.stringValue = NSLocalizedString("authui-username-text-FAU", comment: "value shown as FAU username")
                passwordText.stringValue = NSLocalizedString("authui-password-text-FAU", comment: "value shown as FAU password")
                logo.image = NSImage(named: FAU.authenticationDialogImage)
            } else {
                usernameText.stringValue = NSLocalizedString("authui-username-text", comment: "value shown as username")
                passwordText.stringValue = NSLocalizedString("authui-password-text", comment: "value shown as password")
                // force unwrap is ok since authenticationDialogImage is a registered default in AppDelegate
                logo.image = NSImage(named: prefs.string(for: .authenticationDialogImage)!)
            }
            authenticateButtonText.title = NSLocalizedString("authui-button-text", comment: "text on authenticate button")
            cancelButtonText.title = NSLocalizedString("cancel", comment: "cancel")
            self.spinner.isHidden = true
            
            await buildAccountsMenu()
            accountsList.action = #selector(popUpChange)
            await accountsManager.addDelegate(delegate: self)
        }
    }
    
    @IBAction func helpButtonClicked(_ sender: NSButton) {
        // swiftlint:disable force_cast
        let helpPopoverViewController = self.storyboard?.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("HelpPopoverViewController")) as! HelpPopoverViewController
        // swiftlint:enable force_cast
        let popover = NSPopover()
        popover.contentViewController = helpPopoverViewController
        helpPopoverViewController.helpText = helpText[sender.tag]
        popover.animates = true
        popover.show(relativeTo: sender.frame, of: self.view, preferredEdge: .minY)
        popover.behavior = .transient
    }
    
    /// start some UI operations like spinner animation, buttons are not clickable
    /// text fields are not editable and so on
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
    
    /// stop some UI operations like spinner animation, buttons are clickable
    /// text fields are editable and so on
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
            alert.messageText = text
            if alert.runModal() == .alertFirstButtonReturn {
                Logger.authUI.debug("showing alert")
            }
        }
    }
    
    func windowWillClose(_ notification: Notification) {
        stopOperations()
        session = nil
    }
    
    private func closeWindow() {
        Task { @MainActor in
            dismiss(nil)
        }
    }
    
    private func buildAccountsMenu() async {
        let klist = KlistUtil()
        let tickets = await klist.klist()
        
        // populate popup list if there is more than one account
        if await accountsManager.accounts.count > 1 && !prefs.bool(for: .singleUserMode) {
            Task {
                accountsList.removeAllItems()
                for account in await accountsManager.accounts {
                    if tickets.contains(where: { $0.principal.lowercased() == account.upn.lowercased() }) {
                        accountsList.addItem(withTitle: account.displayName + " ◀︎")
                    } else {
                        accountsList.addItem(withTitle: account.displayName)
                    }
                }
                accountsList.addItem(withTitle: "Other...")
                username.isHidden = true
                accountsList.isHidden = false
                accountsList.isEnabled = true
                await popUpChange()
            }
            return
        }
        
        // if there is only one account, hide popup list
        await MainActor.run {
            accountsList.isHidden = true
            username.isHidden = false
            if let lastUser = prefs.string(for: .lastUser) {
                let keyUtil = KeychainManager()
                do {
                    try password.stringValue = keyUtil.retrievePassword(forUsername: lastUser.lowercased()) ?? ""
                    username.stringValue = lastUser.lowercased()
                } catch {
                    Logger.KrbAuthViewController.debug("Unable to get user's password")
                }
            }
        }
    }
    
    @objc func popUpChange() async {
        if accountsList.selectedItem?.title == "Other..." {
            Task { @MainActor in
                accountsList.isHidden = true
                username.isHidden = false
                username.becomeFirstResponder()
            }
        }
        
        for account in await accountsManager.accounts {
            if account.displayName == accountsList.selectedItem?.title.replacingOccurrences(of: " ◀︎", with: "") {
                if let isInKeychain = account.hasKeychainEntry, isInKeychain {
                    let keyUtil = KeychainManager()
                    do {
                        try password.stringValue = keyUtil.retrievePassword(forUsername: account.upn.lowercased()) ?? ""
                    } catch {
                        Logger.KrbAuthViewController.debug("Unable to get user's password")
                    }
                }
            }
        }
        
        Task { @MainActor in
            password.stringValue = ""
        }
    }
}

extension KrbAuthViewController: dogeADUserSessionDelegate {
    func dogeADAuthenticationSucceded() async {
        Logger.authUI.debug("Auth succeded")
        do {
            _ = try await cliTask("kswitch -p \(self.session?.userPrincipal ?? "")")
        } catch {
            Logger.authUI.error("cliTask kswitch -p error: \(error.localizedDescription)")
        }
        
        await session?.userInfo()
        
        if let principal = session?.userPrincipal {
            if let account = await accountsManager.accountForPrincipal(principal: principal) {
                let pwm = KeychainManager()
                do {
                    try pwm.saveCredential(forUsername: account.upn.lowercased(), andPassword: password.stringValue)
                    Logger.authUI.debug("Password updated in keychain")
                } catch {
                    Logger.authUI.debug("Failed saving password in keychain")
                }
            } else {
                let newAccount = DogeAccount(displayName: principal, upn: principal, hasKeychainEntry: prefs.bool(for: .useKeychain))
                let pwm = KeychainManager()
                do {
                    try pwm.saveCredential(forUsername: principal.lowercased(), andPassword: password.stringValue)
                    Logger.authUI.debug("Password updated in keychain")
                } catch {
                    Logger.authUI.debug("Error saving password in Keychain")
                }
                await accountsManager.addAccount(account: newAccount)
            }
        }
        NotificationCenter.default.post(name: .nsmNotification, object: nil, userInfo: ["krbAuthenticated": MounterError.krbAuthSuccessful])
    }
    
    func dogeADAuthenticationFailed(error: dogeADSessionError, description: String) async {
        Logger.authUI.info("Error: \(description, privacy: .public)")
        
        for account in await accountsManager.accounts {
            if account.upn.lowercased() == session?.userPrincipal.lowercased() {
                let pwm = KeychainManager()
                do {
                    try pwm.removeCredential(forUsername: account.upn.lowercased())
                    Logger.authUI.debug("Password removed from Keychain")
                } catch {
                    Logger.authUI.debug("Error removong password from Keychain")
                }
            }
        }
        stopOperations()
        showAlert(message: description)
    }
    
    func dogeADUserInformation(user: ADUserRecord) {
        Logger.authUI.debug("User info: \(user.userPrincipal, privacy: .public)")
        
        // back to the foreground to change the UI
        Task { @MainActor in
            prefs.setADUserInfo(user: user)
            stopOperations()
            closeWindow()
        }
    }
}
