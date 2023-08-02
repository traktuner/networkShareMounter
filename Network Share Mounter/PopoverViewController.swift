//
//  PopoverViewController.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 26.06.23.
//  Copyright © 2023 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Cocoa

class PopoverViewController: NSViewController, NSTextFieldDelegate {
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do view setup here.
        let shares: [String] = UserDefaults.standard.array(forKey: Settings.networkSharesKey) as? [String] ?? []
        var sharesString: String = ""
        shares.forEach {
            sharesString.append($0)
            sharesString.append("\n")
        }
        
        listOfShares.stringValue = "\(sharesString)"
    }
    
    @IBOutlet weak var listOfShares: NSTextField!
    
}
