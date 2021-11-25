//
//  AppDelegate.swift
//  Network Share Mounter
//
//  Created by Gregor Longariva on 24.11.21.
//  Copyright © 2021 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Cocoa
import Network
import LaunchAtLogin

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    
    let statusItem = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
    let popover = NSPopover()
    
    // An observer that you use to monitor and react to network changes
    let monitor = NWPathMonitor()
    
    var timer = Timer()

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
        let mounter = Mounter.init()
        LaunchAtLogin.isEnabled = true
        
        // Do any additional setup after loading the view.
        Monitor().startMonitoring { [weak self] connection, reachable in
                    guard let strongSelf = self else { return }
            strongSelf.doSomething(connection, reachable: reachable, mounter: mounter)
            
        }
        
        // start a timer to perform a mount every 5 minutes
        self.timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true, block: { _ in
            mounter.mountShares()
        })
        
        if let button = statusItem.button {
            button.image = NSImage(named:NSImage.Name("server-file-swk"))
            //button.action = #selector(printQuote(_:))
            //button.action = #selector(togglePopover(_:))
            button.action = #selector(AppDelegate.togglePopover(_:))
        }
        popover.contentViewController = NetworkShareMounterViewController.newInsatnce()
        self.popover.animates = false
        //constructMenu()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
    
    
    private func doSomething(_ connection: Connection, reachable: Reachable, mounter: Mounter) {
        NSLog("Current Connection : \(connection) Is reachable: \(reachable)")
        if reachable == Reachable.yes {
            mounter.mountShares()
        }
    }


    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
    
    @objc func printQuote(_ sender: Any?) {
      let quoteText = "Never put off until tomorrow what you can do the day after tomorrow."
      let quoteAuthor = "Mark Twain"
      
      print("\(quoteText) — \(quoteAuthor)")
    }

    func constructMenu() {
      let menu = NSMenu()

      menu.addItem(NSMenuItem(title: "Print Quote", action: #selector(AppDelegate.printQuote(_:)), keyEquivalent: "P"))
      menu.addItem(NSMenuItem.separator())
      menu.addItem(NSMenuItem(title: "Quit Quotes", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

      statusItem.menu = menu
    }
    
    @objc func togglePopover(_ sender: Any?) {
      if popover.isShown {
        closePopover(sender: sender)
      } else {
        showPopover(sender: sender)
      }
    }

    func showPopover(sender: Any?) {
      if let button = statusItem.button {
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
      }
    }

    func closePopover(sender: Any?) {
      popover.performClose(sender)
    }


}

