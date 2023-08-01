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
import OSLog

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    var window = NSWindow()
    let userDefaults = UserDefaults.standard
    var mountpath = ""

    // An observer that you use to monitor and react to network changes
    let monitor = NWPathMonitor()

    var timer = Timer()
    
    let logger = Logger(subsystem: "NetworkShareMounter", category: "App")
    
    //
    // initalize class which will perform all the automounter tasks
    let mounter = Mounter.init()

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        window.isReleasedWhenClosed = false
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
        self.mountpath = mounter.mountpath
        
        //
        // initialize statistics reporting struct
        let stats = AppStatistics.init()
        Task {
            await stats.reportAppInstallation()
        }

        //
        // register App according to userDefaults as "start at login"
        // LaunchAtLogin.isEnabled = userDefaults.bool(forKey: "autostart")
        // LaunchAtLogin.isEnabled = UserDefaults(suiteName: config.defaultsDomain)?.bool(forKey: "autostart") ?? true
        if userDefaults.bool(forKey: "autostart") != false {
            LaunchAtLogin.isEnabled = true
        } else {
            LaunchAtLogin.isEnabled = false
        }

        if let button = statusItem.button {
            button.image = NSImage(named: NSImage.Name("networkShareMounter"))
        }
        window.contentViewController = NetworkShareMounterViewController.newInstance()

        // Do any additional setup after loading the view.
        constructMenu(withMounter: mounter)
        
        // start a timer to perform a mount every 5 minutes
        let timerInterval: Double = 300
        self.timer = Timer.scheduledTimer(withTimeInterval: timerInterval, repeats: true, block: { _ in
            self.logger.info("Passed \(timerInterval) seconds, performing mount operartions.")
            let netConnection = Monitor.shared
            let status = netConnection.netOn
            self.logger.info("Current Network Path is \(status).")
            self.mounter.mountShares()
        })
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        //
        // unmount all shares befor leaving
        if userDefaults.bool(forKey: "unmountOnExit") == true {
            self.mounter.unmountAllShares()
        }
        //
        // end network monitoring
        monitor.cancel()
    }

    private func performMount(_ connection: Connection, reachable: Reachable, mounter: Mounter) {
        self.logger.info("Current Connection: \(connection.rawValue) Is reachable: \(reachable.rawValue)")
        if reachable == Reachable.yes {
            mounter.mountShares()
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    @objc func showInfo(_ sender: Any?) {
        self.logger.info("Some day maybe show some useful information about Network Share Mounter")
//        print("Some day maybe show some useful information about Network Share Mounter")
    }

    @objc func openMountDir(_ sender: Any?) {
        if let mountDirectory =  URL(string: self.mountpath) {
            self.logger.info("Trying to open \(mountDirectory) in Finder...")
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: mountDirectory.path)
        }
    }
    
    @objc func mountManually(_ sender: Any?) {
        self.logger.info("User triggered mount all shares")
        mounter.mountShares()
    }
    
    @objc func unmountShares(_ sender: Any?) {
        self.logger.info("User triggered unmount all shares")
        mounter.unmountAllShares()
    }
    
    @objc func openHelpURL(_ sender: Any?) {
        guard let url = userDefaults.string(forKey: "helpURL"), let openURL = URL(string: url) else {
            return
        }
        NSWorkspace.shared.open(openURL)
    }

    func constructMenu(withMounter mounter: Mounter) {
        let menu = NSMenu()
        
        if userDefaults.string(forKey: "helpURL")!.description.isValidURL {
            menu.addItem(NSMenuItem(title: NSLocalizedString("About Network Share Mounter", comment: "About Network Share Mounter"),
                                    action: #selector(AppDelegate.openHelpURL(_:)), keyEquivalent: ""))
        }
        menu.addItem(NSMenuItem(title: NSLocalizedString("Mount shares", comment: "Mount shares"),
                                action: #selector(AppDelegate.mountManually(_:)), keyEquivalent: "m"))
        menu.addItem(NSMenuItem(title: NSLocalizedString("Unmount shares", comment: "Unmount shares"),
                                action: #selector(AppDelegate.unmountShares(_:)), keyEquivalent: "u"))
        menu.addItem(NSMenuItem(title: NSLocalizedString("Show mounted shares", comment: "Show mounted shares"),
                                action: #selector(AppDelegate.openMountDir(_:)), keyEquivalent: "f"))
        // menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem.separator())
        
        menu.addItem(NSMenuItem(title: NSLocalizedString("Preferences ...", comment: "Preferences"),
                                action: #selector(AppDelegate.showWindow(_:)), keyEquivalent: ","))
        if userDefaults.bool(forKey: "canQuit") != false {
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: NSLocalizedString("Quit Network Share Mounter", comment: "Quit Network Share Mounter"),
                                    action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
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
        // window.titlebarAppearsTransparent = true
        window.title = NSLocalizedString("Preferences", comment: "Preferences")
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
