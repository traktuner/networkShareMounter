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
        RunLoop.main.perform {
            self.buildAccountsMenu()
        }
    }
    
    
    
    // MARK: - help messages
    var helpText = [NSLocalizedString("Sorry, no help available", comment: "this should not happen"),
                    NSLocalizedString("authui-infotext", comment: "")]
    
    let workQueue = DispatchQueue(label: "de.fau.networkShareMounter.kerberos", qos: .userInteractive, attributes:[], autoreleaseFrequency: .never, target: nil)
    
    var session: dogeADSession?
    var prefs = PreferenceManager()
    
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
        self.session = dogeADSession.init(domain: self.username.stringValue.userDomain() ?? prefs.string(for: .kerberosRealm) ?? "", user: self.username.stringValue)
        session?.setupSessionFromPrefs(prefs: prefs)
        session?.userPass = password.stringValue
        session?.delegate = self
//        workQueue.async {
        Task {
            self.session?.authenticate()
        }
    }
    
    @IBAction func cancelKlicked(_ sender: Any) {
        dismiss(nil)
    }
    
    // MARK: - initialize view
    override func viewDidLoad() {
        super.viewDidLoad()
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
        
        buildAccountsMenu()
        accountsList.action = #selector(popUpChange)
        AccountsManager.shared.delegates.append(self)
        
    }
    
    @IBAction func helpButtonClicked(_ sender: NSButton) {
        // swiftlint:disable force_cast
        let helpPopoverViewController = self.storyboard?.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("HelpPopoverViewController")) as! HelpPopoverViewController
        // swiftlint:enable force_cast
        let popover = NSPopover()
        popover.contentViewController = helpPopoverViewController
        helpPopoverViewController.helpText = helpText[sender.tag]
        popover.animates = true
        popover.show(relativeTo: sender.frame, of: self.view, preferredEdge: NSRectEdge.minY)
        popover.behavior = NSPopover.Behavior.transient
    }
    
    /// start some UI operations like spinner animation, buttons are not clickable
    /// text fields are not editable and so on
    fileprivate func startOperations() {
        RunLoop.main.perform {
            self.spinner.isHidden = false
            self.spinner.startAnimation(nil)
            self.authenticateButtonText.isEnabled = false
            self.cancelButtonText.isEnabled = false
            self.username.isEditable = false
            self.password.isEditable = false
        }
    }
    
    /// stop some UI operations like spinner animation, buttons are clickable
    /// text fields are editable and so on
    fileprivate func stopOperations() {
        RunLoop.main.perform {
            self.spinner.isHidden = true
            self.spinner.stopAnimation(nil)
            self.authenticateButtonText.isEnabled = true
            self.cancelButtonText.isEnabled = true
            self.username.isEditable = true
            self.password.isEditable = true
        }
    }
    
    private func showAlert(message: String) {
        RunLoop.main.perform {
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
            case "Preauthentication failed" :
                text = "Incorrect username or password."
            case "Password has expired" :
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
        self.stopOperations()
        self.session = nil
    }
    
    private func closeWindow() {
        RunLoop.main.perform {
            self.dismiss(nil)
        }
    }
    
    private func buildAccountsMenu() {
        
        let klist = KlistUtil()
        let tickets = klist.klist()
        
        // populate popup list if there is more than one account
        if AccountsManager.shared.accounts.count > 1 && !prefs.bool(for: .singleUserMode) {
            self.accountsList.removeAllItems()
            for account in AccountsManager.shared.accounts {
                if tickets.contains(where: { $0.principal.lowercased() == account.upn.lowercased()}) {
                    self.accountsList.addItem(withTitle: account.displayName + " ◀︎")
                } else {
                    self.accountsList.addItem(withTitle: account.displayName)
                }
            }
            self.accountsList.addItem(withTitle: "Other...")
            self.username.isHidden = true
            self.accountsList.isHidden = false
            self.accountsList.isEnabled = true
            popUpChange()
            return
        }
        
        // if there is only one account, hide popup list
        self.accountsList.isHidden = true
        self.username.isHidden = false
        if let lastUser = prefs.string(for: .lastUser) {//}, prefs.bool(for: .useKeychain) {
            let keyUtil = KeychainManager()
            do {
                try self.password.stringValue = keyUtil.retrievePassword(forUsername: lastUser.lowercased()) ?? ""
                self.username.stringValue = lastUser.lowercased()
            } catch {
                Logger.KrbAuthViewController.debug("Unable to get user's password")
            }
        }
    }
    
    @objc func popUpChange() {
        if self.accountsList.selectedItem?.title == "Other..." {
            RunLoop.main.perform {
                self.accountsList.isHidden = true
                self.username.isHidden = false
                self.username.becomeFirstResponder()
            }
        }
        
        for account in AccountsManager.shared.accounts {
            if account.displayName == self.accountsList.selectedItem?.title.replacingOccurrences(of: " ◀︎", with: "") {
                if let isInKeychain = account.hasKeychainEntry, isInKeychain {
                    let keyUtil = KeychainManager()
                    do {
                        try self.password.stringValue = keyUtil.retrievePassword(forUsername: account.upn.lowercased()) ?? ""
                    } catch {
                        Logger.KrbAuthViewController.debug("Unable to get user's password")
                    }
                }
            }
        }
        
        RunLoop.main.perform {
            self.password.stringValue = ""
        }
    }
}


extension KrbAuthViewController: dogeADUserSessionDelegate {
    
    func dogeADAuthenticationSucceded() {
        Logger.authUI.debug("Auth succeded")
        cliTask("kswitch -p \(self.session?.userPrincipal ?? "")")
        
        self.session?.userInfo()
        
        if let principal = session?.userPrincipal {
            if let account = AccountsManager.shared.accountForPrincipal(principal: principal) {
                let pwm = KeychainManager()
                Task {
                    do {
                        try pwm.saveCredential(forUsername: account.upn.lowercased(), andPassword: self.password.stringValue)
                        Logger.authUI.debug("Password updated in keychain")
                    } catch {
                        Logger.authUI.debug("Failed saving password in keychain")
                    }
                }
            } else {
                let newAccount = DogeAccount(displayName: principal, upn: principal, hasKeychainEntry: prefs.bool(for: .useKeychain))
                let pwm = KeychainManager()
                Task {
                    do {
                        try pwm.saveCredential(forUsername: principal.lowercased(), andPassword: self.password.stringValue)
                        Logger.authUI.debug("Password updated in keychain")
                    } catch {
                        Logger.authUI.debug("Error saving password in Keychain")
                    }
                }
                AccountsManager.shared.addAccount(account: newAccount)
            }
        }
    }
    
    func dogeADAuthenticationFailed(error: dogeADSessionError, description: String) {
        Logger.authUI.info("Error: \(description, privacy: .public)")
        
        for account in AccountsManager.shared.accounts {
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
        RunLoop.main.perform {
            self.prefs.setADUserInfo(user: user)
            self.stopOperations()
            self.closeWindow()
        }
    }
}
