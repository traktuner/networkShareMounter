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
import dogeADAuth

/// A delegate that manages the application lifecycle and network share mounting functionality.
///
/// The `AppDelegate` class is responsible for:
/// - Managing the app's menu bar item and context menu
/// - Monitoring network connectivity and enabling/disabling share mounting
/// - Handling authentication with Kerberos (when enabled)
/// - Mounting and unmounting network shares
/// - Managing user preferences
///
/// It serves as the central coordinator for all major app functions, connecting the UI elements
/// with the underlying mounting and authentication logic.
///
/// ## Menu Bar Integration
/// The app appears as an icon in the macOS menu bar, with a context menu allowing users to:
/// - Mount and unmount network shares
/// - Access mounted shares through Finder
/// - Configure app preferences
/// - Check for updates (if enabled)
///
/// ## Authentication Support
/// The app supports different authentication methods:
/// - Standard macOS credentials
/// - Kerberos Single Sign-On (when configured)
///
/// ## Menu States
/// The menu bar icon changes color to indicate various states:
/// - Default: Standard icon when operating normally
/// - Green: Kerberos authentication successful
/// - Yellow: Authentication issue (non-Kerberos)
/// - Red: Kerberos authentication failure
@main
class AppDelegate: NSObject, NSApplicationDelegate {

    /// The status item displayed in the system menu bar.
    /// This provides the app's primary user interface through a context menu.
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    
    /// The path where network shares are mounted.
    /// This path is used as the default location for all mounted shares.
    var mountpath = ""
    
    /// The object responsible for mounting network shares.
    /// This handles all operations related to connecting, authenticating, and mounting shares.
    var mounter: Mounter?
    
    /// Manages user preferences for the application.
    /// Provides access to stored settings like auto-mount configuration, menu behavior, etc.
    var prefs = PreferenceManager()
    
    /// Flag indicating whether Kerberos authentication is enabled.
    /// When true, the app will attempt to use Kerberos for Single Sign-On authentication.
    var enableKerberos = false
    
    /// Flag indicating if authentication has completed successfully.
    /// This helps track the authentication state throughout the app lifecycle.
    var authDone = false
    
    /// Handles automatic sign-in functionality.
    /// Manages credential storage and retrieval for network shares.
    var automaticSignIn = AutomaticSignIn.shared
    
    /// Monitors network changes to trigger appropriate mount/unmount operations.
    /// Detects when the network becomes available or unavailable.
    let monitor = Monitor.shared
    
    /// Timer for scheduling periodic mount operations.
    /// Triggers mount attempts at regular intervals defined by `Defaults.mountTriggerTimer`.
    var mountTimer = Timer()
    
    /// Timer for scheduling periodic authentication operations.
    /// Triggers authentication checks at regular intervals defined by `Defaults.authTriggerTimer`.
    var authTimer = Timer()
    
    /// Dispatch source for handling unmount signals from external sources.
    /// Responds to SIGUSR1 signals to unmount all shares.
    var unmountSignalSource: DispatchSourceSignal?
    
    /// Dispatch source for handling mount signals from external sources.
    /// Responds to SIGUSR2 signals to mount configured shares.
    var mountSignalSource: DispatchSourceSignal?
    
    /// Controller for managing application updates.
    /// Handles checking for, downloading, and installing app updates when enabled.
    var updaterController: SPUStandardUpdaterController?
    
    /// Controller for monitoring system activity.
    /// Tracks user activity to optimize mount/unmount operations.
    var activityController: ActivityController?
    
