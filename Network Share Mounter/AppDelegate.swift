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
    var mounter = Mounter()
    var backGroundManager = BackGroundManager()

    // An observer that you use to monitor and react to network changes
    let monitor = Monitor.shared

    var timer = Timer()
    
    // define the activityController to et notifications from NSWorkspace
    var activityController: ActivityController?
    
    //
    // initalize class which will perform all the automounter tasks
//    let mounter = Mounter.init()

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
        /// set defaults for a few keys in userDefaults
        /// userDefaults.register allows to define default values if a value
        /// was not defined. Pretty slick
        UserDefaults.standard.register(
            defaults: [
                "keychainiCloudSync": false,
                "authenticationDialogImage": "nsm_logo"
            ]
        )
        
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
        NotificationCenter.default.addObserver(self, selector: #selector(handleErrorNotification(_:)), name: .nsmNotification, object: nil)
        
        //
        // start a timer to perform a mount every 5 minutes
        let timerInterval: Double = 300
        self.timer = Timer.scheduledTimer(withTimeInterval: timerInterval, repeats: true, block: { _ in
            Logger.app.info("Passed \(timerInterval, privacy: .public) seconds, performing operartions.")
            let netConnection = Monitor.shared
            let status = netConnection.netOn
            Logger.app.info("Current Network Path is \(status, privacy: .public).")
            Task {
                Logger.app.debug("... processing automatic sign in (if configured)")
                await self.backGroundManager.processAutomaticSignIn()
                Logger.app.debug("... check for possible MDM profile changes")
                // call updateShareArray() to reflect possible changes in MDM profile
                self.mounter.shareManager.updateShareArray()
                Logger.app.debug("... mounting shares.")
                await self.mounter.mountAllShares()
            }
        })
        
        //
        // start monitoring network connectivity and perform mount/unmount on network changes
        monitor.startMonitoring { connection, reachable in
            if reachable.rawValue == "yes" {
                Task {
                    Logger.app.debug("Got network monitoring callback:")
                    Logger.app.debug("... processing automatic sign in (if configured)")
                    await self.backGroundManager.processAutomaticSignIn()
                    Logger.app.debug("... check for possible MDM profile changes")
                    // call updateShareArray() to reflect possible changes in MDM profile
                    self.mounter.shareManager.updateShareArray()
                    Logger.app.debug("... mounting shares.")
                    await self.mounter.mountAllShares(userTriggered: true)
                }
            } else {
                Task {
                    // since the mount status after a network change is unknown it will be set
                    // to unknown so it can be tested and maybe remounted if the network connects again
                    await self.mounter.setAllMountStatus(to: MountStatus.undefined)
                    Logger.app.debug("Got network monitoring callback, unmount shares.")
                    // trying to unmount all shares
                    await self.mounter.unmountAllMountedShares()
                    // call updateShareArray() to reflect possible changes in MDM profile
                    self.mounter.shareManager.updateShareArray()
                }
            }
        }

        //
        // finally authenticate and mount all defined shares...
        Task {
            await self.backGroundManager.processAutomaticSignIn()
            await self.mounter.mountAllShares()
        }
        
        // ...and fire up the activityController to get system/NSWorkspace notifications
        activityController = ActivityController.init(withMounter: mounter)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        //
        // unmount all shares before leaving
        if userDefaults.bool(forKey: "unmountOnExit") == true {
            Task {
                await self.mounter.unmountAllMountedShares()
            }
        }
        //
        // end network monitoring
        monitor.monitor.cancel()
    }
    
    func setAlertMenuIcon(to alert: Bool) {
        guard let button = self.statusItem.button else { return }
            button.image = NSImage(named: NSImage.Name(alert ? MenuImageName.alert.rawValue : MenuImageName.normal.rawValue))
    }
    
    ///
    /// provide a method to react to certain events
    @objc func handleErrorNotification(_ notification: NSNotification) {
        if notification.userInfo?["AuthError"] is Error {
            // changes of the icon must be done on the main thread, therefore the call on DispatchQueue.main
            DispatchQueue.main.async {
                // Ändert die Farbe des Menuicons
                if let button = self.statusItem.button {
                    button.image = NSImage(named: NSImage.Name("networkShareMounterMenuYellow"))
                    self.constructMenu(withMounter: self.mounter, andStatus: .authenticationError)
                }
            }
        } else if notification.userInfo?["ClearError"] is Error {
            // changes of the icon must be done on the main thread, therefore the call on DispatchQueue.main
            DispatchQueue.main.async {
                // Ändert die Farbe des Menuicons
                if let button = self.statusItem.button {
                    button.image = NSImage(named: NSImage.Name("networkShareMounter"))
                    self.constructMenu(withMounter: self.mounter)
                }
            }
        } else if notification.userInfo?["FailError"] is Error {
            // changes of the icon must be done on the main thread, therefore the call on DispatchQueue.main
            DispatchQueue.main.async {
                // Ändert die Farbe des Menuicons
                if let button = self.statusItem.button {
                    button.image = NSImage(named: NSImage.Name("networkShareMounterMenuFail"))
                }
            }
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    @objc func showInfo(_ sender: Any?) {
        Logger.app.info("Some day maybe show some useful information about Network Share Mounter")
    }

    @objc func openMountDir(_ sender: Any?) {
        if let mountDirectory =  URL(string: self.mounter.defaultMountPath) {
            Logger.app.info("Trying to open \(mountDirectory, privacy: .public) in Finder...")
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: mountDirectory.path)
        }
    }
    
    @objc func mountManually(_ sender: Any?) {
        Logger.app.debug("User triggered mount all shares")
        Task {
            await self.mounter.mountAllShares(userTriggered: true)
        }
    }
    
    @objc func unmountShares(_ sender: Any?) {
        Logger.app.debug("User triggered unmount all shares")
        Task {
            await self.mounter.unmountAllMountedShares(userTriggered: true)
        }
    }
    
    @objc func openHelpURL(_ sender: Any?) {
        guard let url = userDefaults.string(forKey: "helpURL"), let openURL = URL(string: url) else {
            return
        }
        NSWorkspace.shared.open(openURL)
    }

    ///
    /// function which reads configured profiles to construct App's menu
    func constructMenu(withMounter mounter: Mounter, andStatus: MounterError? = nil) {
        let menu = NSMenu()
        
        switch andStatus {
        case .authenticationError:
            Logger.app.debug("Constructing authentication problem menu.")
            mounter.errorStatus = .authenticationError
            menu.addItem(NSMenuItem(title: NSLocalizedString("⚠️ Authentication problem...", comment: "Authentication problem"),
                                    action: #selector(AppDelegate.showWindow(_:)), keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())
            
        default:
            mounter.errorStatus = .noError
            Logger.app.debug("Constructing default menu.")
        }
        
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
