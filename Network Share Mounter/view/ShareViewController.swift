//  ShareViewController.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 14.11.23.
//  Copyright © 2023 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation
import Cocoa
import OSLog

class ShareViewController: NSViewController {
    
    // Share struct
    struct ShareData {
        var networkShare: URL
        var authType: AuthType
        var username: String?
        var password: String?
        var mountPath: String?
    }
    
    // MARK: - help messages
    var helpText = [NSLocalizedString("Sorry, no help available", comment: "this should not happen"),
                    NSLocalizedString("help-new-share", comment: ""),
                    NSLocalizedString("help-authType", comment: ""),
                    NSLocalizedString("help-uername", comment: ""),
                    NSLocalizedString("help-password", comment: "")]
    
    // MARK: - Properties
    
    var selectedShareURL: String?
    var shareData: ShareData?
    var authType: AuthType = AuthType.krb
    var shareArray : [Share] = []
    
    // MARK: - Outlets
    
    @IBOutlet private weak var networkShareTextField: NSTextField!
    @IBOutlet private weak var authTypeSwitch: NSSwitch!
    @IBOutlet private weak var usernameTextField: NSTextField!
    @IBOutlet private weak var passwordTextField: NSSecureTextField!
    @IBOutlet weak var usernameText: NSTextField!
    @IBOutlet weak var authInfoHelpButton: NSButton!
    @IBOutlet weak var passwordText: NSTextField!
    @IBOutlet weak var shareHelpButton: NSButton!
    @IBOutlet weak var usernameHelpButton: NSButton!
    @IBOutlet weak var passwordHelpButton: NSButton!
    
    // MARK: - initialization
    
    // swiftlint:disable force_cast
    // appDelegate is used to accesss variables in AppDelegate
    let appDelegate = NSApplication.shared.delegate as! AppDelegate
    // swiftlint:enable force_cast
    let logger = Logger(subsystem: "NetworkShareMounter", category: "ShareViewController")
    