    /// Initializes the AppDelegate and sets up the auto-updater if enabled.
    ///
    /// This method:
    /// - Checks if the auto-updater is enabled in user preferences
    /// - Initializes the Sparkle updater controller if updates are enabled
    /// - Configures Sparkle settings based on preferences before starting
    ///
    /// The updater controller is configured with default settings, which can be
    /// customized for more specific control over the update process.
    override init() {
        super.init()
        
        // First check if auto-updater is enabled
        if prefs.bool(for: .disableAutoUpdateFramework) == false {
            // Configure Sparkle defaults before initializing the controller
            let sparkleDefaults = UserDefaults.standard
            
            // Set SUEnableAutomaticChecks from preferences or default to true
            let enableChecks = prefs.bool(for: .SUEnableAutomaticChecks)
            sparkleDefaults.set(enableChecks, forKey: "SUEnableAutomaticChecks")
            
            // Set SUAutomaticallyUpdate from preferences or default to true
            let autoUpdate = prefs.bool(for: .SUAutomaticallyUpdate)
            sparkleDefaults.set(autoUpdate, forKey: "SUAutomaticallyUpdate")
            
            // Only initialize the updater controller if auto-updater is enabled
            updaterController = SPUStandardUpdaterController(
                startingUpdater: enableChecks, // Only start updater if checks are enabled
                updaterDelegate: nil,
                userDriverDelegate: nil)
            
            Logger.app.debug("Sparkle initialized with: checks=\(enableChecks, privacy: .public), auto-update=\(autoUpdate, privacy: .public)")
        } else {
            // Explicitly disable Sparkle in defaults when auto-updater is disabled
            UserDefaults.standard.set(false, forKey: "SUEnableAutomaticChecks")
            Logger.app.debug("Auto-updater disabled via preferences")
        }
    }
    
    /// Performs initial setup when the application launches.
    ///
    /// This method:
    /// 1. Configures diagnostic reporting (if enabled)
    /// 2. Initializes the application window
    /// 3. Sets up the menu bar status item
    /// 4. Configures login item status
    /// 5. Initializes the network share mounter
    /// 6. Sets up signal handlers for external command support
    ///
    /// - Parameter aNotification: The notification object sent when the app finishes launching
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
        // --- Preference Migration Logic for Sparkle --- 
        migrateSparklePreference()
        // --- End Migration Logic ---
        
#if DEBUG
        Logger.appStatistics.debug("🐛 Debugging app, not reporting anything to sentry server ...")
#else
        if prefs.bool(for: .sendDiagnostics) == true {
            Logger.app.debug("Initializing sentry SDK...")
            SentrySDK.start { options in
                options.dsn = Defaults.sentryDSN
                options.debug = false
                
                // Set tracesSampleRate to 1.0 to capture 100% of transactions for tracing.
                // We recommend adjusting this value in production.
                options.tracesSampleRate = 0.1
                // When enabled, the SDK reports SIGTERM signals to Sentry.
                //options.enableSigtermReporting = true
//                options.configureProfiling = {
//                    $0.lifecycle = .trace
//                    $0.sessionSampleRate = 1
//                }
            }
            // Manually call startProfiler and stopProfiler
            // to profile the code in between
            //SentrySDK.startProfiler()
            // this code will be profiled
            //
            // Calls to stopProfiler are optional - if you don't stop the profiler, it will keep profiling
            // your application until the process exits or stopProfiler is called.
            //SentrySDK.stopProfiler()
        }
#endif
        
        // Synchronize Sparkle settings with current preferences
        synchronizeSparkleSettings()
        
        // Initialize the Mounter instance
        mounter = Mounter()
        
        // Set up the status item in the menu bar
        if let button = statusItem.button {
            button.image = NSImage(named: NSImage.Name(MenuImageName.normal.imageName))
        }
        
        // Asynchronously initialize the app
        Task {
            await initializeApp()
        }
        
        // Set up signal handlers for the app
        setupSignalHandlers()
        
        activityController = ActivityController(appDelegate: self)

