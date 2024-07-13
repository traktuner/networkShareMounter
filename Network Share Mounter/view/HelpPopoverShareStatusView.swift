//
//  HelpPopoverShareStatusView.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 12.07.24.
//  Copyright © 2024 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation
import Cocoa

class HelpPopoverShareStatusView: NSViewController {
    var helpItems: [(symbolName: String, symbolColor: NSColor, description: String)] = []
    
    @IBOutlet weak var stackView: NSStackView!
    
    @IBOutlet weak var mountedText: NSTextField!
    @IBOutlet weak var queuedText: NSTextField!
    @IBOutlet weak var invalidCredentialsText: NSTextField!
    @IBOutlet weak var errorOnMountText: NSTextField!
    @IBOutlet weak var obstructingDirectoryText: NSTextField!
    @IBOutlet weak var unreachableText: NSTextField!
    @IBOutlet weak var unknownText: NSTextField!
    
    @IBOutlet weak var mountedImage: NSImageView!
    @IBOutlet weak var queuedImage: NSImageView!
    @IBOutlet weak var invaliudCredentialsImage: NSImageView!
    @IBOutlet weak var errorOnMountImage: NSImageView!
    @IBOutlet weak var obstructingDirectoryImage: NSImageView!
    @IBOutlet weak var unreachableImage: NSImageView!
    @IBOutlet weak var unknownImage: NSImageView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
//        setupHelpItems()
    }
    
//    private func setupHelpItems() {
//        for item in helpItems {
//            if let helpItemView = loadHelpItemView() {
//                helpItemView.configure(symbolName: item.symbolName, symbolColor: item.symbolColor, description: item.description)
//                stackView.addArrangedSubview(helpItemView)
//            }
//        }
//    }
    
//    private func loadHelpItemView() -> HelpItemView? {
//        var topLevelObjects: NSArray? = nil
//        let nib = NSNib(nibNamed: "HelpItemView", bundle: nil)
//        nib?.instantiate(withOwner: self, topLevelObjects: &topLevelObjects)
//        return topLevelObjects?.first(where: { $0 is HelpItemView }) as? HelpItemView
//    }
}
