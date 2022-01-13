//
//  NetworkShareMounterViewController.swift
//  Network Share Mounter
//
//  Created by Gregor Longariva on 24.11.21.
//  Copyright © 2021 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Cocoa
import LaunchAtLogin

class NetworkShareMounterViewController: NSViewController {

    let userDefaults = UserDefaults.standard

    @objc dynamic var launchAtLogin = LaunchAtLogin.kvo

    // let customshares = UserDefaults(suiteName: config.defaultsDomain)?.array(forKey: "customNetworkShares") as? [String] ?? []

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.delegate = self

        addShareButton.isEnabled = true
        removeShareButton.isEnabled = false

        if userDefaults.bool(forKey: "canChangeAutostart") == false {
            launchAtLoginRadioButton.isHidden = true
        }

        tableView.action = #selector(handleClickColumn)
    }

    @objc func handleClickColumn() {
        if tableView.clickedRow >= 0 {
            removeShareButton.isEnabled = true
        } else {
            removeShareButton.isEnabled = false
        }
    }

    @IBOutlet weak var usersNewShare: NSTextField!

    @IBOutlet weak var addShareButton: NSButton!

    @IBAction func addShare(_ sender: NSButton) {
        let shareString = usersNewShare.stringValue

        if shareString.isValidURL {
            if shareString.hasPrefix("smb://") || shareString.hasPrefix("cifs://") {
                var shareArray = userDefaults.object(forKey: "customNetworkShares") as? [String] ?? [String]()
                if shareArray.contains(shareString) {
                    NSLog("\(shareString) is already in list of user's customNetworkShares")
                } else {
                    let mounter = Mounter.init()
                    do {
                        try mounter.doTheMount(forShare: usersNewShare.stringValue)
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

    @IBOutlet weak var launchAtLoginRadioButton: NSButton!

    @IBOutlet weak var tableView: NSTableView!

    @IBOutlet weak var removeShareButton: NSButton!

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
