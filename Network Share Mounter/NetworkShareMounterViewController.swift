//
//  NetworkShareMounterViewController.swift
//  Network Share Mounter
//
//  Created by Gregor Longariva on 24.11.21.
//  Copyright © 2021 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Cocoa
import LaunchAtLogin

class NetworkShareMounterViewController: NSViewController, NSPopoverDelegate {

    let userDefaults = UserDefaults.standard

    @objc dynamic var launchAtLogin = LaunchAtLogin.kvo
    
    // swiftlint:disable force_cast
    let appDelegate = NSApplication.shared.delegate as! AppDelegate
    // swiftlint:enable force_cast

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.delegate = self

        addShareButton.isEnabled = true
        removeShareButton.isEnabled = false

        if userDefaults.bool(forKey: "canChangeAutostart") == false {
            launchAtLoginRadioButton.isHidden = true
            horizontalLine.isHidden = true
        }

        tableView.action = #selector(handleClickColumn)
    
        //
        // get build and version number of the app
        let applicationVersion = Bundle.main.infoDictionary!["CFBundleShortVersionString"]!
        let applicationBuild = Bundle.main.infoDictionary!["CFBundleVersion"]!
        appVersion.stringValue = "Version: \(applicationVersion) (\(applicationBuild))"
        
        let shares: [String] = UserDefaults.standard.array(forKey: "networkShares") as? [String] ?? []
        if shares.isEmpty {
            showPopoverButton.isHidden = true
            additionalSharesText.title = ""
        } else {
            showPopoverButton.image = NSImage(named: NSImage.Name("240px-info"))
            additionalSharesText.title = NSLocalizedString("Additional shares", comment: "Additional shares")
        }
    }

    @objc func handleClickColumn() {
        if tableView.clickedRow >= 0 {
            removeShareButton.isEnabled = true
        } else {
            removeShareButton.isEnabled = false
        }
    }

    @IBOutlet weak var appVersion: NSTextField!
    
    @IBOutlet weak var usersNewShare: NSTextField!

    @IBOutlet weak var addShareButton: NSButton!

    @IBAction func addShare(_ sender: NSButton) {
        let shareString = usersNewShare.stringValue
        // if the share URL string contains a space, the URL vill not
        // validate as valid. Therefore we replace the " " with a "_"
        // and test those string.
        // Of course this is a hack and not the best way to solve the
        // problem. But hey, every saturday I code, I am obbligated
        // to cheat. ¯\_(ツ)_/¯ 
        let shareURL = shareString.replacingOccurrences(of: " ",
                                                       with: "_")
        if shareURL.isValidURL {
            if shareString.hasPrefix("smb://") || shareString.hasPrefix("cifs://") {
                var shareArray = userDefaults.object(forKey: "customNetworkShares") as? [String] ?? [String]()
                if shareArray.contains(shareString) {
                    NSLog("\(shareString) is already in list of user's customNetworkShares")
                } else {
                    do {
                        try appDelegate.mounter.doTheMount(forShare: usersNewShare.stringValue)
                        shareArray.append(usersNewShare.stringValue)
                        userDefaults.set(shareArray, forKey: "customNetworkShares")
                        usersNewShare.stringValue=""
                    } catch let error as NSError {
                        NSLog("Mounting of new share \(usersNewShare.stringValue) failed: \(error)")
                    }
                }                
            }
        }
    }

    @IBOutlet weak var showPopover: NSButtonCell!

    @IBOutlet weak var horizontalLine: NSBox!
    
    @IBOutlet weak var launchAtLoginRadioButton: NSButton!

    @IBOutlet weak var tableView: NSTableView!

    @IBOutlet weak var removeShareButton: NSButton!

    @IBOutlet weak var showPopoverButton: NSButton!
    
    @IBOutlet weak var additionalSharesText: NSTextFieldCell!
    
    @IBAction func removeShare(_ sender: NSButton) {
        let row = self.tableView.selectedRow
        if row >= 0 {
            var shareArray = userDefaults.object(forKey: "customNetworkShares") as? [String] ?? [String]()
            shareArray.remove(at: row)
            userDefaults.set(shareArray, forKey: "customNetworkShares")
            //UserDefaults.standard.set(shareArray, forKey: "customNetworkShares")
            // tableView.removeRows(at: IndexSet(integer:row), withAnimation:.effectFade)
        }
    }

    @IBAction func showPopover(_ sender: Any) {
        let popoverViewController = self.storyboard?.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("PopoverViewController")) as? NSViewController
        let popover = NSPopover()
        popover.contentViewController = popoverViewController
        popover.animates = true
        // swiftlint:disable force_cast
        let button = sender as! NSButton
        // swiftlint:enable force_cast
        popover.show(relativeTo: button.frame, of: self.view, preferredEdge: NSRectEdge.minY)
        popover.behavior = NSPopover.Behavior.transient
    }
    
    // MARK: Storyboard instantiation
    static func newInsatnce() -> NetworkShareMounterViewController {
        let storyboard = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: nil)
        let identifier = NSStoryboard.SceneIdentifier("NetworkShareMounterViewController")

        guard let viewcontroller = storyboard.instantiateController(withIdentifier: identifier) as? NetworkShareMounterViewController else {
            fatalError("Unable to instantiate ViewController in Main.storyboard")
        }
        return viewcontroller
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
