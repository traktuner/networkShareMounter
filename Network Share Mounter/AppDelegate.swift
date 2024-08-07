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
import Sparkle

/// The main application delegate class responsible for managing the app's lifecycle and core functionality.
@main
class AppDelegate: NSObject, NSApplicationDelegate {

    /// The status item displayed in the system menu bar
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    
    /// The main application window
    var window = NSWindow()
    
    /// The path where network shares are mounted
    var mountpath = ""
    
    /// The object responsible for mounting network shares
    var mounter: Mounter?
    
    /// Manages user preferences
    var prefs = PreferenceManager()
    
    /// Flag to enable Kerberos authentication
    var enableKerberos = false
    
    /// Flag to indicate if authentication is complete
    var authDone = false
    
    /// Handles automatic sign-in functionality
    var automaticSignIn = AutomaticSignIn.shared
    
    /// Monitors network changes
    let monitor = Monitor.shared
    
    /// Timer for scheduling mount operations
    var mountTimer = Timer()
    
    /// Timer for scheduling authentication operations
    var authTimer = Timer()
    
    /// Dispatch source for handling unmount signals
    var unmountSignalSource: DispatchSourceSignal?
    
    /// Dispatch source for handling mount signals
    var mountSignalSource: DispatchSourceSignal?
    
    /// Controller for managing app updates
    var updaterController: SPUStandardUpdaterController?
    
    /// Controller for monitoring system activity
    var activityController: ActivityController?
    
    /// Initializes the AppDelegate and sets up the auto-updater if enabled
    override init() {
        if prefs.bool(for: .enableAutoUpdater) == true {
            // Initialize the updater controller with default configuration
            // TODO: Consider adding custom updater delegate for more control over the update process
            updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        }
    }
    
    /// Application entry point after launch
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Prevent window from being deallocated when closed
        window.isReleasedWhenClosed = false
        
        // Initialize the Mounter instance
        mounter = Mounter()
        
        // Configure app to start at login based on user preferences
        LaunchAtLogin.isEnabled = prefs.bool(for: .autostart)
        
        // Set up the status item in the menu bar
        if let button = statusItem.button {
            button.image = NSImage(named: NSImage.Name("networkShareMounter"))
        }
        
        // Set the main window's content view controller
        window.contentViewController = NetworkShareMounterViewController.newInstance()
        
        // Asynchronously initialize the app
        Task {
            await initializeApp()
        }
        
        // Set up signal handlers for the app
        setupSignalHandlers()
        