    // MARK: - View Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureView()
        shareArray = appDelegate.mounter.shareManager.allShares
        authInfoHelpButton.image = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: "Help")
        shareHelpButton.image = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: "Help")
        usernameHelpButton.image = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: "Help")
        passwordHelpButton.image = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: "Help")
        // check if NetworkShareMounter View has set selectedShareURL
        // if yes, prefill the data
        if let shareString = selectedShareURL {
            if let selectedShare = shareArray.filter({$0.networkShare == shareString}).first {
                networkShareTextField.stringValue = selectedShare.networkShare
                if selectedShare.authType == AuthType.pwd {
                    authTypeSwitch.state = NSControl.StateValue.off
                    authType = AuthType.pwd
                    usernameTextField.isEnabled = true
                    passwordTextField.isEnabled = true
                    usernameTextField.isHidden = false
                    passwordTextField.isHidden = false
                    usernameHelpButton.isHidden = false
                    passwordHelpButton.isHidden = false
                    usernameText.isHidden = false
                    passwordText.isHidden = false
                    usernameTextField.stringValue = selectedShare.username ?? ""
                    passwordTextField.stringValue = selectedShare.password ?? ""
                } else {
                    authTypeSwitch.state = NSControl.StateValue.on
                    authType = AuthType.krb
                    usernameTextField.isEnabled = false
                    passwordTextField.isEnabled = false
                    usernameTextField.isHidden = true
                    passwordTextField.isHidden = true
                    usernameHelpButton.isHidden = true
                    passwordHelpButton.isHidden = true
                    usernameText.isHidden = true
                    passwordText.isHidden = true
                }
            }
        }
    }
    
    // MARK: - Actions
    
    @IBAction private func saveButtonTapped(_ sender: NSButton) {
        let networkShareText = networkShareTextField.stringValue
        guard let networkShareURL = URL(string: networkShareText) else {
            // TODO: Handle invalid input
            return
        }
        let networkShare = networkShareTextField.stringValue
//        let authTypeString = authTypePopUpButton.selectedItem?.title,
//        let authType = AuthType(rawValue: authTypeString)
        let username = usernameTextField.stringValue
        let password = passwordTextField.stringValue
        
        let shareData = ShareData(networkShare: networkShareURL, authType: authType, username: username, password: password)
        
        // Do something with the share data
        
        // TODO: Import from NetworkShareMounterViewController
//        let shareString = usersNewShare.stringValue
        // if the share URL string contains a space, the URL vill not
        // validate as valid. Therefore we replace the " " with a "_"
        // and test this string.
        // Of course this is a hack and not the best way to solve the
        // problem. But hey, every now and then I code, I am obbligated
        // to cheat. ¯\_(ツ)_/¯
        let shareURL = networkShareText.replacingOccurrences(of: " ", with: "_")
        if shareURL.isValidURL {
            if networkShareText.hasPrefix("smb://") || networkShareText.hasPrefix("cifs://") {
                // TODO: check if share is already in list of shares
//                var shareArray = userDefaults.object(forKey: Settings.customSharesKey) as? [String] ?? [String]()
//                if shareArray.contains(shareString) {
//                    self.logger.debug("\(shareString, privacy: .public) is already in list of user's customNetworkShares")
//                } else {
                var newShare: Share
                if username.isEmpty {
                    newShare = Share.createShare(networkShare: networkShareText, authType: .krb, mountStatus: .unmounted, managed: false)
                } else {
                    newShare = Share.createShare(networkShare: networkShareText, authType: .pwd, mountStatus: .unmounted, username: username, password: password, managed: false)
                }
                    appDelegate.mounter.addShare(newShare)
                    Task {
                        do {
                                try await appDelegate.mounter.mountShare(forShare: newShare, atPath: appDelegate.mounter.defaultMountPath)
                            // add the new share to the app-internal array to display personal shares
//                            shareArray.append(usersNewShare.stringValue)
//                            userDefaults.set(shareArray, forKey: Settings.customSharesKey)
//                            usersNewShare.stringValue=""
                            dismiss(nil)
                        } catch {
                            // share did not mount, remove it from the array of shares
                            appDelegate.mounter.removeShare(for: newShare)
//                            logger.warning("Mounting of new share \(self.usersNewShare.stringValue, privacy: .public) failed: \(error, privacy: .public)")
                            logger.warning("Mounting of new share \(networkShareText, privacy: .public) failed: \(error, privacy: .public)")
                        }
                    }
//                }
            } else {
                
            }
        }
//        dismiss(nil)
    }
    
    
    @IBAction func authTypeSwitchChanged(_ sender: Any) {
        if authTypeSwitch.state == NSControl.StateValue.off {
            authType = AuthType.pwd
            usernameTextField.isEnabled = true
            passwordTextField.isEnabled = true
            usernameTextField.isHidden = false
            passwordTextField.isHidden = false
            usernameHelpButton.isHidden = false
            passwordHelpButton.isHidden = false
            usernameText.isHidden = false
            passwordText.isHidden = false
        } else {
            authType = AuthType.krb
            usernameTextField.isEnabled = false
            passwordTextField.isEnabled = false
            usernameTextField.isHidden = true
            passwordTextField.isHidden = true
            usernameHelpButton.isHidden = true
            passwordHelpButton.isHidden = true
            usernameText.isHidden = true
            passwordText.isHidden = true
        }
    }
    
    let popover = NSPopover()
        
//        @IBAction func helpButtonClicked(_ sender: NSButton) {
//            
//            let helpPopoverViewController = HelpPopoverViewController()
//            helpPopoverViewController.helpText = "This is the help text for button \(helpButton.tag)"
//            
//            popover.contentViewController = helpPopoverViewController
//            popover.show(relativeTo: helpButton.bounds, of: helpButton, preferredEdge: .maxY)
//        }
    
    @IBAction func helpButtonClicked(_ sender: NSButton) {
        let helpPopoverViewController = self.storyboard?.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("HelpPopoverViewController")) as! HelpPopoverViewController
        let popover = NSPopover()
        popover.contentViewController = helpPopoverViewController
//        helpPopoverViewController.helpText = "This is the help text for button \(sender.tag)"
        helpPopoverViewController.helpText = helpText[sender.tag]
        popover.animates = true
        popover.show(relativeTo: sender.frame, of: self.view, preferredEdge: NSRectEdge.minY)
        popover.behavior = NSPopover.Behavior.transient
    }
    
    @IBAction private func cancelButtonTapped(_ sender: NSButton) {
        dismiss(nil)
    }
    
    // MARK: - Private Methods
    
    private func configureView() {
        guard let shareData = shareData else {
            return
        }
        
        networkShareTextField.stringValue = shareData.networkShare.absoluteString
        authTypeSwitch.state = NSControl.StateValue.off
        usernameTextField.stringValue = shareData.username ?? ""
        passwordTextField.stringValue = shareData.password ?? ""
        authTypeSwitch.state = NSControl.StateValue.off
        authType = AuthType.pwd
        usernameTextField.isEnabled = true
        passwordTextField.isEnabled = true
        usernameTextField.isHidden = false
        passwordTextField.isHidden = false
        usernameText.isHidden = false
        passwordText.isHidden = false
    }
}
