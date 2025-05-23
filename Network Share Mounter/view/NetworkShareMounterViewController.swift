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
import Sparkle

class NetworkShareMounterViewController: NSViewController, NSTableViewDelegate, NSTableViewDataSource, NSPopoverDelegate {
    
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
    
    var updater: SPUUpdater?
    // swiftlint:enable force_cast
    
    // toggle to show user defined or managed shares
    var showManagedShares = false
    
    let popover = NSPopover()
    
    let accountsManager = AccountsManager.shared
    
    // MARK: - initialize view
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.delegate = self
        
        NotificationCenter.default.addObserver(self, selector: #selector(handleErrorNotification(_:)), name: .nsmNotification, object: nil)
        
        if let krbRealm = self.prefs.string(for: .kerberosRealm), !krbRealm.isEmpty {
            Logger.app.info("Enabling Kerberos Realm \(krbRealm, privacy: .public).")
            self.enableKerberos = true
        } else {
            Logger.app.info("No Kerberos Realm found.")
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
        Task {
            let hasShares = await appDelegate.mounter!.shareManager.hasShares()
            additionalSharesText.isHidden = !hasShares
            additionalSharesText.stringValue = NSLocalizedString("managed-shares-text", comment: "Label for additional/managed shares")
        }
    }
    
    override func viewWillAppear() {
        if prefs.bool(for: .enableAutoUpdater) == true {
            updateCheckbox.isHidden = false
            updater = appDelegate.updaterController?.updater
            updateCheckbox.state = updater?.automaticallyChecksForUpdates ?? false ? .on : .off
        } else {
            updateCheckbox.isHidden = true
        }
        super.viewWillAppear()
        Task {
            //
            // hide kerberos authenticate button if no krb domain is set
            dogeAuthenticateButton.isHidden = (prefs.string(for: .kerberosRealm) ?? "").isEmpty
            dogeAuthenticateHelp.isHidden = (prefs.string(for: .kerberosRealm) ?? "").isEmpty
            dogeAuthenticateButton.title = NSLocalizedString("krb-auth-button", comment: "Button text for kerberos authentication")
            
            //
            // copy all mdm and user defined shares to a local array
            // if there is an authentication error show those shares without password
            if appDelegate.mounter!.errorStatus == .authenticationError { 
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
                let accounts = await accountsManager.accounts
                let accountsCount = accounts.count
                for account in await accountsManager.accounts {
                    if !prefs.bool(for: .singleUserMode) || account.upn == prefs.string(for: .lastUser) || accountsCount == 1 {
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
    }
    
    @IBAction func updateCheckboxToggled(_ sender: Any) {
        Logger.activityController.debug("🔄 User has manually switched automatic updates to: \(String((sender as AnyObject).state == .on), privacy: .public)")
        updater?.automaticallyChecksForUpdates = ((sender as AnyObject).state == .on)
    }
    
    @IBOutlet weak var updateCheckbox: NSButton!
    
    @IBOutlet weak var networShareMounterExplanation: NSTextField!
    
    @IBOutlet weak var additionalSharesText: NSTextField!
    
    @IBOutlet weak var appVersion: NSTextField!
    
    @IBOutlet weak var usersNewShare: NSTextField!
    
    @IBOutlet weak var modifyShareButton: NSButton!
    
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
        tableView.reloadData()
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
    
    @IBOutlet weak var sendDiagnosticsRadioButton: NSButton!
    
    @IBOutlet weak var tableView: NSTableView!
    
    @IBOutlet weak var removeShareButton: NSButton!
    

    
    @IBAction func tableViewClicked(_ sender: NSTabView) {
        if tableView.clickedRow >= 0 {
            if tableView.clickedColumn == 0 {
                // swiftlint:disable force_cast
                let HelpPopoverShareStatusViewController = self.storyboard?.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("HelpPopoverShareStatusViewController"))
                    as! HelpPopoverShareStatusViewController
                // swiftlint:enable force_cast
                let popover = NSPopover()
                popover.contentViewController = HelpPopoverShareStatusViewController
//                helpPopoverViewController.helpText = helpText[(sender as AnyObject).tag]
                popover.animates = true
                popover.behavior = .transient
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
            Task {
                if let selectedShare = await appDelegate.mounter!.getShare(forNetworkShare: usersNewShare.stringValue) {
                    Logger.networkShareViewController.debug("unmounting share \(selectedShare.networkShare, privacy: .public)")
                    await self.appDelegate.mounter!.unmountShare(for: selectedShare)
                    Logger.networkShareViewController.info("⚠️ User removed share \(selectedShare.networkShare, privacy: .public)")
                    await self.appDelegate.mounter!.removeShare(for: selectedShare)
                    // update userDefaults
                    await self.appDelegate.mounter!.shareManager.saveModifiedShareConfigs()
                    // remove share from local userShares array bound to tableView
                    self.userShares = self.userShares.filter { $0.networkShare != usersNewShare.stringValue }
                    usersNewShare.stringValue=""
                    tableView.reloadData()
                }
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
        Task {
            if segue.identifier == "ShareViewSegue" {
                // swiftlint:disable force_cast
                let shareViewController = segue.destinationController as! ShareViewController
                // swiftlint:enable force_cast
                // callback action for data coming from shareViewController
                shareViewController.callback = { [weak self] result in
                                guard let self = self else { return }
                        if self.appDelegate.mounter!.errorStatus == .authenticationError {
                            self.refreshUserArray(type: .missingPassword)
                        } else if self.toggleManagedSwitch.state == NSControl.StateValue.off {
                            self.refreshUserArray(type: .unmanaged)
                        } else {
                            self.refreshUserArray(type: .managed)
                        }
                        self.tableView.reloadData()
                }
                if let selectedShare = await appDelegate.mounter!.shareManager.allShares.first(where: {$0.networkShare == usersNewShare.stringValue}) {
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
    }
    
    ///
    ///private function to check if a networkShare should added to the list of displayed shares
    ///- Parameter type: enum of various types of shares to check for
    private func refreshUserArray(type: DisplayShareTypes) {
        Task {
            await appDelegate.mounter!.shareManager.allShares.forEach { definedShare in
                // set mount symbol
                var mountSymbol =   (definedShare.mountStatus == .mounted) ? MountStatusDescription.mounted.symbolName :
                (definedShare.mountStatus == .queued) ? MountStatusDescription.queued.symbolName :
                (definedShare.mountStatus == .invalidCredentials) ? MountStatusDescription.invalidCredentials.symbolName :
                (definedShare.mountStatus == .errorOnMount) ? MountStatusDescription.errorOnMount.symbolName :
                (definedShare.mountStatus == .obstructingDirectory) ? MountStatusDescription.obstructingDirectory.symbolName :
                (definedShare.mountStatus == .unreachable) ? MountStatusDescription.unreachable.symbolName :
                MountStatusDescription.unknown.symbolName
                let mountColor =    (definedShare.mountStatus == .mounted) ? MountStatusDescription.mounted.color :
                (definedShare.mountStatus == .queued) ? MountStatusDescription.queued.color :
                (definedShare.mountStatus == .invalidCredentials) ? MountStatusDescription.invalidCredentials.color :
                (definedShare.mountStatus == .errorOnMount) ? MountStatusDescription.errorOnMount.color :
                (definedShare.mountStatus == .obstructingDirectory) ? MountStatusDescription.obstructingDirectory.color :
                (definedShare.mountStatus == .unreachable) ? MountStatusDescription.unreachable.color :
                MountStatusDescription.unknown.color
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
                    mountSymbol = MountStatusDescription.invalidCredentials.symbolName
                }
                
                if shouldAppend {
                    // check and skip if share is already in userShares
                    if !userShares.contains(where: { $0.networkShare == definedShare.networkShare }) {
                        userShares.append(UserShare(networkShare: definedShare.networkShare,
                                                    authType: definedShare.authType.rawValue,
                                                    username: definedShare.username,
                                                    password: definedShare.password,
                                                    mountPoint: definedShare.mountPoint,
                                                    managed: definedShare.managed,
                                                    mountStatus: definedShare.mountStatus.rawValue,
                                                    mountSymbol: mountSymbol,
                                                    symbolColor: mountColor))
                    }
                }
            }
            tableView.reloadData()
        }
    }
    ///
    /// provide a method to react to certain events
    @objc func handleErrorNotification(_ notification: NSNotification) {
        // Always dispatch UI updates to the main thread
        DispatchQueue.main.async {
            if notification.userInfo?["krbOffDomain"] is Error {
                self.dogeAuthenticateButton.isEnabled = false
                self.dogeAuthenticateHelp.isEnabled = false
                self.dogeAuthenticateButton.title = NSLocalizedString("krb-offdomain-button", comment: "Button text for kerberos authentication")
            } else if notification.userInfo?["KrbAuthError"] is Error {
                if self.enableKerberos {
                    self.dogeAuthenticateButton.isEnabled = true
                    self.dogeAuthenticateHelp.isEnabled = true
                    self.dogeAuthenticateButton.title =  NSLocalizedString("missing-krb-auth-button", comment: "Button text for missing kerberos authentication")
                }
            } else if notification.userInfo?["krbAuthenticated"] is Error {
                if self.enableKerberos {
                    self.dogeAuthenticateButton.isEnabled = true
                    self.dogeAuthenticateHelp.isEnabled = true
                    self.dogeAuthenticateButton.title = NSLocalizedString("krb-auth-button", comment: "Button text for kerberos authentication")
                }
            } else if notification.userInfo?["AuthError"] is MounterError {
                // Update UI for authentication errors
                Task {
                    self.refreshUserArray(type: .missingPassword)
                    self.toggleManagedSwitch.isHidden = true
                    self.additionalSharesText.isHidden = true
                    self.additionalSharesHelpButton.isHidden = true
                    self.modifyShareButton.title = NSLocalizedString("authenticate-share-button", comment: "Button text to change authentication")
                    self.networShareMounterExplanation.stringValue = NSLocalizedString("help-auth-error", comment: "Help text shown if some shares are not authenticated")
                    self.tableView.reloadData()
                }
            }
        }
    }
    
    
    func numberOfRows(in tableView: NSTableView) -> Int {
        return userShares.count
    }
    
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let userShare = userShares[row]
        
        if tableColumn?.identifier == NSUserInterfaceItemIdentifier("NetworkShareColumn") {
            let cellIdentifier = NSUserInterfaceItemIdentifier("NetworkShareCell")
            guard let cell = tableView.makeView(withIdentifier: cellIdentifier, owner: nil) as? NSTableCellView else {
                return nil
            }
            cell.textField?.stringValue = userShare.networkShare
            return cell
        } else if tableColumn?.identifier == NSUserInterfaceItemIdentifier("MountSymbolColumn") {
            let cellIdentifier = NSUserInterfaceItemIdentifier("MountSymbolCell")
            guard let cell = tableView.makeView(withIdentifier: cellIdentifier, owner: nil) as? NSTableCellView else {
                return nil
            }
            if let imageView = cell.imageView {
                if let symbolImage = NSImage(systemSymbolName: userShare.mountSymbol, accessibilityDescription: nil) {
                    if let color = userShare.symbolColor {
                        // changing color for SF Symbols is available on macOS >= 12
                        if #available(macOS 12.0, *) {
                            let config = NSImage.SymbolConfiguration(paletteColors: [color])
                            imageView.image = symbolImage.withSymbolConfiguration(config)
                        } else {
                            imageView.image = symbolImage
                        }
                    } else {
                        imageView.image = symbolImage
                    }
                } else {
                    imageView.image = nil
                }
            }
            return cell
        }
        return nil
    }
}
