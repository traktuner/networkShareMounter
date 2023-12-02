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

class NetworkShareMounterViewController: NSViewController, NSPopoverDelegate, DataDelegate {
    func didReceiveData(_ data: Any) {
        print("Data is \(data)")
        // swiftlint:disable force_cast
        let newShare = data as! Share
        // swiftlint:enable force_cast
        self.userShares.append(UserShare(networkShare: newShare.networkShare,
                                         authType: (newShare.authType == AuthType.pwd ? true : false),
                                         username: newShare.username,
                                         password: newShare.password,
                                         mountPoint: newShare.mountPoint,
                                         managed: newShare.managed))
        self.tableView.reloadData()
    }
    

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
    

    // MARK: - initialize view
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.delegate = self
        
        //
        // copy all mdm and user defined shares to a local array
        for definedShare in appDelegate.mounter.shareManager.allShares {
            //
            // on load select those which are not managed
            if !definedShare.managed {
                userShares.append(UserShare(networkShare: definedShare.networkShare, 
                                            authType: true,
                                            username: definedShare.username,
                                            password: definedShare.password,
                                            mountPoint: definedShare.mountPoint,
                                            managed: definedShare.managed))
            }
        }

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
        
//        let shares: [String] = UserDefaults.standard.array(forKey: Settings.networkSharesKey) as? [String] ?? []
        if  appDelegate.mounter.shareManager.allShares.isEmpty {
            additionalSharesText.title = ""
        } else {
            additionalSharesText.title = NSLocalizedString("Additional shares", comment: "Additional shares")
        }
    }

    @objc func handleClickColumn() {
        if tableView.clickedRow >= 0 && toggleManagedSwitch.state == NSControl.StateValue.off {
            if !self.userShares[tableView.selectedRow].managed {
                removeShareButton.isEnabled = true
                modifyShareButton.isEnabled = true
                usersNewShare.stringValue =  self.userShares[tableView.selectedRow].networkShare
            }
        } else {
            removeShareButton.isEnabled = false
            modifyShareButton.isEnabled = false
            usersNewShare.stringValue=""
        }
    }

    @IBOutlet weak var appVersion: NSTextField!
    
    @IBOutlet weak var usersNewShare: NSTextField!

    @IBOutlet weak var modifyShareButton: NSButton!

    @IBOutlet var shareArrayController: NSArrayController!
    
    @IBOutlet weak var toggleManagedSwitch: NSSwitch!
    
    
    /// function toggle between managed shares and user defined shares
    @IBAction func toggleManagedSharesAction(_ sender: Any) {
        if toggleManagedSwitch.state == NSControl.StateValue.off {
            showManagedShares = false
            self.userShares.removeAll()
            modifyShareButton.isEnabled = false
            addNewShareButton.isEnabled = true
            usersNewShare.stringValue=""
            for definedShare in appDelegate.mounter.shareManager.allShares {
                if !definedShare.managed {
                    self.userShares.append(UserShare(networkShare: definedShare.networkShare,
                                                     authType: true,
                                                     username: definedShare.username,
                                                     password: definedShare.password,
                                                     mountPoint: definedShare.mountPoint,
                                                     managed: definedShare.managed))
                }
            }
        } else {
            showManagedShares = true
            removeShareButton.isEnabled = false
            self.userShares.removeAll()
            modifyShareButton.isEnabled = false
            addNewShareButton.isEnabled = false
            usersNewShare.stringValue=""
            for definedShare in appDelegate.mounter.shareManager.allShares {
                if definedShare.managed {
                    self.userShares.append(UserShare(networkShare: definedShare.networkShare,
                                                     authType: true,
                                                     username: definedShare.username,
                                                     password: definedShare.password,
                                                     mountPoint: definedShare.mountPoint,
                                                     managed: definedShare.managed))
                }
            }
        }
    }
    
    /// function to prepare to hand over the object for the user-selected tableview column (aka share URL)
    @IBAction func modifyShare(_ sender: NSButton) {
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
            if let selectedShare = appDelegate.mounter.shareManager.allShares.first(where: {$0.networkShare == usersNewShare.stringValue}) {
                self.logger.info("⚠️ User removed share \(selectedShare.networkShare, privacy: .public)")
                appDelegate.mounter.removeShare(for: selectedShare)
                // update userDefaults
                appDelegate.mounter.shareManager.writeUserShareConfigs()
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
            if let shareViewController = segue.destinationController as? ShareViewController {
                // pass the value in the field usersNewShare. This is an optional, so it can be empty if a
                // new share will be added
                shareViewController.delegate = self
                shareViewController.selectedShareURL = usersNewShare.stringValue
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

protocol DataDelegate: class {
    func didReceiveData(_ data: Any)
}

