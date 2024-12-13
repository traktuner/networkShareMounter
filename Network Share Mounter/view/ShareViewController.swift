//  ShareViewController.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 14.11.23.
//  Copyright © 2024 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation
import Cocoa
import OSLog

class ShareViewController: NSViewController {
    
    // MARK: - Types
    struct ShareData {
        var networkShare: String
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
    var callback: ((String?) -> Void)?
    var prefs = PreferenceManager()
    // swiftlint:disable force_cast
    // appDelegate is used to accesss variables in AppDelegate
    let appDelegate = NSApplication.shared.delegate as! AppDelegate
    // swiftlint:enable force_cast
    
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
    
    // MARK: - View Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        Task {
            await configureInitialState()
            await loadAndConfigureShare()
        }
    }
    
    @IBAction private func saveButtonTapped(_ sender: NSButton) {
        Task { @MainActor in
            guard let shareData = createShareData() else { return }
            await handleSave(with: shareData)
        }
    }
    
    @IBAction private func authTypeSwitchChanged(_ sender: Any) {
        configureAuthTypeUI(isKerberos: authTypeSwitch.state == .on)
    }
    
    @IBAction private func helpButtonClicked(_ sender: NSButton) {
        showHelpPopover(for: sender)
    }
    
    @IBAction private func cancelButtonTapped(_ sender: NSButton) {
        callback?("cancel")
        dismiss(nil)
    }
    
    // MARK: - Private Methods
    
    private func configureInitialState() async {
        progressIndicator.isHidden = true
        shareArray = await appDelegate.mounter!.shareManager.getAllShares()
        shareViewText.stringValue = NSLocalizedString("ShareView-Text", comment: "Default text to show on ShareView window")
        authTypeSwitch.isEnabled = !(prefs.string(for: .kerberosRealm) ?? "").isEmpty
    }
    
    private func loadAndConfigureShare() async {
        guard let shareString = selectedShareURL,
              let selectedShare = shareArray.first(where: { $0.networkShare == shareString }) else { return }
        
        await MainActor.run {
            configureShareUI(with: selectedShare)
        }
    }
    
    private func configureShareUI(with share: Share) {
        saveButton.title = NSLocalizedString("Save", comment: "Save data")
        networkShareTextField.stringValue = share.networkShare
        isManaged = share.managed
        
        if share.managed {
            configureManagedShareUI()
        } else {
            configureUnmanagedShareUI(with: share)
        }
    }
    
    private func configureManagedShareUI() {
        networkShareTextField.isEditable = false
        authTypeSwitch.isEnabled = false
        [authTypeSwitch, authTypeText, authTypeHelpButton, shareViewText].forEach { $0?.isHidden = true }
    }
    
    private func configureUnmanagedShareUI(with share: Share) {
        let isPasswordAuth = share.authType == .pwd
        authType = share.authType
        authTypeSwitch.state = isPasswordAuth ? .off : .on
        configureAuthTypeUI(isKerberos: !isPasswordAuth)
        
        if isPasswordAuth {
            usernameTextField.stringValue = share.username ?? ""
            passwordTextField.stringValue = share.password ?? ""
        }
    }
    
    private func configureAuthTypeUI(isKerberos: Bool) {
        authType = isKerberos ? .krb : .pwd
        let authElements = [usernameTextField, passwordTextField, usernameHelpButton,
                          passwordHelpButton, usernameText, passwordText]
        
        authElements.forEach {
            $0?.isEnabled = !isKerberos
            $0?.isHidden = isKerberos
        }
    }
    
    private func createShareData() -> ShareData? {
        let networkShareText = networkShareTextField.stringValue
        guard networkShareText.isValidURL else {
            showErrorDialog(error: MounterError.errorOnEncodingShareURL)
            return nil
        }
        
        return ShareData(
            networkShare: networkShareText,
            authType: authType,
            username: usernameTextField.stringValue,
            password: passwordTextField.stringValue,
            mountPath: nil,
            managed: isManaged
        )
    }
    
    private func handleSave(with shareData: ShareData) async {
        progressIndicator.isHidden = false
        saveButton.isEnabled = false
        progressIndicator.startAnimation(self)
        
        if let _ = await handleShareURL(networkShareText: shareData.networkShare, shareData: shareData) {
            progressIndicator.isHidden = true
            callback?("save")
            dismiss(nil)
        } else {
            progressIndicator.isHidden = true
            dismiss(nil)
        }
    }
    
    private func showHelpPopover(for sender: NSButton) {
        // swiftlint:disable force_cast
        let helpPopoverViewController = storyboard?.instantiateController(
            withIdentifier: NSStoryboard.SceneIdentifier("HelpPopoverViewController")
        ) as! HelpPopoverViewController
        // swiftlint:enable force_cast
        
        let popover = NSPopover()
        popover.contentViewController = helpPopoverViewController
        helpPopoverViewController.helpText = helpText[sender.tag]
        popover.animates = true
        popover.behavior = .transient
        popover.show(relativeTo: sender.frame, of: view, preferredEdge: .minY)
    }
    
    
    ///
    /// check if share is new or an existing share should be updated
    /// - Parameter networkShareText: String containig the URL of a share
    /// - Parameter shareData: ShareData Struct containing relevant share data
    private func handleShareURL(networkShareText: String, shareData: ShareData) async -> Share? {
        if networkShareText.hasPrefix("smb://") || networkShareText.hasPrefix("cifs://") || networkShareText.hasPrefix("https://") || networkShareText.hasPrefix("afp://") {
            let newShare = Share.createShare(networkShare: networkShareText, authType: shareData.authType, mountStatus: .unmounted, username: shareData.username, password: shareData.password, managed: shareData.managed)

            if shareArray.contains(where: { $0.networkShare == newShare.networkShare }) {
                if let existingShare = await appDelegate.mounter!.getShare(forNetworkShare: newShare.networkShare) {
                    Logger.shareViewController.debug("Updating existing share \(networkShareText, privacy: .public).")
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
            Logger.shareViewController.error("\(networkShareText, privacy: .public) is not a valid share, since it does not start with smb://, cifs://, afp:// or http://")
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
        await self.appDelegate.mounter!.unmountShare(for: existingShare)
        do {
            let returned = try await self.appDelegate.mounter!.mountShare(forShare: newShare, atPath: self.appDelegate.mounter!.defaultMountPath)
            Logger.shareViewController.debug("Mounting of new share \(networkShareText, privacy: .public) succeded: \(returned, privacy: .public)")
            await self.appDelegate.mounter!.updateShare(for: newShare)
            await self.appDelegate.mounter!.shareManager.saveModifiedShareConfigs()
            NotificationCenter.default.post(name: .nsmNotification, object: nil, userInfo: ["ClearError": MounterError.noError])
            return true
        } catch {
            // share did not mount, reset it to the former state
            await self.appDelegate.mounter!.updateShare(for: existingShare)
            await self.appDelegate.mounter!.shareManager.saveModifiedShareConfigs()
            Logger.shareViewController.warning("Mounting of new share \(networkShareText, privacy: .public) failed: \(error, privacy: .public)")
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
            let returned = try await self.appDelegate.mounter!.mountShare(forShare: newShare, atPath: self.appDelegate.mounter!.defaultMountPath)
            Logger.shareViewController.debug("Mounting of new share \(networkShareText, privacy: .public) succeded: \(returned, privacy: .public)")
            await self.appDelegate.mounter!.addShare(newShare)
            await self.appDelegate.mounter!.shareManager.saveModifiedShareConfigs()
            return true
        } catch {
            // share did not mount, remove it from the array of shares
            await self.appDelegate.mounter!.removeShare(for: newShare)
            await self.appDelegate.mounter!.shareManager.saveModifiedShareConfigs()
            Logger.shareViewController.warning("Mounting of new share \(networkShareText, privacy: .public) failed: \(error, privacy: .public)")
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
        // TODO: Unfortunately, two modal views on top of each other don't work as hoped. If I close the alert, the view underneath
        //  is also closed. I have to take a look at it
        alert.runModal()
    }
}
