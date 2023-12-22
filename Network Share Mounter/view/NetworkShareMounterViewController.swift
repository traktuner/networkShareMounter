//
//  NetworkShareMounterViewController.swift
//  Network Share Mounter
//
//  Created by Gregor Longariva on 24.11.21.
//  Copyright © 2021 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Cocoa
import LaunchAtLogin
import OSLog

class NetworkShareMounterViewController: NSViewController, NSPopoverDelegate {
    
    ///
    /// enum containig type of shares to display in the tableView
    /// managed: share is managed, whether krb or pwd
    /// unmanaged: share is unmanage, whether krb or pwd
    /// pwd: share is password authenticated, whether managed or unmanaged
    /// krb: share is kerbeors authenticated, whether managed or unmanaged
    /// managedPwd: share is managed and password authenticated
    /// managedOrPwd: share is managed or password authenticated
    enum displayShareTypes: String {
        case managed = "managed"
        case unmanaged = "unmanaged"
        case pwd = "pwd"
        case krb = "krb"
        case managedAndPwd = "managedPwd"
        case managedOrPwd = "managedOrPwd"
        case missingPassword = "missingPassword"
    }
    
    // MARK: - help messages
    var helpText = [NSLocalizedString("Sorry, no help available", comment: "this should not happen"),
                    NSLocalizedString("help-show-managed-shares", comment: "")]

    let userDefaults = UserDefaults.standard

    @objc dynamic var launchAtLogin = LaunchAtLogin.kvo
    // prepare an array of type UserShare to store the defined shares while showing this view
    @objc dynamic var userShares: [UserShare] = []
    
    // swiftlint:disable force_cast
    // appDelegate is used to accesss variables in AppDelegate
    let appDelegate = NSApplication.shared.delegate as! AppDelegate
    // swiftlint:enable force_cast
    
    let logger = Logger(subsystem: "NetworkShareMounter", category: "NSMViewController")
    
    // toggle to show user defined or managed shares
    var showManagedShares = false
    
    let popover = NSPopover()
    

    // MARK: - initialize view
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.delegate = self
        
        //
        // copy all mdm and user defined shares to a local array
        refreshUserArray(type: .unmanaged)

        modifyShareButton.isEnabled = false
        removeShareButton.isEnabled = false

        if userDefaults.bool(forKey: "canChangeAutostart") == false {
            launchAtLoginRadioButton.isHidden = true
            horizontalLine.isHidden = true
        }

        //
        // create an action to react on user clicks in tableview
        tableView.action = #selector(handleClickColumn)
    
        //
        // get build and version number of the app
        let applicationVersion = Bundle.main.infoDictionary!["CFBundleShortVersionString"]!
        let applicationBuild = Bundle.main.infoDictionary!["CFBundleVersion"]!
        appVersion.stringValue = "Version: \(applicationVersion) (\(applicationBuild))"
        
