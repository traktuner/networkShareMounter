//
//  ShareViewController.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 14.11.23.
//  Copyright © 2023 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation
import Cocoa

class ShareViewController: NSViewController {
    
    // Share struct
    struct ShareData {
        var networkShare: URL
        var authType: AuthType
        var username: String?
        var password: String?
        var mountPath: String?
    }
    
    // MARK: - Properties
    
    var shareData: ShareData?
    var authType: AuthType = AuthType.krb
    
    // MARK: - Outlets
    
    @IBOutlet private weak var networkShareTextField: NSTextField!
    @IBOutlet private weak var authTypeSwitch: NSSwitch!
    @IBOutlet private weak var usernameTextField: NSTextField!
    @IBOutlet private weak var passwordTextField: NSSecureTextField!
    @IBOutlet private weak var mountPathTextField: NSTextField!
    @IBOutlet weak var networkShareAddressInfo: NSButton!
    @IBOutlet weak var authTypeInfo: NSButton!
    @IBOutlet weak var authenticationInfo: NSButton!
    @IBOutlet weak var mountPointInfo: NSButton!
    
    // MARK: - View Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureView()
        networkShareAddressInfo.image = NSImage(named: NSImage.Name("240px-info"))
        authTypeInfo.image = NSImage(named: NSImage.Name("240px-info"))
        authenticationInfo.image = NSImage(named: NSImage.Name("240px-info"))
        mountPointInfo.image = NSImage(named: NSImage.Name("240px-info"))
    }
    
    // MARK: - Actions
    
    @IBAction private func saveButtonTapped(_ sender: NSButton) {
        let networkShareText = networkShareTextField.stringValue
        guard let networkShareURL = URL(string: networkShareText) else {
            // Handle invalid input
            return
        }
        let networkShare = networkShareTextField.stringValue
//        let authTypeString = authTypePopUpButton.selectedItem?.title,
//        let authType = AuthType(rawValue: authTypeString)
        let username = usernameTextField.stringValue
        let password = passwordTextField.stringValue
        let mountPath = mountPathTextField.stringValue
        
        let shareData = ShareData(networkShare: networkShareURL, authType: authType, username: username, password: password, mountPath: mountPath)
        
        // Do something with the share data
        
        dismiss(nil)
    }
    
    
    @IBAction func authTypeSwitchChanged(_ sender: Any) {
        if authTypeSwitch.state == NSControl.StateValue.on {
            authType = AuthType.pwd
            usernameTextField.isEnabled = true
            passwordTextField.isEnabled = true
        } else {
            authType = AuthType.krb
            usernameTextField.isEnabled = false
            passwordTextField.isEnabled = false
        }
    }
    
    @IBAction func networkShareAddressInfoPressed(_ sender: Any) {
        let popoverShareViewController = self.storyboard?.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier("PopoverInfoViewController")) as? NSViewController
        let popover = NSPopover()
        popover.contentViewController = popoverShareViewController
        popover.animates = true
        // swiftlint:disable force_cast
        let button = sender as! NSButton
        // swiftlint:enable force_cast
        popover.show(relativeTo: button.frame, of: self.view, preferredEdge: NSRectEdge.minY)
        popover.behavior = NSPopover.Behavior.transient
    }
    
    @IBAction func authTypeInfoPressed(_ sender: Any) {
    }
    
    @IBAction func authenticationInfoPressed(_ sender: Any) {
    }
    
    @IBAction func mountPointInfoPressed(_ sender: Any) {
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
        mountPathTextField.stringValue = shareData.mountPath ?? ""
    }
}
