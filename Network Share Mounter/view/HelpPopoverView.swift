//
//  HelpPopoverView.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 15.11.23.
//  Copyright © 2023 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation
import Cocoa
import OSLog

class HelpPopoverViewController: NSViewController {
    var helpText: String = "help"
    override func viewDidLoad() {
        super.viewDidLoad()
        helpTextLabel.stringValue = helpText
    }
    
    @IBOutlet weak var helpTextLabel: NSTextField!
}