        Task.detached(priority: .background) { [weak self] in
            guard let self = self else { return }
            Logger.app.debug("Setting LaunchAtLogin state asynchronously via Task...")
            // Der eigentliche Aufruf, der blockieren kann
            LaunchAtLogin.isEnabled = self.prefs.bool(for: .autostart)
            Logger.app.debug("LaunchAtLogin state set via Task.")
        }
    }
    
    /// Migrates the old Sparkle enable preference to the new disable preference if necessary.
    /// The new key `.disableAutoUpdateFramework` takes precedence.
    private func migrateSparklePreference() {
        let defaults = UserDefaults.standard
        let newKey = PreferenceKeys.disableAutoUpdateFramework.rawValue
        let oldKey = PreferenceKeys.enableAutoUpdater.rawValue

        // Check if the new key is already set (by user or MDM)
        if defaults.object(forKey: newKey) != nil {
            Logger.app.info("New preference key '\(newKey)' found. Ignoring old key '\(oldKey)'.")
            // New key exists, no migration needed, its value takes precedence.
        } 
        // Check if the old key exists and the new one doesn't
        else if defaults.object(forKey: oldKey) != nil {
            let oldValue = defaults.bool(forKey: oldKey) // Read the old value
            let newValue = !oldValue // Invert the logic for the new key
            prefs.set(for: .disableAutoUpdateFramework, value: newValue)
            Logger.app.warning("Old preference key '\(oldKey)' found and migrated to '\(newKey)=\(newValue)'. Please update configuration profiles.")
        } else {
            Logger.app.info("Neither new ('\(newKey)') nor old ('\(oldKey)') Sparkle preference key found. Using default value.")
            // Neither key exists, rely on the default registered for disableAutoUpdateFramework (likely false).
        }
    }
    
    /// Synchronizes Sparkle settings with current preferences.
    ///
    /// This method ensures that Sparkle respects the MDM configuration settings
    /// by explicitly setting all Sparkle-related defaults based on the current
    /// preferences. This is especially important when MDM configurations change
    /// without the app being restarted.
    ///
    /// The method:
    /// 1. Checks if auto-updater is enabled overall
    /// 2. Sets all Sparkle-specific keys accordingly
    /// 3. Logs the current configuration for debugging
    private func synchronizeSparkleSettings() {
        let sparkleDefaults = UserDefaults.standard
        // Use the new preference key to determine if the framework is globally disabled
        let autoUpdaterFrameworkDisabled = prefs.bool(for: .disableAutoUpdateFramework)
        
        // If framework is disabled, ensure all Sparkle settings reflect this
        if autoUpdaterFrameworkDisabled {
            sparkleDefaults.set(false, forKey: "SUEnableAutomaticChecks")
            sparkleDefaults.set(false, forKey: "SUAutomaticallyUpdate")
            sparkleDefaults.set(true, forKey: "SUHasLaunchedBefore")
            Logger.app.info("Sparkle framework disabled via 'disableAutoUpdateFramework': Setting all Sparkle settings to false")
            return
        }
        
        // Otherwise, apply the specific settings
        let enableChecks = prefs.bool(for: .SUEnableAutomaticChecks)
        let autoUpdate = prefs.bool(for: .SUAutomaticallyUpdate)
        let hasLaunchedBefore = prefs.bool(for: .SUHasLaunchedBefore)
        
        sparkleDefaults.set(enableChecks, forKey: "SUEnableAutomaticChecks")
        sparkleDefaults.set(autoUpdate, forKey: "SUAutomaticallyUpdate")
        sparkleDefaults.set(hasLaunchedBefore, forKey: "SUHasLaunchedBefore")
        
        Logger.app.info("Sparkle settings synchronized: ")
        Logger.app.info("     enableChecks=\(enableChecks, privacy: .public)")
        Logger.app.info("     autoUpdate=\(autoUpdate, privacy: .public)")
        Logger.app.info("     hasLaunchedBefore=\(hasLaunchedBefore, privacy: .public)")
    }
    
    /// Performs asynchronous initialization tasks for the application.
    ///
    /// This method:
    /// 1. Initializes the mounter component
    /// 2. Sets up the menu
    /// 3. Configures Kerberos if needed
    /// 4. Reports installation statistics
    /// 5. Sets up notification observers
    /// 6. Configures timers for periodic operations
    /// 7. Starts network monitoring
    ///
    /// This method is called asynchronously after the app finishes launching.
    /// It handles tasks that may take longer to complete and should not block
    /// the main application launch sequence.
    private func initializeApp() async {
        Task { @MainActor in
            Logger.app.debug("🔄 Starting asynchronous app initialization")
            
            // Initialize the mounter
            await mounter?.asyncInit()
            Logger.app.debug("✅ Mounter successfully initialized")
            
            // Always build the menu, regardless of the mounter status
            await self.constructMenu(withMounter: self.mounter)
            Logger.app.debug("✅ Initial menu constructed")
            
            // Check if a kerberos domain/realm is set and is not empty
            if let krbRealm = self.prefs.string(for: .kerberosRealm), !krbRealm.isEmpty {
                Logger.app.info("Enabling Kerberos Realm \(krbRealm, privacy: .public).")
                self.enableKerberos = true
                
                // Check for existing valid Kerberos tickets
                let klist = KlistUtil()
                let principals = await klist.klist()
                if !principals.isEmpty {
                    Logger.app.info("Found existing Kerberos tickets, updating menu icon.")
                    Task { @MainActor in
                        if let button = self.statusItem.button {
                            button.image = NSImage(named: NSImage.Name(MenuImageName.green.imageName))
                        }
                    }
                }
            } else {
                Logger.app.info("No Kerberos Realm found.")
            }
            
            // Initialize statistics reporting
            let stats = AppStatistics.init()
            await stats.reportAppInstallation()
            Logger.app.debug("✅ App installation statistics reported")
            
            await AccountsManager.shared.initialize()
            Logger.app.debug("✅ Account manager initialized")
            
            // Perform one-time migration from legacy credentials to profiles
            let migrationKey = "AuthProfileMigrationCompleted_v3.2"
            if !UserDefaults.standard.bool(forKey: migrationKey) {
                do {
                    try await AuthProfileManager.shared.migrateFromLegacyCredentials()
                    UserDefaults.standard.set(true, forKey: migrationKey)
                    Logger.app.info("✅ Profile migration completed successfully")
                } catch {
                    Logger.app.error("❌ Profile migration failed: \(error)")
                }
            } else {
                Logger.app.debug("Profile migration already completed, skipping")
            }
            
            // Set up notification observer for error handling
            if mounter != nil {
                NotificationCenter.default.addObserver(self, selector: #selector(handleErrorNotification(_:)), name: .nsmNotification, object: nil)
                Logger.app.debug("✅ Error notification observer registered")
            } else {
                Logger.app.error("Could not initialize mounter class, this should never happen.")
            }
            
            // Trigger user authentication on app start
            Logger.app.debug("Trigger user authentication on app startup.")
            NotificationCenter.default.post(name: Defaults.nsmAuthTriggerNotification, object: nil)
            
            // Set up periodic mount timer
            self.mountTimer = Timer.scheduledTimer(withTimeInterval: Defaults.mountTriggerTimer, repeats: true, block: { _ in
                Logger.app.debug("Passed \(Defaults.mountTriggerTimer, privacy: .public) seconds, performing operartions:")
                NotificationCenter.default.post(name: Defaults.nsmTimeTriggerNotification, object: nil)
            })
            
            // Set up periodic authentication timer
            self.authTimer = Timer.scheduledTimer(withTimeInterval: Defaults.authTriggerTimer, repeats: true, block: { _ in
                Logger.app.debug("Passed \(Defaults.authTriggerTimer, privacy: .public) seconds, performing operartions:")
                NotificationCenter.default.post(name: Defaults.nsmAuthTriggerNotification, object: nil)
            })
            
            // Debug log to confirm timers were initialized
            Logger.app.info("Timer actualized on main thread - Mount: \(self.mountTimer.isValid, privacy: .public), Auth: \(self.authTimer.isValid, privacy: .public)")
            
            // Start network connectivity monitoring
            monitor.startMonitoring { [weak self] connection, reachable in
                guard let self = self else { return }
                
                if reachable.rawValue == "yes" {
                    Logger.app.debug("Network is reachable, firing nsmNetworkChangeTriggerNotification and nsmAuthTriggerNotification.")
                    // Network is available - trigger connection and authentication
                    NotificationCenter.default.post(name: Defaults.nsmNetworkChangeTriggerNotification, object: nil)
                    NotificationCenter.default.post(name: Defaults.nsmAuthTriggerNotification, object: nil)
                } else {
                    // Network is unavailable - unmount shares and reset status
                    // Using a long-lasting task with @MainActor
                    let networkTask = Task { @MainActor in
                        Logger.app.debug("🔄 Network monitoring callback - unmounting shares")
                        NotificationCenter.default.post(name: Defaults.nsmAuthTriggerNotification, object: nil)
                        // Since the mount status after a network change is unknown it will be set
                        // to undefined so it can be tested and maybe remounted if the network connects again
                        Logger.app.debug("Got network monitoring callback, unmount shares.")
                        if let mounter = self.mounter {
                            await mounter.setAllMountStatus(to: MountStatus.undefined)
                            // Trying to unmount all shares
                            NotificationCenter.default.post(name: Defaults.nsmUnmountTriggerNotification, object: nil)
                            await mounter.unmountAllMountedShares()
                            Logger.app.debug("✅ Network monitoring - shares unmounted successfully")
                        } else {
                            Logger.app.error("Could not initialize mounter class, this should never happen.")
                        }
                    }
                    _ = networkTask
                }
            }
            
            // Trigger initial mount operation
            NotificationCenter.default.post(name: Defaults.nsmTimeTriggerNotification, object: nil)
            Logger.app.debug("🎉 App initialization completed successfully")
        }
    }

    /// Performs cleanup when the application is about to terminate.
    ///
    /// This method:
    /// 1. Stops network monitoring
    /// 2. Unmounts all shares if configured to do so in preferences
    ///
    /// - Parameter aNotification: The notification object sent when the app is terminating
    func applicationWillTerminate(_ aNotification: Notification) {
        // End network monitoring
        monitor.monitor.cancel()
        
        // Unmount all shares before exiting if configured in preferences
        if prefs.bool(for: .unmountOnExit) == true {
            Logger.app.debug("Exiting app, unmounting shares...")
            unmountShares(self)
            // Wait briefly to allow unmount operations to complete
            // This ensures shares are properly unmounted before the app exits
            sleep(3)
        }
    }
    
    /// Handles various error notifications and updates the menu bar icon accordingly.
    ///
    /// This method processes notifications related to authentication and connectivity status,
    /// updating the menu bar icon color to reflect the current state:
    /// - Red: Kerberos authentication error
    /// - Yellow: General authentication error
    /// - Green: Successful Kerberos authentication
    /// - Default: Normal operation or error cleared
    ///
    /// It also updates the menu structure based on the current error state.
    ///
    /// - Parameter notification: The notification containing error information.
    @objc func handleErrorNotification(_ notification: NSNotification) {
        // Handle Kerberos authentication error
        if notification.userInfo?["KrbAuthError"] is Error {
            Logger.app.debug("🔔 [DEBUG] Processing KrbAuthError path")
            
            // Check if we have successfully mounted shares before setting error status
            Task { @MainActor in
                let hasMountedShares = await mounter?.shareManager.allShares.contains { $0.mountStatus == .mounted } ?? false
                
                if hasMountedShares {
                    Logger.app.debug("🔔 [DEBUG] Shares are mounted - ignoring Kerberos error to prevent status override")
                    return
                }
                
                Logger.app.debug("🔔 [DEBUG] No mounted shares - proceeding with Kerberos error handling")
                if let button = statusItem.button, enableKerberos {
                    button.image = NSImage(named: NSImage.Name("networkShareMounterMenuRed"))
                    mounter?.setErrorStatus(.krbAuthenticationError)
                    await constructMenu(withMounter: mounter, andStatus: .krbAuthenticationError)
                }
            }
        }
        // Handle general authentication error
        else if notification.userInfo?["AuthError"] is Error {
            Logger.app.debug("🔔 [DEBUG] Processing AuthError path")
            
            // Check if we have successfully mounted shares before setting error status
            Task { @MainActor in
                let hasMountedShares = await mounter?.shareManager.allShares.contains { $0.mountStatus == .mounted } ?? false
                
                if hasMountedShares {
                    Logger.app.debug("🔔 [DEBUG] Shares are mounted - ignoring Auth error to prevent status override")
                    return
                }
                
                // No mounted shares, proceed with error handling
                if let button = self.statusItem.button {
                    button.image = NSImage(named: NSImage.Name("networkShareMounterMenuYellow"))
                    self.mounter?.setErrorStatus(.authenticationError)
                    await self.constructMenu(withMounter: self.mounter, andStatus: .authenticationError)
                }
            }
        }
        // Handle error clearance
        else if notification.userInfo?["ClearError"] is Error {
            Logger.app.debug("🔔 [DEBUG] Processing ClearError path")
            Task { @MainActor in
                // Change the color of the menu symbol to default
                if let button = self.statusItem.button {
                    button.image = NSImage(named: NSImage.Name("networkShareMounter"))
                    self.mounter?.setErrorStatus(.noError)
                    await self.constructMenu(withMounter: self.mounter)
                }
            }
        }
        // Handle successful Kerberos authentication
        else if notification.userInfo?["krbAuthenticated"] is Error {
            Logger.app.debug("🔔 [DEBUG] Processing krbAuthenticated path")
            Task { @MainActor in
                if let button = self.statusItem.button, self.enableKerberos {
                    button.image = NSImage(named: NSImage.Name("networkShareMounterMenuGreen"))
                    self.mounter?.setErrorStatus(.noError)
                    await self.constructMenu(withMounter: self.mounter)
                }
            }
        }
        // Handle general failure
        else if notification.userInfo?["FailError"] is Error {
            Task { @MainActor in
                if let button = self.statusItem.button {
                    button.image = NSImage(named: NSImage.Name("networkShareMounterMenuFail"))
                    self.mounter?.setErrorStatus(.otherError)
                    await self.constructMenu(withMounter: self.mounter)
                }
            }
        }
        // Handle Kerberos off-domain status
        else if notification.userInfo?["krbOffDomain"] is Error {
            Logger.app.debug("🔔 [DEBUG] Processing krbOffDomain path")
            Task { @MainActor in
                // Change the color of the menu symbol to default when off domain
                if let button = statusItem.button, enableKerberos {
                    button.image = NSImage(named: NSImage.Name("networkShareMounter"))
                    mounter?.setErrorStatus(.offDomain)
                    await constructMenu(withMounter: mounter)
                }
            }
        }
        
        // Handle Kerberos unreachable (KDC/Network issues)
        else if notification.userInfo?["krbUnreachable"] is Error {
            Logger.app.debug("🔔 [DEBUG] Processing krbUnreachable path")
            Task { @MainActor in
                if let button = statusItem.button, enableKerberos {
                    button.image = NSImage(named: NSImage.Name("networkShareMounter")) // Farblos
                    mounter?.setErrorStatus(.offDomain)
                    await constructMenu(withMounter: mounter)
                }
            }
        }
    }

    /// Indicates whether the application supports secure restorable state.
    ///
    /// This method always returns true, indicating that the application
    /// supports secure state restoration in macOS.
    ///
    /// - Parameter app: The NSApplication instance.
    /// - Returns: Always returns true for this application.
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    /// Displays information about the Network Share Mounter.
    ///
    /// Currently a placeholder that logs an informational message.
    /// In the future, this could be implemented to show detailed information
    /// about the application, such as version number, configuration, etc.
    ///
    /// - Parameter sender: The object that initiated this action.
    @objc func showInfo(_ sender: Any?) {
        Logger.app.info("Some day maybe show some useful information about Network Share Mounter")
    }

    /// Opens the specified directory in Finder
    ///
    /// This method extracts a directory path from a menu item's `representedObject` property
    /// and opens it in Finder. It's typically used to open mounted network shares.
    ///
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
    
    /// Manually triggers the mounting of all configured shares.
    ///
    /// This method is typically called when the user selects "Mount shares" from the menu.
    /// It posts notifications to:
    /// 1. Trigger authentication if needed
    /// 2. Start the mounting process for all configured shares
    ///
    /// - Parameter sender: The object that triggered the action
    @objc func mountManually(_ sender: Any?) {
        Logger.app.debug("User triggered mount all shares")
        NotificationCenter.default.post(name: Defaults.nsmAuthTriggerNotification, object: nil)
        NotificationCenter.default.post(name: Defaults.nsmMountManuallyTriggerNotification, object: nil)
    }

    /// Unmounts all currently mounted network shares.
    ///
    /// This method is typically called when the user selects "Unmount shares" from the menu.
    /// It instructs the mounter to safely disconnect all mounted shares.
    ///
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
    
    /// Mounts a specific network share when selected from the menu.
    ///
    /// This method is called when the user selects a specific unmounted share from the menu.
    /// It attempts to mount only that share and then refreshes Finder to show the new mount.
    ///
    /// - Parameter sender: Menu item containing the share ID to mount
    @objc func mountSpecificShare(_ sender: NSMenuItem) {
        if let shareID = sender.representedObject as? String {
            Logger.app.debug("User triggered to mount share with id \(shareID, privacy: .public)")
            Task {
                if let mounter = mounter {
                    await mounter.mountGivenShares(userTriggered: true, forShare: shareID)
                    let finderController = FinderController()
                    let mountPaths = await finderController.getActualMountPaths(from: mounter)
                    await finderController.refreshFinder(forPaths: mountPaths)
                } else {
                    Logger.app.error("Could not initialize mounter class, this should never happen.")
                }
            }
        }
    }

    /// Opens the help URL in the default web browser.
    ///
    /// This method opens the help URL configured in preferences in the system's default browser.
    /// The URL is retrieved from preferences using the `.helpURL` key.
    ///
    /// - Parameter sender: The object that triggered the action
    @objc func openHelpURL(_ sender: Any?) {
        guard let url = prefs.string(for: .helpURL), let openURL = URL(string: url) else {
            // TODO: Consider adding error logging or user feedback if URL is invalid
            return
        }
        NSWorkspace.shared.open(openURL)
    }

    /// Shows the new SwiftUI settings window.
    @objc func showSettingsWindowSwiftUI(_ sender: Any?) {
        SettingsWindowManager.shared.showSettingsWindow()
    }
    
    /// Sets up signal handlers for mounting and unmounting shares.
    ///
    /// This method configures the application to respond to UNIX signals:
    /// - SIGUSR1: Unmount all shares
    /// - SIGUSR2: Mount all configured shares
    ///
    /// These signals allow external processes to trigger mount/unmount operations.
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
            guard let self = self else { return }
            
            Logger.app.debug("🚦Received unmount signal.")
            
            let signalTask = Task { @MainActor in
                Logger.app.debug("🔄 Processing unmount signal")
                await self.mounter?.unmountAllMountedShares(userTriggered: false)
                Logger.app.debug("✅ Unmount signal processing completed")
            }
            
            _ = signalTask
        }

        // Set up event handler for mount signal
        mountSignalSource?.setEventHandler { [weak self] in
            guard let self = self else { return }
            
            Logger.app.debug("🚦Received mount signal.")
            
            let signalTask = Task { @MainActor in
                Logger.app.debug("🔄 Processing mount signal")
                await self.mounter?.mountGivenShares(userTriggered: true)
                Logger.app.debug("✅ Mount signal processing completed")
            }
            
            _ = signalTask
        }

        // Activate the signal sources
        unmountSignalSource?.resume()
        mountSignalSource?.resume()
        
        Logger.app.debug("✅ Signal handlers configured successfully")
    }
    
    /// Constructs the app's menu based on configured profiles and current status.
    ///
    /// This method builds the context menu that appears when the user clicks
    /// the app's menu bar icon. The menu adapts based on:
    /// - The current error state (if any)
    /// - Available network shares
    /// - User preferences
    /// - Auto-updater availability
    ///
    /// The menu is built dynamically each time it's shown, reflecting the
    /// current state of network shares and app configuration.
    ///
    /// - Parameters:
    ///   - mounter: The Mounter object responsible for mounting/unmounting shares
    ///   - andStatus: Optional MounterError indicating any current error state
    @MainActor func constructMenu(withMounter mounter: Mounter?, andStatus: MounterError? = nil) async {
        let menu = NSMenu()
        menu.autoenablesItems = false
        
        // Determine the status to use: explicit parameter or mounter's current error status
        let statusToUse = andStatus ?? mounter?.errorStatus
        
        // Handle different error states and construct appropriate menu items
        if let mounter = mounter {
            switch statusToUse {
            case .krbAuthenticationError:
                Logger.app.debug("🏗️ Constructing Kerberos authentication problem menu.")
//                mounter.setErrorStatus(.authenticationError)
                menu.addItem(NSMenuItem(title: NSLocalizedString("⚠️ Kerberos SSO Authentication problem...", comment: "Kerberos Authentication problem"),
                                        action: #selector(AppDelegate.showSettingsWindowSwiftUI(_:)), keyEquivalent: ""))
                menu.addItem(NSMenuItem.separator())
            case .authenticationError:
                Logger.app.debug("🏗️ Constructing authentication problem menu.")
//                mounter.setErrorStatus(.authenticationError)
                menu.addItem(NSMenuItem(title: NSLocalizedString("⚠️ Authentication problem...", comment: "Authentication problem"),
                                        action: #selector(AppDelegate.showSettingsWindowSwiftUI(_:)), keyEquivalent: ""))
                menu.addItem(NSMenuItem.separator())
                
            default:
                mounter.setErrorStatus(.noError)
                Logger.app.debug("🏗️ Constructing default menu.")
            }
        } else {
            Logger.app.debug("🏗️ Constructing basic menu without mounter.")
        }
        
        // Add "About" menu item if help URL is valid
        if let urlString = prefs.string(for: .helpURL), URL(string: urlString) != nil {
            if let newMenuItem = createMenuItem(title: "About Network Share Mounter",
                                                  comment: "About Network Share Mounter",
                                                  action: #selector(AppDelegate.openHelpURL(_:)),
                                                  keyEquivalent: "",
                                                  preferenceKey: .menuAbout,
                                                  prefs: prefs) {
                menu.addItem(newMenuItem)
            }
        }
        
        // Add core functionality menu items only if mounter is available
        if mounter != nil {
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
                newMenuItem.representedObject = mounter?.defaultMountPath
                menu.addItem(newMenuItem)
            }
        }
        
        // Add "Check for Updates" menu item if auto-updater is enabled
        if prefs.bool(for: .enableAutoUpdater) == true && updaterController != nil {
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
        
        // Add share-specific menu items only if mounter is available and shares exist
        if let mounter = mounter {
            let menuShowSharesValue = prefs.string(for: .menuShowShares) ?? ""
            // Only add separator and share entries if shares exist
            if await !mounter.shareManager.getAllShares().isEmpty {
                menu.addItem(NSMenuItem.separator())
                for share in await mounter.shareManager.allShares {
                    var menuItem: NSMenuItem
                    
                    // If share is mounted, use the mountpoint icon
                    if let mountpoint = share.actualMountPoint {
                        let mountDir = (mountpoint as NSString).lastPathComponent
                        Logger.app.debug("  Menu: 🍰 Adding mountpoint \(mountDir, privacy: .public) for \(share.networkShare, privacy: .public) to menu.")
                        
                        let menuIcon = createMenuIcon(withIcon: "externaldrive.connected.to.line.below.fill", backgroundColor: .systemBlue, symbolColor: .white)
                        menuItem = NSMenuItem(title: NSLocalizedString(mountDir, comment: ""),
                                              action: #selector(AppDelegate.openDirectory(_:)),
                                              keyEquivalent: "")
                        menuItem.representedObject = mountpoint
                        menuItem.image = menuIcon
                    } else {
                        // If share is not mounted, use the standard icon
                        Logger.app.debug("  Menu: 🍰 Adding remote share \(share.networkShare, privacy: .public).")
                        let menuIcon = createMenuIcon(withIcon: "externaldrive.connected.to.line.below", backgroundColor: .systemGray, symbolColor: .white)
                        // Use shareDisplayName if available, otherwise networkShare
                        let menuItemTitle = share.shareDisplayName ?? share.networkShare
                        menuItem = NSMenuItem(title: NSLocalizedString(menuItemTitle, comment: "Menu item title for a specific share"),
                                              action: #selector(AppDelegate.mountSpecificShare(_:)),
                                              keyEquivalent: "")
                        menuItem.representedObject = share.id
                        menuItem.image = menuIcon
                    }
                    
                    // Configure menu item based on preference value
                    switch menuShowSharesValue {
                    case "hidden":
                        // Skip adding this menu item
                        continue
                    case "disabled":
                        // Add menu item but disable it
                        menuItem.isEnabled = false
                    default:
                        // Add menu item normally and enable it
                        menuItem.isEnabled = true
                    }
                    
                    // Add the configured menu item
                    menu.addItem(menuItem)
                }
            }
        }
        
        // Add "Preferences" menu item
        if let newMenuItem = createMenuItem(title: "Preferences ...",
                                              comment: "Preferences",
                                              action: #selector(AppDelegate.showSettingsWindowSwiftUI(_:)),
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
    
    /// Creates and configures a menu item based on user preferences.
    ///
    /// This factory method creates menu items that respect user preferences for
    /// visibility and enabled/disabled state. Menu items can be:
    /// - Hidden (not added to menu)
    /// - Disabled (shown but not clickable)
    /// - Enabled (normal operation)
    ///
    /// - Parameters:
    ///   - title: The localized title text for the menu item
    ///   - comment: A comment for localization context
    ///   - action: The selector to be called when menu item is clicked
    ///   - keyEquivalent: The keyboard shortcut for the menu item
    ///   - preferenceKey: The preference key to check the menu item's state
    ///   - prefs: The preference manager instance to retrieve settings
    ///
    /// - Returns: A configured NSMenuItem instance, or nil if the menu item should be hidden
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
    
    /// Creates a custom menu bar icon with a colored background circle and SF Symbol.
    ///
    /// This method generates custom icons for the menu, particularly for network shares
    /// with different statuses (mounted/unmounted).
    ///
    /// - Parameters:
    ///   - withIcon: The name of the SF Symbol to use
    ///   - backgroundColor: The background color of the circular icon
    ///   - symbolColor: The color of the SF Symbol
    ///
    /// - Returns: An NSImage containing the composed icon
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