        if  appDelegate.mounter.shareManager.allShares.isEmpty {
            additionalSharesText.title = ""
        } else {
            additionalSharesText.title = NSLocalizedString("Additional shares", comment: "Additional shares")
        }
//        let symbolConfig = NSImage.SymbolConfiguration(scale: .large)
//
//        if let symbolImage = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: "Help") {
//            let resizedImage = symbolImage.withSymbolConfiguration(symbolConfig)
//            
//            managedSharesHelp.image = resizedImage
//            managedSharesHelp.imageScaling = .scaleProportionallyDown
//        }
//        managedSharesHelp.image = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: "Help")
    }

    @objc func handleClickColumn() {
        if tableView.clickedRow >= 0 {
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
    }

    @IBOutlet weak var appVersion: NSTextField!
    
    @IBOutlet weak var usersNewShare: NSTextField!

    @IBOutlet weak var modifyShareButton: NSButton!

    @IBOutlet var shareArrayController: NSArrayController!
    
    @IBOutlet weak var toggleManagedSwitch: NSSwitch!
    
    @IBOutlet weak var managedSharesHelp: NSButton!
    
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
    
    @IBOutlet weak var horizontalLine: NSBox!
    
    @IBOutlet weak var launchAtLoginRadioButton: NSButton!

    @IBOutlet weak var tableView: NSTableView!

    @IBOutlet weak var removeShareButton: NSButton!
    
    @IBOutlet weak var additionalSharesText: NSTextFieldCell!
    
    /// IBAction function called if removeShare button is pressed.
    /// This will remove the share in the selected row in tableView
    @IBAction func removeShare(_ sender: NSButton) {
        let row = self.tableView.selectedRow
        // this if is probably not needed, but I feel safer with it ;-)
        if row >= 0 {
            // if a share with the selected name is found, delete it
            if let selectedShare = appDelegate.mounter.getShare(forNetworkShare: usersNewShare.stringValue) {
                self.logger.debug("unmounting share \(selectedShare.networkShare, privacy: .public)")
                self.appDelegate.mounter.unmountShare(for: selectedShare)
                self.logger.info("⚠️ User removed share \(selectedShare.networkShare, privacy: .public)")
                self.appDelegate.mounter.removeShare(for: selectedShare)
                // update userDefaults
                self.appDelegate.mounter.shareManager.saveModifiedShareConfigs()
                // remove share from local userShares array bound to tableView
                self.userShares = self.userShares.filter { $0.networkShare != usersNewShare.stringValue }
//                self.tableView.reloadData()
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
            let shareViewController = segue.destinationController as! ShareViewController
            // callback action for data coming from shareViewController
            shareViewController.callback = { result in
                if let newShare = result {
                    // swiftlint:enable force_cast
                    self.userShares.append(UserShare(networkShare: newShare.networkShare,
                                                     authType: (newShare.authType.rawValue),
                                                     username: newShare.username,
                                                     password: newShare.password,
                                                     mountPoint: newShare.mountPoint,
                                                     managed: newShare.managed,
                                                     mountStatus: newShare.mountStatus.rawValue))
                    self.tableView.reloadData()
                }
            }
            if let selectedShare = appDelegate.mounter.shareManager.allShares.first(where: {$0.networkShare == usersNewShare.stringValue}) {
                    // pass the value in the field usersNewShare. This is an optional, so it can be empty if a
                    // new share will be added
                    shareViewController.shareData = ShareViewController.ShareData(networkShare: URL(string: selectedShare.networkShare)!, authType: selectedShare.authType, username: selectedShare.username, password: selectedShare.password, managed: selectedShare.managed)
                    shareViewController.selectedShareURL = usersNewShare.stringValue
            }
        }
    }
    
    ///
    ///private function to check if a networkShare should added to the list of displayed shares
    ///- Parameter type: enum of various types of shares to check for
    private func refreshUserArray(type: displayShareTypes) {
        appDelegate.mounter.shareManager.allShares.forEach { definedShare in

            let shouldAppend: Bool
            switch type {
                case .managed:
                    shouldAppend = definedShare.managed
                case .krb:
                    shouldAppend = definedShare.authType == .krb
                case .pwd:
                    shouldAppend = definedShare.authType == .pwd
                case .managedOrPwd:
                    shouldAppend = definedShare.authType == .pwd || definedShare.managed
                case .managedAndPwd:
                    shouldAppend = definedShare.authType == .pwd && definedShare.managed
                case .unmanaged:
                    shouldAppend = !definedShare.managed
                case .missingPassword:
                    shouldAppend = definedShare.authType == .pwd && (definedShare.password == "" || definedShare.password == nil)
            }

            if shouldAppend {
                self.userShares.append(UserShare(networkShare: definedShare.networkShare,
                                                 authType: definedShare.authType.rawValue,
                                                 username: definedShare.username,
                                                 password: definedShare.password,
                                                 mountPoint: definedShare.mountPoint,
                                                 managed: definedShare.managed,
                                                 mountStatus: definedShare.mountStatus.rawValue))
            }
        }
    }
}

extension NetworkShareMounterViewController: NSTableViewDelegate {

}

extension String {
    /// Extension for ``String`` to check if the string itself is a valid URL
    /// - Returns: true if the string is a valid URL
    var isValidURL: Bool {
        // swiftlint:disable force_try
        let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        // swiftlint:denable force_try
        if let match = detector.firstMatch(in: self, options: [], range: NSRange(location: 0, length: self.utf16.count)) {
            // it is a link, if the match covers the whole string
            return match.range.length == self.utf16.count
        } else {
            return false
        }
    }
}
