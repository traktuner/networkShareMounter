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
    let userDefaults = UserDefaults.standard
    
    // An observer that you use to monitor and react to network changes
    let monitor = NWPathMonitor()
    
    var timer = Timer()

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
        //
        // using "register" instead of "get" will set the values according to the plist read
        // by "readPropertyList" if, and only if the respective  values are nil. Those values
        // are not written back to UserDefaults.
        // So if there are any values set by the user or MDM, those values will be used. If
        // not, the values in the plist are used.
        if let defaultValues = readPropertyList() {
            userDefaults.register(defaults: defaultValues)
        }

        //
        // initalize class which will perform all the automounter tasks
        let mounter = Mounter.init()
        
        //
        // register App according to userDefaults as "start at login"
        LaunchAtLogin.isEnabled = userDefaults.bool(forKey: "autostart")
        
        if let button = statusItem.button {
            button.image = NSImage(named:NSImage.Name("server-file-swk"))
            //button.action = #selector(printQuote(_:))
            //button.action = #selector(togglePopover(_:))
            //button.action = #selector(AppDelegate.togglePopover(_:))
        }
        //popover.contentViewController = NetworkShareMounterViewController.newInsatnce()
        //self.popover.animates = false
        constructMenu()
        
        // Do any additional setup after loading the view.
        Monitor().startMonitoring { [weak self] connection, reachable in
                    guard let strongSelf = self else { return }
            strongSelf.performMount(connection, reachable: reachable, mounter: mounter)
            
        }
        
        // start a timer to perform a mount every 5 minutes
        self.timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true, block: { _ in
            mounter.mountShares()
        })
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
    
    
    private func performMount(_ connection: Connection, reachable: Reachable, mounter: Mounter) {
        NSLog("Current Connection : \(connection) Is reachable: \(reachable)")
        if reachable == Reachable.yes {
            mounter.mountShares()
        }
    }


    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
    
    @objc func showInfo(_ sender: Any?) {
      print("Show some day some useful information about Network Share Mounter")
    }

    func constructMenu() {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "Network Share Mounter", action: #selector(AppDelegate.showInfo(_:)), keyEquivalent: "P"))
        //menu.addItem(NSMenuItem.separator())
        if userDefaults.bool(forKey: "canQuit") == true {
            menu.addItem(NSMenuItem(title: "Network Share Mounter Beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        }
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

    //
    // method to read a file with a bunch of defaults instead of setting it in the source code
    private func readPropertyList() -> [String: Any]? {
        guard let plistPath = Bundle.main.path(forResource: "DefaultValues", ofType: "plist"),
                    let plistData = FileManager.default.contents(atPath: plistPath) else {
                return nil
            }
        return try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
    }

}

