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

class KrbAuthViewController: NSViewController {
    
    let userDefaults = UserDefaults.standard
    
    @IBOutlet weak var logo: NSImageView!
    @IBOutlet weak var usernameText: NSTextField!
    @IBOutlet weak var passwordText: NSTextField!
    @IBOutlet weak var username: NSTextField!
    @IBOutlet weak var password: NSTextField!
    @IBOutlet weak var krbAuthInfoText: NSTextField!
    @IBOutlet weak var authenticateButtonText: NSButton!
    @IBOutlet weak var cancelButtonText: NSButton!
    
    @IBAction func authenticateKlicked(_ sender: Any) {
        
    }
    
    @IBAction func cancelKlicked(_ sender: Any) {
    }
    
    // MARK: - initialize view
    override func viewDidLoad() {
        super.viewDidLoad()
        // force unwrap is ok since authenticationDialogImage is a registered default in AppDelegate
        logo.image = NSImage(named: userDefaults.string(forKey: Settings.authenticationDialogImage)!)
        usernameText.stringValue = NSLocalizedString("authui-username-text", comment: "value shown as username")
        passwordText.stringValue = NSLocalizedString("authui-password-text", comment: "value shown as username")
        authenticateButtonText.stringValue = NSLocalizedString("auth-button-text", comment: "text on authenticate button")
        cancelButtonText.stringValue = NSLocalizedString("cancel", comment: "cancel")
        
    }
}
