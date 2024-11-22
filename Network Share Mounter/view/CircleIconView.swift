//
//  CircleIconView.swift
//  Network Share Mounter
//
//  Created by Gregor Longariva on 19.11.24.
//  Copyright © 2024 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation
import AppKit

class CircleIconView: NSView {
    var symbolName: String
    private var symbolImage: NSImage?
    
    init(frame: NSRect, symbolName: String) {
        self.symbolName = symbolName
        super.init(frame: frame)
        setupSymbol()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupSymbol() {
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let scale = 0.6 // Anpassen für verschiedene Symbol-Größen
            let symbolSize = NSSize(width: bounds.width * scale, height: bounds.height * scale)
            image.size = symbolSize
            image.isTemplate = true
            symbolImage = image
        }
    }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // Kreis zeichnen
        let circleInset: CGFloat = 0.5
        let circleBounds = bounds.insetBy(dx: circleInset, dy: circleInset)
        let circlePath = NSBezierPath(ovalIn: circleBounds)
        NSColor.systemBlue.setFill()
        circlePath.fill()
        
        // Symbol zeichnen
        if let image = symbolImage {
            NSGraphicsContext.saveGraphicsState()
            NSColor.white.set()
            
            let imageRect = NSRect(
                x: (bounds.width - image.size.width) / 2,
                y: (bounds.height - image.size.height) / 2,
                width: image.size.width,
                height: image.size.height
            )
            
            image.draw(in: imageRect,
                      from: NSRect(origin: .zero, size: image.size),
                      operation: .sourceAtop,
                      fraction: 1.0)
            
            NSGraphicsContext.restoreGraphicsState()
        }
    }
}
