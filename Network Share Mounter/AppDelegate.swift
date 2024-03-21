//
//  AppDelegate.swift
//  Network Share Mounter
//
//  Created by Gregor Longariva on 24.11.21.
//  Copyright © 2024 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Cocoa
import Network
import LaunchAtLogin
import OSLog

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    var window = NSWindow()
    var mountpath = ""
    var mounter = Mounter()
    var prefs = PreferenceManager()
    var enableKerberos = false
    var authDone = false
    var automaticSignIn: AutomaticSignIn?
    
    // An observer that you use to monitor and react to network changes
    let monitor = Monitor.shared

    var mountTimer = Timer()
    var authTimer = Timer()
    
    // define the activityController to et notifications from NSWorkspace
    var activityController: ActivityController?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        window.isReleasedWhenClosed = false
        
        // check if a kerberos domain/realm is set and is not empty
        if let krbRealm = self.prefs.string(for: .kerberosRealm), !krbRealm.isEmpty {
            self.enableKerberos = true
        }
        
        //
        // initialize statistics reporting struct
        let stats = AppStatistics.init()
        Task {
            await stats.reportAppInstallation()
        }

        //
        // register App according to userDefaults as "start at login"
        LaunchAtLogin.isEnabled = prefs.bool(for: .autostart)

        if let button = statusItem.button {
            button.image = NSImage(named: NSImage.Name("networkShareMounter"))
        }
        window.contentViewController = NetworkShareMounterViewController.newInstance()

        // Do any additional setup after loading the view.
        constructMenu(withMounter: mounter)
        NotificationCenter.default.addObserver(self, selector: #selector(handleErrorNotification(_:)), name: .nsmNotification, object: nil)
        
        // fire up the activityController to get system/NSWorkspace notifications
        activityController = ActivityController.init(withMounter: mounter)
        
        // set a timer to perform a mount every n seconds
        self.mountTimer = Timer.scheduledTimer(withTimeInterval: Defaults.mountTriggerTimer, repeats: true, block: { _ in
            Logger.app.info("Passed \(Defaults.mountTriggerTimer, privacy: .public) seconds, performing operartions:")
            NotificationCenter.default.post(name: Defaults.nsmTimeTriggerNotification, object: nil)
        })
        // set a timer to perform authentication every n seconds
        self.authTimer = Timer.scheduledTimer(withTimeInterval: Defaults.authTriggerTimer, repeats: true, block: { _ in
            Logger.app.info("Passed \(Defaults.authTriggerTimer, privacy: .public) seconds, performing operartions:")
            NotificationCenter.default.post(name: Defaults.nsmAuthTriggerNotification, object: nil)
        })
        
        //
        // start monitoring network connectivity and perform mount/unmount on network changes
        monitor.startMonitoring { connection, reachable in
            if reachable.rawValue == "yes" {
                NotificationCenter.default.post(name: Defaults.nsmTimeTriggerNotification, object: nil)
            } else {
                Task {
                    // since the mount status after a network change is unknown it will be set
                    // to unknown so it can be tested and maybe remounted if the network connects again
                    Logger.app.debug("Got network monitoring callback, unmount shares.")
                    await self.mounter.setAllMountStatus(to: MountStatus.undefined)
                    // trying to unmount all shares
                    NotificationCenter.default.post(name: Defaults.nsmUnmountTriggerNotification, object: nil)
                    await self.mounter.unmountAllMountedShares()
                }
            }
        }

        //
        // finally authenticate and mount all defined shares...
        NotificationCenter.default.post(name: Defaults.nsmTimeTriggerNotification, object: nil)
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // end network monitoring
        monitor.monitor.cancel()
        //
        // unmount all shares before leaving
        if prefs.bool(for: .unmountOnExit) == true {
            Logger.app.debug("Exiting app, unmounting shares...")
            unmountShares(self)
            // OK, I know, this is ugly, but a little sleep on app exit does not harm ;-)
            sleep(3)
        }
    }
    
    ///
    /// provide a method to react to certain events
    @objc func handleErrorNotification(_ notification: NSNotification) {
        if notification.userInfo?["KrbAuthError"] is Error {
            // changes of the icon must be done on the main thread, therefore the call on DispatchQueue.main
            DispatchQueue.main.async {
                // Ändert die Farbe des Menuicons
                if let button = self.statusItem.button, self.enableKerberos {
                    button.image = NSImage(named: NSImage.Name("networkShareMounterMenuRed"))
                    self.constructMenu(withMounter: self.mounter, andStatus: .krbAuthenticationError)
                }
            }
        } else if notification.userInfo?["AuthError"] is Error {
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
        } else if notification.userInfo?["krbAuthenticated"] is Error {
            // changes of the icon must be done on the main thread, therefore the call on DispatchQueue.main
            DispatchQueue.main.async {
                // Ändert die Farbe des Menuicons
                if let button = self.statusItem.button, self.enableKerberos {
                    button.image = NSImage(named: NSImage.Name("networkShareMounterMenuGreen"))
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
        } else if notification.userInfo?["krbOffDomain"] is Error {
            // changes of the icon must be done on the main thread, therefore the call on DispatchQueue.main
            DispatchQueue.main.async {
                // Ändert die Farbe des Menuicons
                if let button = self.statusItem.button, self.enableKerberos {
                    button.image = NSImage(named: NSImage.Name("networkShareMounter"))
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
        NotificationCenter.default.post(name: Defaults.nsmMountManuallyTriggerNotification, object: nil)
    }
    
    @objc func unmountShares(_ sender: Any?) {
        Logger.app.debug("User triggered unmount all shares")
        Task {
            await self.mounter.unmountAllMountedShares(userTriggered: true)
        }
    }
    
    @objc func openHelpURL(_ sender: Any?) {
        guard let url = prefs.string(for: .helpURL), let openURL = URL(string: url) else {
            return
        }
        NSWorkspace.shared.open(openURL)
    }

    ///
    /// function which reads configured profiles to construct App's menu
    func constructMenu(withMounter mounter: Mounter, andStatus: MounterError? = nil) {
        let menu = NSMenu()
        
        switch andStatus {
            case .krbAuthenticationError:
                Logger.app.debug("Constructing Kerberos authentication problem menu.")
                mounter.errorStatus = .authenticationError
                menu.addItem(NSMenuItem(title: NSLocalizedString("⚠️ Kerberos SSO Authentication problem...", comment: "Kerberos Authentication problem"),
                                action: #selector(AppDelegate.showWindow(_:)), keyEquivalent: ""))
                menu.addItem(NSMenuItem.separator())
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
        
        if prefs.string(for: .helpURL)!.description.isValidURL {
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
        if prefs.bool(for: .canQuit) != false {
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
        // make this window the key window receiving keyboard and other non-touch related events
        window.makeKey()
    }
}
