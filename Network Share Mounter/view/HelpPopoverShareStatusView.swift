//
//  HelpPopoverShareStatusView.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 12.07.24.
//  Copyright © 2024 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation
import Cocoa

class HelpPopoverShareStatusViewController: NSViewController {
    let helpItems = MountStatusDescription.allCases.map { status in
        (status.symbolName, status.color, status.localizedDescription)
    }
    

    @IBOutlet weak var stackView: NSStackView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupHelpItems()
        stackView.spacing = 8
        stackView.alignment = .leading
    }
    
    private func setupHelpItems() {
        let _: [()] = MountStatusDescription.allCases.map { item in
            let helpItemView = HelpItemView(symbolName: item.symbolName, symbolColor: item.color, description: item.localizedDescription)
            stackView.addArrangedSubview(helpItemView)
        }
    }
}

class HelpItemView: NSView {
    private let symbolImageView = NSImageView()
    private let descriptionLabel = NSTextField(labelWithString: "")
    
    init(symbolName: String, symbolColor: NSColor?, description: String) {
        super.init(frame: .zero)
        
        if let symbolImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            if let color = symbolColor {
                // changing color for SF Symbols is available on macOS >= 12
                if #available(macOS 12.0, *) {
                    let config = NSImage.SymbolConfiguration(hierarchicalColor: color)
                    symbolImageView.image = symbolImage.withSymbolConfiguration(config)
                } else {
                    symbolImageView.image = symbolImage
                }
            } else {
                symbolImageView.image = symbolImage
            }
        } else {
            symbolImageView.image = nil
        }
        symbolImageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(symbolImageView)
        
        let paragraphStyle = NSMutableParagraphStyle()
        
        let attributes: [NSAttributedString.Key: Any] = [
            .paragraphStyle: paragraphStyle
        ]
        
        let attributedDescription = NSAttributedString(string: description, attributes: attributes)
        descriptionLabel.attributedStringValue = attributedDescription
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(descriptionLabel)
        
        NSLayoutConstraint.activate([
            symbolImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            symbolImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            symbolImageView.widthAnchor.constraint(equalToConstant: 24),
            symbolImageView.heightAnchor.constraint(equalToConstant: 24),
            
            descriptionLabel.leadingAnchor.constraint(equalTo: symbolImageView.trailingAnchor, constant: 8),
            descriptionLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            descriptionLabel.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            descriptionLabel.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
