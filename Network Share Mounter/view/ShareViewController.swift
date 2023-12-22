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
    
    var callback: ((Share?) -> Void)?
    
    // Share struct
    struct ShareData {
        var networkShare: URL
        var authType: AuthType
        var username: String?
        var password: String?
        var mountPath: String?
        var managed: Bool
    }
    
    // MARK: - help messages
    var helpText = [NSLocalizedString("Sorry, no help available", comment: "this should not happen"),
                    NSLocalizedString("help-new-share", comment: ""),
                    NSLocalizedString("help-authType", comment: ""),
                    NSLocalizedString("help-username", comment: ""),
                    NSLocalizedString("help-password", comment: "")]
    
    // MARK: - Properties
    
    var selectedShareURL: String?
    var shareData: ShareData?
    var isManaged = false
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
    @IBOutlet weak var saveButton: NSButton!
    
    @IBOutlet weak var progressIndicator: NSProgressIndicator!
    @IBOutlet weak var shareAddressText: NSTextField!
    @IBOutlet weak var authTypeText: NSTextField!
    @IBOutlet weak var shareViewText: NSTextField!
    @IBOutlet weak var authTypeHelpButton: NSButton!
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
        progressIndicator.isHidden = true
        authType = AuthType.pwd
        shareArray = appDelegate.mounter.shareManager.allShares
        
        // check if NetworkShareMounter View has set selectedShareURL
        // if yes, prefill the data
        if let shareString = selectedShareURL {
            if let selectedShare = shareArray.filter({$0.networkShare == shareString}).first {
                saveButton.title =  NSLocalizedString("Save", comment: "Save data")
                networkShareTextField.stringValue = selectedShare.networkShare
                isManaged = selectedShare.managed
                // if the share is managed only username and password should be changed
                if selectedShare.managed {
                    networkShareTextField.isEditable = false
                    authTypeSwitch.isEnabled = false
                    authTypeSwitch.isHidden = true
                    authTypeText.isHidden = true
                    authTypeHelpButton.isHidden = true
                    shareViewText.isHidden = true
                } else {
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
    }
    
    // MARK: - Actions
    
    @IBAction private func saveButtonTapped(_ sender: NSButton) {
        Task { @MainActor in
            let networkShareText = self.networkShareTextField.stringValue
            guard let networkShareURL = URL(string: networkShareText) else {
                // TODO: Handle invalid input
                return
            }
            let username = usernameTextField.stringValue
            let password = passwordTextField.stringValue
            
            let shareData = ShareData(networkShare: networkShareURL, authType: authType, username: username, password: password, managed: isManaged)
            
            let shareURL = networkShareText.replacingOccurrences(of: " ", with: "_")
            if shareURL.isValidURL {
                progressIndicator.isHidden = false
                saveButton.isEnabled = false
                progressIndicator.startAnimation(self)
                if let newShare = await handleShareURL(networkShareText: networkShareText, shareData: shareData) {
                    callback?(newShare)
                    dismiss(nil)
//                    self.view.window?.windowController?.close()
                } else {
                    
                }
            }
        }
    }
    
    
    ///
    /// check if share is new or an existing share should be updated
    /// - Parameter networkShareText: String containig the URL of a share
    /// - Parameter shareData: ShareData Struct containing relevant share data
    private func handleShareURL(networkShareText: String, shareData: ShareData) async -> Share? {
        if networkShareText.hasPrefix("smb://") || networkShareText.hasPrefix("cifs://") || networkShareText.hasPrefix("https://") || networkShareText.hasPrefix("afp://") {
            let newShare = Share.createShare(networkShare: networkShareText, authType: shareData.authType, mountStatus: .unmounted, username: shareData.username, password: shareData.password, managed: shareData.managed)

            if shareArray.contains(where: { $0.networkShare == newShare.networkShare }) {
                if let existingShare = appDelegate.mounter.getShare(forNetworkShare: newShare.networkShare) {
                    self.logger.debug("Updating existing share \(networkShareText, privacy: .public).")
                    if await updateExistingShare(existingShare: existingShare, newShare: newShare, networkShareText: networkShareText) {
                        return nil
                    }
                }
            } else {
                if await addNewShare(newShare: newShare, networkShareText: networkShareText) {
                    return newShare
                }
            }
        } else {
            // not valid share entered
            self.logger.error("\(networkShareText, privacy: .public) is not a valid share, since it does not start with smb://, cifs://, afp:// or http://")
            showErrorDialog(error: MounterError.errorOnEncodingShareURL)
            progressIndicator.stopAnimation(self)
            progressIndicator.isHidden = true
            saveButton.isEnabled = true
        }
        return nil
    }
    
    ///
    /// update an existing share
    /// - Parameter existingShare: Share struct containing data of an existing share entry
    /// - Parameter newShare: Share struct containig changed data to update
    /// - Parameter networkShareText: String contianing the URL of the share
    private func updateExistingShare(existingShare: Share, newShare: Share, networkShareText: String) async -> Bool {
        self.appDelegate.mounter.unmountShare(for: existingShare)
        do {
            let returned = try await self.appDelegate.mounter.mountShare(forShare: newShare, atPath: self.appDelegate.mounter.defaultMountPath)
            logger.debug("Mounting of new share \(networkShareText, privacy: .public) succeded: \(returned, privacy: .public)")
            self.appDelegate.mounter.updateShare(for: newShare)
            self.appDelegate.mounter.shareManager.saveModifiedShareConfigs()
            NotificationCenter.default.post(name: .nsmNotification, object: nil, userInfo: ["ClearError": MounterError.noError])
            return true
        } catch {
            // share did not mount, reset it to the former state
            self.appDelegate.mounter.updateShare(for: existingShare)
            self.appDelegate.mounter.shareManager.saveModifiedShareConfigs()
            logger.warning("Mounting of new share \(networkShareText, privacy: .public) failed: \(error, privacy: .public)")
            showErrorDialog(error: error)
            progressIndicator.stopAnimation(self)
            progressIndicator.isHidden = true
            saveButton.isEnabled = true
            return false
        }
    }
    
    ///
    /// add a new share
    /// - Parameter newShare: Share struct containing the relevant data to add a share
    /// - Parameter networkShareText: String with the URL of the share
    private func addNewShare(newShare: Share, networkShareText: String) async -> Bool {
        do {
            let returned = try await self.appDelegate.mounter.mountShare(forShare: newShare, atPath: self.appDelegate.mounter.defaultMountPath)
            logger.debug("Mounting of new share \(networkShareText, privacy: .public) succeded: \(returned, privacy: .public)")
            self.appDelegate.mounter.addShare(newShare)
            self.appDelegate.mounter.shareManager.saveModifiedShareConfigs()
            return true
        } catch {
            // share did not mount, remove it from the array of shares
            self.appDelegate.mounter.removeShare(for: newShare)
            self.appDelegate.mounter.shareManager.saveModifiedShareConfigs()
            logger.warning("Mounting of new share \(networkShareText, privacy: .public) failed: \(error, privacy: .public)")
            showErrorDialog(error: error)
            progressIndicator.stopAnimation(self)
            progressIndicator.isHidden = true
            saveButton.isEnabled = true
            return false
        }
    }
    
    ///
    /// show dialog to inform user what went worng
    /// - Parameter error: Error type containing the error code to display
    private func showErrorDialog(error: Error) {
        let alert: NSAlert = NSAlert()
        alert.messageText = "\(error.localizedDescription)"
        alert.informativeText = NSLocalizedString("Please check the data entered", comment: "Please check the data entered")
        alert.addButton(withTitle: "OK")
        alert.alertStyle = NSAlert.Style.warning

        if let viewWindow = self.view.window {
            alert.beginSheetModal(for: viewWindow, completionHandler: { (modalResponse: NSApplication.ModalResponse) -> Void in
                if(modalResponse == NSApplication.ModalResponse.alertFirstButtonReturn){
                    self.logger.debug("User informed about error \(error, privacy: .public)")
                }
            })
        }
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
