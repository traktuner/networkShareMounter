//
//  NetworkShareMounterViewController.swift
//  Network Share Mounter
//
//  Created by Gregor Longariva on 24.11.21.
//  Copyright © 2024 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Cocoa
import LaunchAtLogin
import OSLog

class NetworkShareMounterViewController: NSViewController, NSPopoverDelegate {

    // MARK: - help messages
    var helpText = [NSLocalizedString("Sorry, no help available", comment: "this should not happen"),
                    NSLocalizedString("help-show-managed-shares", comment: ""),
                    NSLocalizedString("mount-status-info-text", comment: ""),
                    NSLocalizedString("help-krb-auth-text", comment: "")]

    var prefs = PreferenceManager()
    
    var enableKerberos = false

    @objc dynamic var launchAtLogin = LaunchAtLogin.kvo
    // prepare an array of type UserShare to store the defined shares while showing this view
    @objc dynamic var userShares: [UserShare] = []
    
    // swiftlint:disable force_cast
    // appDelegate is used to accesss variables in AppDelegate
    let appDelegate = NSApplication.shared.delegate as! AppDelegate
    
    // swiftlint:enable force_cast
    
    // toggle to show user defined or managed shares
    var showManagedShares = false
    
    let popover = NSPopover()
    

    // MARK: - initialize view
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.delegate = self
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleErrorNotification(_:)), name: .nsmNotification, object: nil)
        
        if let krbRealm = self.prefs.string(for: .kerberosRealm), !krbRealm.isEmpty {
            self.enableKerberos = true
        }
        
        modifyShareButton.isEnabled = false
        removeShareButton.isEnabled = false

        if prefs.bool(for: .canChangeAutostart) == false {
            launchAtLoginRadioButton.isHidden = true
            horizontalLine.isHidden = true
        }
    
        //
        // get build and version number of the app
        let applicationVersion = Bundle.main.infoDictionary!["CFBundleShortVersionString"]!
        let applicationBuild = Bundle.main.infoDictionary!["CFBundleVersion"]!
        appVersion.stringValue = "Version: \(applicationVersion) (\(applicationBuild))"
        
        if  appDelegate.mounter.shareManager.allShares.isEmpty {
            additionalSharesText.isHidden = true
        } else {
            additionalSharesText.isHidden = false
        }
        
        additionalSharesText.stringValue = NSLocalizedString("managed-shares-text", comment: "Label for additional/managed shares")
    }
    
    override func viewWillAppear() {
        super.viewWillAppear()
        
        //
        // hide kerberos authenticate button if no krb domain is set
        dogeAuthenticateButton.isHidden = (prefs.string(for: .kerberosRealm) ?? "").isEmpty
        dogeAuthenticateHelp.isHidden = (prefs.string(for: .kerberosRealm) ?? "").isEmpty
        dogeAuthenticateButton.title = NSLocalizedString("krb-auth-button", comment: "Button text for kerberos authentication")
            
        //
        // copy all mdm and user defined shares to a local array
        // if there is an authentication error show thos shares without password
        if appDelegate.mounter.errorStatus == .authenticationError {
            refreshUserArray(type: .missingPassword)
            toggleManagedSwitch.isHidden = true
            additionalSharesText.isHidden = true
            additionalSharesHelpButton.isHidden = true
            modifyShareButton.title = NSLocalizedString("authenticate-share-button", comment: "Button text to change authentication")
            networShareMounterExplanation.stringValue = NSLocalizedString("help-auth-error", comment: "Help text shown if some shares are not authenticated")
        //
        // else fill the array with user defined shares
        } else {
            refreshUserArray(type: .unmanaged)
            toggleManagedSwitch.isHidden = false
            additionalSharesText.isHidden = false
            additionalSharesHelpButton.isHidden = false
            modifyShareButton.title = NSLocalizedString("modify-share-button", comment: "Button text to modify share")
            networShareMounterExplanation.stringValue = NSLocalizedString("help-new-share", comment: "Help text with some infos about adding new shares")
        }
        if self.enableKerberos {
            for account in AccountsManager.shared.accounts {
                if !prefs.bool(for: .singleUserMode) || account.upn == prefs.string(for: .lastUser) || AccountsManager.shared.accounts.count == 1 {
                    let pwm = KeychainManager()
                    do {
                        if let _ = try pwm.retrievePassword(forUsername: account.upn.lowercased()) {
                            break
                        }
                    } catch {
                            dogeAuthenticateButton.title =  NSLocalizedString("missing-krb-auth-button", comment: "Button text for missing kerberos authentication")
                            performSegue(withIdentifier: "KrbAuthViewSegue", sender: self)
                            break
                    }
                }
            }
        }
    }

    @IBOutlet weak var networShareMounterExplanation: NSTextField!
    
    @IBOutlet weak var additionalSharesText: NSTextField!
    
    @IBOutlet weak var appVersion: NSTextField!
    
    @IBOutlet weak var usersNewShare: NSTextField!

    @IBOutlet weak var modifyShareButton: NSButton!

    @IBOutlet var shareArrayController: NSArrayController!
    
    @IBOutlet weak var toggleManagedSwitch: NSSwitch!
    
    @IBOutlet weak var managedSharesHelp: NSButton!
    
    @IBOutlet weak var dogeAuthenticateButton: NSButton!
    
    @IBOutlet weak var dogeAuthenticateHelp: NSButton!
    
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
    
    
    /// function toggle between managed shares and user defined shares
    @IBAction func toggleManagedSharesAction(_ sender: Any) {
        if toggleManagedSwitch.state == NSControl.StateValue.off {
            showManagedShares = false
            self.userShares.removeAll()
            modifyShareButton.isEnabled = false
            addNewShareButton.isEnabled = true
            usersNewShare.stringValue=""
            refreshUserArray(type: .unmanaged)
        } else {
            showManagedShares = true
            removeShareButton.isEnabled = false
            self.userShares.removeAll()
            modifyShareButton.isEnabled = false
            addNewShareButton.isEnabled = false
            usersNewShare.stringValue=""
            refreshUserArray(type: .managed)
        }
    }
    
    /// function to prepare to hand over the object for the user-selected tableview column (aka share URL)
    @IBAction func modifyShare(_ sender: NSButton) {
        self.performSegue(withIdentifier: "ShareViewSegue", sender: self)
    }
    @IBAction func addSharePressed(_ sender: NSButton) {
        usersNewShare.stringValue=""
        self.performSegue(withIdentifier: "ShareViewSegue", sender: self)
    }
    
    @IBOutlet weak var addNewShareButton: NSButton!
    
    @IBOutlet weak var additionalSharesHelpButton: NSButton!
    
    @IBOutlet weak var horizontalLine: NSBox!
    
    @IBOutlet weak var launchAtLoginRadioButton: NSButton!

    @IBOutlet weak var tableView: NSTableView!

    @IBOutlet weak var removeShareButton: NSButton!
    
    @IBAction func tableViewClicked(_ sender: NSTabView) {
        if tableView.clickedRow >= 0 {
            if tableView.clickedColumn == 0 {
                // swiftlint:disable force_cast
                let helpPopoverViewController = self.storyboard?.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("HelpPopoverViewController")) as! HelpPopoverViewController
                // swiftlint:enable force_cast
                let popover = NSPopover()
                popover.contentViewController = helpPopoverViewController
                helpPopoverViewController.helpText = helpText[(sender as AnyObject).tag]
                popover.animates = true
                popover.behavior = NSPopover.Behavior.transient
                let rowRect = tableView.rect(ofRow: tableView.clickedRow)
                popover.show(relativeTo: rowRect, of: sender, preferredEdge: NSRectEdge.maxY)
            } else {
                // if share is not managed
                removeShareButton.isEnabled = false
                modifyShareButton.isEnabled = false
                usersNewShare.stringValue=""
                if !self.userShares[tableView.selectedRow].managed ||
                    // or authType for share is password
                    self.userShares[tableView.selectedRow].authType == AuthType.pwd.rawValue {
                    
                    removeShareButton.isEnabled = true
                    modifyShareButton.isEnabled = true
                    usersNewShare.stringValue =  self.userShares[tableView.selectedRow].networkShare
                    if self.userShares[tableView.selectedRow].managed {
                        removeShareButton.isEnabled = false
                    }
                }
            }
        } else {
            removeShareButton.isEnabled = false
            modifyShareButton.isEnabled = false
        }
    }
    /// IBAction function called if removeShare button is pressed.
    /// This will remove the share in the selected row in tableView
    @IBAction func removeShare(_ sender: NSButton) {
        let row = self.tableView.selectedRow
        // this if is probably not needed, but I feel safer with it ;-)
        if row >= 0 {
            // if a share with the selected name is found, delete it
            if let selectedShare = appDelegate.mounter.getShare(forNetworkShare: usersNewShare.stringValue) {
                Logger.networkShareViewController.debug("unmounting share \(selectedShare.networkShare, privacy: .public)")
                self.appDelegate.mounter.unmountShare(for: selectedShare)
                Logger.networkShareViewController.info("⚠️ User removed share \(selectedShare.networkShare, privacy: .public)")
                self.appDelegate.mounter.removeShare(for: selectedShare)
                // update userDefaults
                self.appDelegate.mounter.shareManager.saveModifiedShareConfigs()
                // remove share from local userShares array bound to tableView
                self.userShares = self.userShares.filter { $0.networkShare != usersNewShare.stringValue }
                usersNewShare.stringValue=""
            }
        }
    }
    
    // MARK: Storyboard instantiation
    static func newInstance() -> NetworkShareMounterViewController {
        let storyboard = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: nil)
        let identifier = NSStoryboard.SceneIdentifier("NetworkShareMounterViewController")

        guard let viewcontroller = storyboard.instantiateController(withIdentifier: identifier) as? NetworkShareMounterViewController else {
            fatalError("Unable to instantiate ViewController in Main.storyboard")
        }
        return viewcontroller
    }
    
    // MARK: prepare segues by setting certain values
    override func prepare(for segue: NSStoryboardSegue, sender: Any?) {
        if segue.identifier == "ShareViewSegue" {
            // swiftlint:disable force_cast
            let shareViewController = segue.destinationController as! ShareViewController
            // swiftlint:enable force_cast
            // callback action for data coming from shareViewController
            shareViewController.callback = { result in
                if result != "cancel" {
                    if self.appDelegate.mounter.errorStatus == .authenticationError {
                        self.refreshUserArray(type: .missingPassword)
                    } else if self.toggleManagedSwitch.state == NSControl.StateValue.off {
                        self.refreshUserArray(type: .unmanaged)
                    } else {
                        self.refreshUserArray(type: .managed)
                    }
                    self.tableView.reloadData()
                }
            }
            if let selectedShare = appDelegate.mounter.shareManager.allShares.first(where: {$0.networkShare == usersNewShare.stringValue}) {
                    // pass the value in the field usersNewShare. This is an optional, so it can be empty if a
                    // new share will be added
                    shareViewController.shareData = ShareViewController.ShareData(networkShare: selectedShare.networkShare, 
                                                                                  authType: selectedShare.authType,
                                                                                  username: selectedShare.username,
                                                                                  password: selectedShare.password,
                                                                                  managed: selectedShare.managed)
                    shareViewController.selectedShareURL = usersNewShare.stringValue
            }
        }
    }
    
    ///
    ///private function to check if a networkShare should added to the list of displayed shares
    ///- Parameter type: enum of various types of shares to check for
    private func refreshUserArray(type: DisplayShareTypes) {
        self.appDelegate.mounter.shareManager.allShares.forEach { definedShare in
            // set mount symbol
            var mountSymbol =   (definedShare.mountStatus == .mounted) ? "🟢" :
                                (definedShare.mountStatus == .queued) ? "🟣" :
                                (definedShare.mountStatus == .invalidCredentials) ? "🟠" :
                                (definedShare.mountStatus == .errorOnMount) ? "🔴":
                                (definedShare.mountStatus == .obstructingDirectory) ? "❗" :
                                "⚪️"
            let shouldAppend: Bool
            switch type {
                case .managed:
                    shouldAppend = definedShare.managed
                case .krb:
                    shouldAppend = definedShare.authType == .krb
                case .pwd:
                    shouldAppend = definedShare.authType == .pwd
                case .guest:
                    shouldAppend = definedShare.authType == .guest
                case .managedOrPwd:
                    shouldAppend = definedShare.authType == .pwd || definedShare.managed
                case .managedAndPwd:
                    shouldAppend = definedShare.authType == .pwd && definedShare.managed
                case .unmanaged:
                    shouldAppend = !definedShare.managed
                case .missingPassword:
                    shouldAppend = definedShare.authType == .pwd && (definedShare.password == "" || definedShare.password == nil)
                    mountSymbol = "🟠"
            }

            if shouldAppend {
                // check and skip if share is already in userShares
                if !self.userShares.contains(where: { $0.networkShare == definedShare.networkShare }) {
                    self.userShares.append(UserShare(networkShare: definedShare.networkShare,
                                                     authType: definedShare.authType.rawValue,
                                                     username: definedShare.username,
                                                     password: definedShare.password,
                                                     mountPoint: definedShare.mountPoint,
                                                     managed: definedShare.managed,
                                                     mountStatus: definedShare.mountStatus.rawValue,
                                                     mountSymbol: mountSymbol))
                }
            }
        }
    }
    ///
    /// provide a method to react to certain events
    @objc func handleErrorNotification(_ notification: NSNotification) {
        if notification.userInfo?["krbOffDomain"] is Error {
            DispatchQueue.main.async {
                self.dogeAuthenticateButton.isEnabled = false
                self.dogeAuthenticateHelp.isEnabled = false
                self.dogeAuthenticateButton.title = NSLocalizedString("krb-offdomain-button", comment: "Button text for kerberos authentication")
            }
        } else if notification.userInfo?["KrbAuthError"] is Error {
            DispatchQueue.main.async {
                if self.enableKerberos {
                    self.dogeAuthenticateButton.isEnabled = true
                    self.dogeAuthenticateHelp.isEnabled = true
                    self.dogeAuthenticateButton.title =  NSLocalizedString("missing-krb-auth-button", comment: "Button text for missing kerberos authentication")
                }
            }
        } else if notification.userInfo?["krbAuthenticated"] is Error {
            DispatchQueue.main.async {
                if self.enableKerberos {
                    self.dogeAuthenticateButton.isEnabled = true
                    self.dogeAuthenticateHelp.isEnabled = true
                    self.dogeAuthenticateButton.title = NSLocalizedString("krb-auth-button", comment: "Button text for kerberos authentication")
                }
            }
        }
    }
}

extension NetworkShareMounterViewController: NSTableViewDelegate {

}
