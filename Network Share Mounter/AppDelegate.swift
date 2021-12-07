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
    var window = NSWindow()
    let userDefaults = UserDefaults.standard

    
    // An observer that you use to monitor and react to network changes
    let monitor = NWPathMonitor()
    
    var timer = Timer()

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
        //print(Array(UserDefaults.standard.dictionaryRepresentation()))
        //dump(Array(UserDefaults.standard.dictionaryRepresentation().keys))
//        UserDefaults.standard.removeObject(forKey: "autostart")
//        UserDefaults.standard.removeObject(forKey: "customNetworkShares")
//        UserDefaults.standard.removeObject(forKey: "networkShares")
//        UserDefaults.standard.synchronize()
        
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
            button.image = NSImage(named:NSImage.Name("networkShareMounter"))
        }
        window.contentViewController = NetworkShareMounterViewController.newInsatnce()
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
        // write changed values back to userDefaults
        if userDefaults.bool(forKey: "autostart") != LaunchAtLogin.isEnabled {
            userDefaults.set(true, forKey: "autostart")
        }
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
        menu.addItem(NSMenuItem(title: "Einstellungen ...", action: #selector(AppDelegate.showWindow(_:)), keyEquivalent: ","))
        //menu.addItem(NSMenuItem.separator())
        if userDefaults.bool(forKey: "canQuit") == true {
            menu.addItem(NSMenuItem(title: "Network Share Mounter Beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        }
        statusItem.menu = menu
    }

    @objc func showWindow(_ sender: Any?) {
        //
        // folgender Code zeigt ein neues Fenster an - ohne eigenen WindowController. Es tut was es soll, funktkioniert und ich denke, da
        // werde/würde ich nicht lang rum machen.
        // Geschlossen wird es mit dem roten button links oben, nachdem das andere Apps auch so machen ¯\_(ツ)_/¯ 
        //
        // without titlebar and title-text
        window.titlebarAppearsTransparent = true
        //
        // somehow we close the window
        window.styleMask.insert([.closable])
        //
        // show the window at the center of the current display
        window.center()
        //
        // bring the app itself to front
        NSApp.activate(ignoringOtherApps: true)
        //
        // bringt the window to front
        window.orderFrontRegardless()
        //
        // make this window the key window receibing keyboard and other non-touch related events
        window.makeKey()
    }

    //
    // method to read a file with a bunch of defaults instead of setting them in the source code
    private func readPropertyList() -> [String: Any]? {
        guard let plistPath = Bundle.main.path(forResource: "DefaultValues", ofType: "plist"),
                    let plistData = FileManager.default.contents(atPath: plistPath) else {
                return nil
            }
        return try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
    }

}