        // MARK: TODO - Authentication and mounting
        // The following code block is commented out and may need to be implemented:
        // - Initialize ActivityController
        // - Post notification to trigger mounting of defined shares
        /*
        if let mounter {
            activityController = ActivityController.init()
            NotificationCenter.default.post(name: Defaults.nsmTimeTriggerNotification, object: nil)
        }
        */
    }
    
    private func initializeApp() async {
        Task {
            await mounter?.asyncInit()
            // check if a kerberos domain/realm is set and is not empty
            if let krbRealm = self.prefs.string(for: .kerberosRealm), !krbRealm.isEmpty {
                self.enableKerberos = true
            }
            
            //
            // initialize statistics reporting struct
            let stats = AppStatistics.init()
            await stats.reportAppInstallation()
            await AccountsManager.shared.initialize()
            
            // Do any additional setup after loading the view.
            if let mounter {
                constructMenu(withMounter: mounter)
                NotificationCenter.default.addObserver(self, selector: #selector(handleErrorNotification(_:)), name: .nsmNotification, object: nil)
                // fire up the activityController to get system/NSWorkspace notifications
//                activityController = ActivityController.init(withMounter: mounter)
                activityController = ActivityController.init()
            } else {
                Logger.app.error("Could not initialize mounter class, this should never happen.")
            }
            
            // set a timer to perform a mount every n seconds
            mountTimer = Timer.scheduledTimer(withTimeInterval: Defaults.mountTriggerTimer, repeats: true, block: { _ in
                Logger.app.info("Passed \(Defaults.mountTriggerTimer, privacy: .public) seconds, performing operartions:")
                NotificationCenter.default.post(name: Defaults.nsmTimeTriggerNotification, object: nil)
            })
            // set a timer to perform authentication every n seconds
            authTimer = Timer.scheduledTimer(withTimeInterval: Defaults.authTriggerTimer, repeats: true, block: { _ in
                Logger.app.info("Passed \(Defaults.authTriggerTimer, privacy: .public) seconds, performing operartions:")
                NotificationCenter.default.post(name: Defaults.nsmAuthTriggerNotification, object: nil)
            })
            
            //
            // start monitoring network connectivity and perform mount/unmount on network changes
            monitor.startMonitoring { connection, reachable in
                if reachable.rawValue == "yes" {
                    NotificationCenter.default.post(name: Defaults.nsmNetworkChangeTriggerNotification, object: nil)
                } else {
                    Task {
                        // since the mount status after a network change is unknown it will be set
                        // to unknown so it can be tested and maybe remounted if the network connects again
                        Logger.app.debug("Got network monitoring callback, unmount shares.")
                        if let mounter = self.mounter {
                            await mounter.setAllMountStatus(to: MountStatus.undefined)
                            // trying to unmount all shares
                            NotificationCenter.default.post(name: Defaults.nsmUnmountTriggerNotification, object: nil)
                            await mounter.unmountAllMountedShares()
                        } else {
                            Logger.app.error("Could not initialize mounter class, this should never happen.")
                        }
                    }
                }
            }
            NotificationCenter.default.post(name: Defaults.nsmTimeTriggerNotification, object: nil)
        }
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
    
    /// Handles various error notifications and updates the menu bar icon accordingly.
    /// - Parameter notification: The notification containing error information.
    @objc func handleErrorNotification(_ notification: NSNotification) {
        // Handle Kerberos authentication error
        if notification.userInfo?["KrbAuthError"] is Error {
            DispatchQueue.main.async {
                if let button = self.statusItem.button, self.enableKerberos {
                    button.image = NSImage(named: NSImage.Name("networkShareMounterMenuRed"))
                    if let mounter = self.mounter {
                        self.constructMenu(withMounter: mounter, andStatus: .krbAuthenticationError)
                    } else {
                        Logger.app.error("Could not initialize mounter class, this should never happen.")
                    }
                }
            }
        }
        // Handle general authentication error
        else if notification.userInfo?["AuthError"] is Error {
            DispatchQueue.main.async {
                if let button = self.statusItem.button {
                    button.image = NSImage(named: NSImage.Name("networkShareMounterMenuYellow"))
                    if let mounter = self.mounter {
                        self.constructMenu(withMounter: mounter, andStatus: .authenticationError)
                    } else {
                        Logger.app.error("Could not initialize mounter class, this should never happen.")
                    }
                }
            }
        }
        // Handle error clearance
        else if notification.userInfo?["ClearError"] is Error {
            DispatchQueue.main.async {
                // change the color of the menu symbol
                if let button = self.statusItem.button {
                    button.image = NSImage(named: NSImage.Name("networkShareMounter"))
                    if let mounter = self.mounter {
                        self.constructMenu(withMounter: mounter)
                    } else {
                        Logger.app.error("Could not initialize mounter class, this should never happen.")
                    }
                }
            }
        }
        // Handle successful Kerberos authentication
        else if notification.userInfo?["krbAuthenticated"] is Error {
            DispatchQueue.main.async {
                if let button = self.statusItem.button, self.enableKerberos {
                    button.image = NSImage(named: NSImage.Name("networkShareMounterMenuGreen"))
                }
            }
        }
        // Handle general failure
        else if notification.userInfo?["FailError"] is Error {
            DispatchQueue.main.async {
                if let button = self.statusItem.button {
                    button.image = NSImage(named: NSImage.Name("networkShareMounterMenuFail"))
                }
            }
        }
        // Handle Kerberos off-domain status
        else if notification.userInfo?["krbOffDomain"] is Error {
            DispatchQueue.main.async {
                // change the color of the menu symbol
                if let button = self.statusItem.button, self.enableKerberos {
                    button.image = NSImage(named: NSImage.Name("networkShareMounter"))
                }
            }
        }
    }

    /// Indicates whether the application supports secure restorable state.
    /// - Parameter app: The NSApplication instance.
    /// - Returns: Always returns true for this application.
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    /// Displays information about the Network Share Mounter.
    /// - Parameter sender: The object that initiated this action.
    /// - Note: Currently a placeholder. Consider implementing actual info display in the future.
    @objc func showInfo(_ sender: Any?) {
        Logger.app.info("Some day maybe show some useful information about Network Share Mounter")
    }

    /// Opens the default mount directory in Finder.
    /// - Parameter sender: The object that initiated this action.
    /// - Note: Logs an error if the mounter class cannot be initialized.
    @objc func openMountDir(_ sender: Any?) {
        if let mounter = mounter {
            if let mountDirectory =  URL(string: mounter.defaultMountPath) {
                Logger.app.info("Trying to open \(mountDirectory, privacy: .public) in Finder...")
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: mountDirectory.path)
            } else {
                Logger.app.error("Could not initialize mounter class, this should never happen.")
            }
        }
    }
    
    /// Manually mounts all shares when triggered by the user
    /// - Parameter sender: The object that triggered the action
    @objc func mountManually(_ sender: Any?) {
        Logger.app.debug("User triggered mount all shares")
        NotificationCenter.default.post(name: Defaults.nsmMountManuallyTriggerNotification, object: nil)
    }

    /// Unmounts all currently mounted shares
    /// - Parameter sender: The object that triggered the action
    @objc func unmountShares(_ sender: Any?) {
        Logger.app.debug("User triggered unmount all shares")
        Task {
            if let mounter = mounter {
                await mounter.unmountAllMountedShares(userTriggered: true)
            } else {
                Logger.app.error("Could not initialize mounter class, this should never happen.")
                // TODO: Implement proper error handling and user feedback
            }
        }
    }

    /// Opens the help URL in the default web browser
    /// - Parameter sender: The object that triggered the action
    @objc func openHelpURL(_ sender: Any?) {
        guard let url = prefs.string(for: .helpURL), let openURL = URL(string: url) else {
            // TODO: Consider adding error logging or user feedback if URL is invalid
            return
        }
        NSWorkspace.shared.open(openURL)
    }

    /// Constructs the app's menu based on configured profiles and current status
    /// - Parameters:
    ///   - mounter: The Mounter object responsible for mounting/unmounting shares
    ///   - andStatus: Optional MounterError indicating any current error state
    func constructMenu(withMounter mounter: Mounter, andStatus: MounterError? = nil) {
        let menu = NSMenu()
        
        // Handle different error states and construct appropriate menu items
        switch andStatus {
        case .krbAuthenticationError:
            Logger.app.debug("🏗️ Constructing Kerberos authentication problem menu.")
            mounter.errorStatus = .authenticationError
            menu.addItem(NSMenuItem(title: NSLocalizedString("⚠️ Kerberos SSO Authentication problem...", comment: "Kerberos Authentication problem"),
                                    action: #selector(AppDelegate.showWindow(_:)), keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())
        case .authenticationError:
            Logger.app.debug("🏗️ Constructing authentication problem menu.")
            mounter.errorStatus = .authenticationError
            menu.addItem(NSMenuItem(title: NSLocalizedString("⚠️ Authentication problem...", comment: "Authentication problem"),
                                    action: #selector(AppDelegate.showWindow(_:)), keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())
            
        default:
            mounter.errorStatus = .noError
            Logger.app.debug("🏗️ Constructing default menu.")
        }
        
        // Add "About" menu item if help URL is valid
        if prefs.string(for: .helpURL)!.description.isValidURL {
            menu.addItem(NSMenuItem(title: NSLocalizedString("About Network Share Mounter", comment: "About Network Share Mounter"),
                                    action: #selector(AppDelegate.openHelpURL(_:)), keyEquivalent: ""))
        }
        
        // Add core functionality menu items
        menu.addItem(NSMenuItem(title: NSLocalizedString("Mount shares", comment: "Mount shares"),
                                action: #selector(AppDelegate.mountManually(_:)), keyEquivalent: "m"))
        menu.addItem(NSMenuItem(title: NSLocalizedString("Unmount shares", comment: "Unmount shares"),
                                action: #selector(AppDelegate.unmountShares(_:)), keyEquivalent: "u"))
        menu.addItem(NSMenuItem(title: NSLocalizedString("Show mounted shares", comment: "Show mounted shares"),
                                action: #selector(AppDelegate.openMountDir(_:)), keyEquivalent: "f"))
        menu.addItem(NSMenuItem.separator())
        
        // Add "Check for Updates" menu item if auto-updater is enabled
        if prefs.bool(for: .enableAutoUpdater) == true {
            let checkForUpdatesMenuItem = NSMenuItem(title: NSLocalizedString("Check for Updates...", comment: "Check for Updates"),
                                        action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)), keyEquivalent: "")
            checkForUpdatesMenuItem.target = updaterController
            menu.addItem(checkForUpdatesMenuItem)
            menu.addItem(NSMenuItem.separator())
        }
        
        // Add "Preferences" menu item
        menu.addItem(NSMenuItem(title: NSLocalizedString("Preferences ...", comment: "Preferences"),
                                action: #selector(AppDelegate.showWindow(_:)), keyEquivalent: ","))
        
        // Add "Quit" menu item if allowed by preferences
        if prefs.bool(for: .canQuit) != false {
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: NSLocalizedString("Quit Network Share Mounter", comment: "Quit Network Share Mounter"),
                                    action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        }
        
        // Set the constructed menu to the statusItem
        statusItem.menu = menu
    }

    /// Shows the preferences window.
    @objc func showWindow(_ sender: Any?) {
        // Configure window appearance and behavior
        window.title = NSLocalizedString("Preferences", comment: "Preferences")
        window.styleMask.insert([.closable])
        
        // Position the window at the center of the current display
        window.center()
        
        // Activate the app and bring the window to front
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        
        // Make this window the key window
        window.makeKey()
        
        // MARK: - Potential improvements
        // TODO: Consider adding a dedicated WindowController for better management
        // TODO: Evaluate if titlebar transparency is needed: window.titlebarAppearsTransparent = true
        
        // NOTE: Window is currently closed using the standard close button
        // Consider implementing a custom close behavior if needed in the future
    }
    
    /// Sets up signal handlers for mounting and unmounting shares.
    func setupSignalHandlers() {
        // Define custom signals for unmounting and mounting
        let unmountSignal = SIGUSR1
        let mountSignal = SIGUSR2

        // Ignore the signals at the process level
        signal(unmountSignal, SIG_IGN)
        signal(mountSignal, SIG_IGN)

        // Create dispatch sources for the signals on the main queue
        unmountSignalSource = DispatchSource.makeSignalSource(signal: unmountSignal, queue: .main)
        mountSignalSource = DispatchSource.makeSignalSource(signal: mountSignal, queue: .main)

        // Set up event handler for unmount signal
        unmountSignalSource?.setEventHandler { [weak self] in
            Logger.app.debug("🚦Received unmount signal.")
            Task {
                await self?.mounter?.unmountAllMountedShares(userTriggered: true)
            }
        }

        // Set up event handler for mount signal
        mountSignalSource?.setEventHandler { [weak self] in
            Logger.app.debug("🚦Received mount signal.")
            Task {
                await self?.mounter?.mountAllShares()
            }
        }

        // Activate the signal sources
        unmountSignalSource?.resume()
        mountSignalSource?.resume()
    }

}
