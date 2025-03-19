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
import Sentry

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
        
#if DEBUG
        Logger.appStatistics.debug("🐛 Debugging app, not reporting anything to sentry server ...")
#else
        if prefs.bool(for: .sendDiagnostics) == true {
            Logger.app.debug("Initializing sentry SDK...")
            SentrySDK.start { options in
                options.dsn = Defaults.sentryDSN
                options.debug = true // Enabling debug when first installing is always helpful
                
                // Set tracesSampleRate to 1.0 to capture 100% of transactions for tracing.
                // We recommend adjusting this value in production.
                options.tracesSampleRate = 1.0
            }
            // Manually call startProfiler and stopProfiler
            // to profile the code in between
            SentrySDK.startProfiler()
            // this code will be profiled
            //
            // Calls to stopProfiler are optional - if you don't stop the profiler, it will keep profiling
            // your application until the process exits or stopProfiler is called.
            SentrySDK.stopProfiler()
        }
#endif
        
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
        
        activityController = ActivityController(appDelegate: self)
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
            if mounter != nil {
                NotificationCenter.default.addObserver(self, selector: #selector(handleErrorNotification(_:)), name: .nsmNotification, object: nil)
            } else {
                Logger.app.error("Could not initialize mounter class, this should never happen.")
            }
            
            // trigger user authentication on app start
            Logger.app.debug("Trigger user authentication on app startup.")
            NotificationCenter.default.post(name: Defaults.nsmAuthTriggerNotification, object: nil)
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
                    NotificationCenter.default.post(name: Defaults.nsmAuthTriggerNotification, object: nil)
                } else {
                    Task {
                        NotificationCenter.default.post(name: Defaults.nsmAuthTriggerNotification, object: nil)
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
                        Task { @MainActor in
                            await self.constructMenu(withMounter: mounter, andStatus: .krbAuthenticationError)
                        }
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
                        Task { @MainActor in
                            await self.constructMenu(withMounter: mounter, andStatus: .authenticationError)
                        }
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
                        Task { @MainActor in
                            await self.constructMenu(withMounter: mounter)
                        }
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

    /// Opens the specified directory in Finder
    /// - Parameter sender: Menu item containing the directory path to open
    ///
    /// The directory path is stored in the menu item's `representedObject` as a String.
    /// This method attempts to:
    /// 1. Extract the directory path from the menu item
    /// 2. Convert it to a URL
    /// 3. Open it in Finder using NSWorkspace
    ///
    /// - Note: Directory path must be a valid file URL that can be opened by Finder
    /// - Important: Logs error if directory path cannot be extracted or is invalid
    @objc func openDirectory(_ sender: NSMenuItem) {
        // Extract directory path from menu item and convert to URL
        if let openMountedDir = sender.representedObject as? String,
           let mountDirectory = URL(string: openMountedDir) {
            // Open directory in Finder
            Logger.app.info("Trying to open \(mountDirectory, privacy: .public) in Finder...")
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: mountDirectory.path)
        } else {
            // Log error if path extraction fails
            Logger.app.error("Could not initialize mounter class, this should never happen.")
        }
    }
    
    /// Manually mounts all shares when triggered by the user
    /// - Parameter sender: The object that triggered the action
    @objc func mountManually(_ sender: Any?) {
        Logger.app.debug("User triggered mount all shares")
        NotificationCenter.default.post(name: Defaults.nsmAuthTriggerNotification, object: nil)
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
    
    /// Unmounts all currently mounted shares
    /// - Parameter sender: The object that triggered the action
    @objc func mountSpecificShare(_ sender: NSMenuItem) {
        if let shareID = sender.representedObject as? String {
            Logger.app.debug("User triggered to mount share with id \(shareID)")
            Task {
                if let mounter = mounter {
                    await mounter.mountGivenShares(userTriggered: true, forShare: shareID)
                    let finderController = FinderController()
                    await finderController.restartFinder()
                } else {
                    Logger.app.error("Could not initialize mounter class, this should never happen.")
                }
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
        unmountSignalSource?.setEventHandler { [self] in
            Logger.app.debug("🚦Received unmount signal.")
            Task {
                await self.mounter?.unmountAllMountedShares(userTriggered: false)
            }
        }

        // Set up event handler for mount signal
        mountSignalSource?.setEventHandler { [self] in
            Logger.app.debug("🚦Received mount signal.")
            Task {
                await self.mounter?.mountGivenShares(userTriggered: true)
            }
        }

        // Activate the signal sources
        unmountSignalSource?.resume()
        mountSignalSource?.resume()
    }
    
    /// Constructs the app's menu based on configured profiles and current status
    /// - Parameters:
    ///   - mounter: The Mounter object responsible for mounting/unmounting shares
    ///   - andStatus: Optional MounterError indicating any current error state
    @MainActor func constructMenu(withMounter mounter: Mounter, andStatus: MounterError? = nil) async {
        let menu = NSMenu()
        menu.autoenablesItems = false
        
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
            if let newMenuItem = createMenuItem(title: "About Network Share Mounter",
                                                  comment: "About Network Share Mounter",
                                                  action: #selector(AppDelegate.openHelpURL(_:)),
                                                  keyEquivalent: "",
                                                  preferenceKey: .menuAbout,
                                                  prefs: prefs) {
                menu.addItem(newMenuItem)
            }
        }
        
        // Add core functionality menu items:
    
        // Add "mount shares" menu item
        if let newMenuItem = createMenuItem(title: "Mount shares",
                                              comment: "Mount share",
                                              action: #selector(AppDelegate.mountManually(_:)),
                                              keyEquivalent: "m",
                                              preferenceKey: .menuConnectShares,
                                              prefs: prefs) {
            menu.addItem(newMenuItem)
        }
        // Add "unmount shares" menu item
        if let newMenuItem = createMenuItem(title: "Unmount shares",
                                              comment: "Unmount shares",
                                              action: #selector(AppDelegate.unmountShares(_:)),
                                              keyEquivalent: "u",
                                              preferenceKey: .menuDisconnectShares,
                                              prefs: prefs) {
            menu.addItem(newMenuItem)
        }
        // Add "Show mounted shares" menu item
        if let newMenuItem = createMenuItem(title: "Show mounted shares",
                                              comment: "Show mounted shares",
                                              action: #selector(AppDelegate.openDirectory(_:)),
                                              keyEquivalent: "f",
                                              preferenceKey: .menuShowSharesMountDir,
                                              prefs: prefs) {
            newMenuItem.representedObject = mounter.defaultMountPath
            menu.addItem(newMenuItem)
        }
        
        // Add "Check for Updates" menu item if auto-updater is enabled
        if prefs.bool(for: .enableAutoUpdater) == true {
            if let newMenuItem = createMenuItem(title: "Check for Updates...",
                                                comment: "Check for Updates",
                                                action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
                                                keyEquivalent: "",
                                                preferenceKey: .menuCheckUpdates,
                                                prefs: prefs) {
                menu.addItem(NSMenuItem.separator())
                newMenuItem.target = updaterController
                menu.addItem(newMenuItem)
            }
        }
        
        let menuShowSharesValue = prefs.string(for: .menuShowShares) ?? ""
        if await !mounter.shareManager.getAllShares().isEmpty {
            menu.addItem(NSMenuItem.separator())
            for share in await mounter.shareManager.allShares {
                var menuItem: NSMenuItem
                
                // Wenn das Share gemountet ist, verwende das Mountpoint-Icon
                if let mountpoint = share.actualMountPoint {
                    let mountDir = (mountpoint as NSString).lastPathComponent
                    Logger.app.debug("  🍰 Adding mountpoint \(mountDir) for \(share.networkShare) to menu.")
                    
                    let menuIcon = createMenuIcon(withIcon: "externaldrive.connected.to.line.below.fill", backgroundColor: .systemBlue, symbolColor: .white)
                    menuItem = NSMenuItem(title: NSLocalizedString(mountDir, comment: ""),
                                          action: #selector(AppDelegate.openDirectory(_:)),
                                          keyEquivalent: "")
                    menuItem.representedObject = mountpoint
                    menuItem.image = menuIcon
                } else {
                    // Wenn das Share nicht gemountet ist, verwende das Standard-Icon
                    Logger.app.debug("  🍰 Adding remote share \(share.networkShare).")
                    let menuIcon = createMenuIcon(withIcon: "externaldrive.connected.to.line.below", backgroundColor: .systemGray, symbolColor: .white)
                    menuItem = NSMenuItem(title: NSLocalizedString(share.networkShare, comment: ""),
                                          action: #selector(AppDelegate.mountSpecificShare(_:)),
                                          keyEquivalent: "")
                    menuItem.representedObject = share.id
                    menuItem.image = menuIcon
                }
                
                // Konfiguriere den Menüeintrag basierend auf dem Präferenzwert
                switch menuShowSharesValue {
                case "hidden":
                    // Menüeintrag wird nicht hinzugefügt
                    continue
                case "disabled":
                    // Menüeintrag wird hinzugefügt, aber deaktiviert
                    menuItem.isEnabled = false
                default:
                    // Menüeintrag wird normal hinzugefügt und ist aktiviert
                    menuItem.isEnabled = true
                }
                
                // Füge den konfigurierten Menüeintrag hinzu
                menu.addItem(menuItem)
            }
        }
        
        // Add "Preferences" menu item
        if let newMenuItem = createMenuItem(title: "Preferences ...",
                                              comment: "Preferences",
                                              action: #selector(AppDelegate.showWindow(_:)),
                                              keyEquivalent: ",",
                                              preferenceKey: .menuSettings,
                                              prefs: prefs) {
            menu.addItem(NSMenuItem.separator())
            menu.addItem(newMenuItem)
        }
        
        // Add "Quit" menu item if allowed by preferences
        if prefs.bool(for: .canQuit) != false {
            if let newMenuItem = createMenuItem(title: "Quit Network Share Mounter",
                                                comment: "Quit Network Share Mounter",
                                                action: #selector(NSApplication.terminate(_:)),
                                                keyEquivalent: "q",
                                                preferenceKey: .menuQuit,
                                                prefs: prefs) {
                menu.addItem(NSMenuItem.separator())
                menu.addItem(newMenuItem)
            }
        }
        
        // Set the constructed menu to the statusItem
        statusItem.menu = menu
    }
    
    /// Creates and configures a menu item based on user preferences
    ///
    /// - Parameters:
    ///   - title: The localized title text for the menu item
    ///   - action: The selector to be called when menu item is clicked
    ///   - keyEquivalent: The keyboard shortcut for the menu item
    ///   - preferenceKey: The preference key to check the menu item's state
    ///   - prefs: The preference manager instance to retrieve settings
    ///
    /// - Returns: A configured NSMenuItem instance, or nil if the menu item should be hidden
    ///
    /// The menu item's state is determined by the preference value:
    /// - "hidden": Returns nil, menu item won't be shown
    /// - "disabled": Menu item is shown but disabled
    /// - Any other value: Menu item is shown and enabled
    func createMenuItem(title: String, comment: String, action: Selector, keyEquivalent: String, preferenceKey: PreferenceKeys, prefs: PreferenceManager) -> NSMenuItem? {
        // Get preference value for the specified key
        let preferenceValue = prefs.string(for: preferenceKey) ?? ""
        // localize menu title
        let localizedTitle = NSLocalizedString(title, comment: "")
        // Create menu item with localized title
        let menuItem = NSMenuItem(title: NSLocalizedString(localizedTitle, comment: comment),
                                  action: action,
                                  keyEquivalent: keyEquivalent)
        
        // Configure menu item state based on preference value
        switch preferenceValue {
        case "hidden":
            // Don't add menu item
            return nil
        case "disabled":
            // Add menu item but disable it
            menuItem.isEnabled = false
        default:
            // Add menu item normally and enable it
            menuItem.isEnabled = true
        }
        return menuItem
    }
    
    /// Creates a custom menu bar icon with a colored background circle and SF Symbol
    /// - Parameters:
    ///   - withIcon: The name of the SF Symbol to use (currently not used in implementation)
    ///   - backgroundColor: The background color of the circular icon
    ///   - symbolColor: The color of the SF Symbol
    /// - Returns: An NSImage containing the composed icon
    /// - Note: The icon parameter is currently hardcoded to "externaldrive.connected.to.line.below.fill"
    func createMenuIcon(withIcon: String, backgroundColor: NSColor, symbolColor: NSColor) -> NSImage {
        
        // Create NSImage from SF Symbol
        let symbolImage = NSImage(systemSymbolName: "externaldrive.connected.to.line.below.fill", accessibilityDescription: nil)!
        
        // Convert symbol to template image for colorization
        // swiftlint:disable force_cast
        let templateImage = symbolImage.copy() as! NSImage
        // swiftlint:enable force_cast
        templateImage.isTemplate = true
        
        // Configure symbol appearance with 12pt regular weight
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        let configuredSymbolImage = templateImage.withSymbolConfiguration(symbolConfig)
        
        // Create base image for colored circle background
        let circleSize = NSSize(width: 24, height: 24)
        let circleImage = NSImage(size: circleSize)
        circleImage.lockFocus()
        
        // Draw colored circle background
        let circlePath = NSBezierPath(ovalIn: NSRect(origin: .zero, size: circleSize))
        backgroundColor.setFill()
        circlePath.fill()
        
        // Center and draw the symbol on top of circle
        if let configuredSymbolImage = configuredSymbolImage {
            let symbolRect = NSRect(
                x: (circleSize.width - configuredSymbolImage.size.width) / 2,
                y: (circleSize.height - configuredSymbolImage.size.height) / 2,
                width: configuredSymbolImage.size.width,
                height: configuredSymbolImage.size.height
            )
            
            // Apply symbol color and draw
            symbolColor.set()
            configuredSymbolImage.draw(in: symbolRect)
        }
        
        circleImage.unlockFocus()
        
        return circleImage
    }
}
