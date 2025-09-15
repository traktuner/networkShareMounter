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
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {

    /// The status item displayed in the system menu bar.
    /// This provides the app's primary user interface through a context menu.
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    
    /// The main application window used for displaying preferences.
    var window = NSWindow()
    
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
    
    // MARK: - Reentrancy/Debounce for SIGUSR2 mount runs
    /// Indicates whether a SIGUSR2-triggered mount is currently running.
    /// Used to guard against parallel mount runs when multiple signals arrive quickly.
    private var isMountInProgress: Bool = false
    
    /// Stores the last mount run ID for logging purposes.
    private var lastMountRunID: String?

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
                options.tracesSampleRate = 0.1
            }
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
    
    private func initializeApp() async {
        Task { @MainActor in
            Logger.app.debug("🔄 Starting asynchronous app initialization")
            
            // Perform one-time migration from legacy credentials to profiles BEFORE mounter init
            let migrationKey = "AuthProfileMigrationCompleted_v3.0"
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
            
            // Initialize the mounter AFTER migration
            await mounter?.asyncInit()
            Logger.app.debug("✅ Mounter successfully initialized")
            
            // NEW: Rescan existing mounts at app start, independent of network state
            if let mounter = self.mounter {
                Logger.app.debug("🔍 Performing initial rescan of existing mounts")
                await mounter.rescanExistingMounts()
            }
            
            await self.constructMenu(withMounter: self.mounter)
            Logger.app.debug("✅ Initial menu constructed")
            
            if let krbRealm = self.prefs.string(for: .kerberosRealm), !krbRealm.isEmpty {
                Logger.app.info("Enabling Kerberos Realm \(krbRealm, privacy: .public).")
                self.enableKerberos = true
                
                let klist = KlistUtil()
                let principals = await klist.klist()
                if !principals.isEmpty {
                    Logger.app.info("Found existing Kerberos tickets, updating menu icon.")
                    await MainActor.run {
                        if let button = self.statusItem.button {
                            button.image = NSImage(named: NSImage.Name(MenuImageName.green.imageName))
                        }
                    }
                }
            } else {
                Logger.app.info("No Kerberos Realm found.")
            }
            
            let stats = AppStatistics.init()
            await stats.reportAppInstallation()
            Logger.app.debug("✅ App installation statistics reported")
            
            await AccountsManager.shared.initialize()
            Logger.app.debug("✅ Account manager initialized")
            
            // Create default realm profile if needed (always check on startup)
            do {
                try await AuthProfileManager.shared.createDefaultRealmProfileIfNeeded()
                Logger.app.debug("✅ Default realm profile check completed")
            } catch {
                Logger.app.error("❌ Default realm profile creation failed: \(error)")
            }

            // Check if MDM requires Kerberos setup and auto-open settings if needed
            if let mdmRealm = AuthProfileManager.shared.needsMDMKerberosSetup() {
                Logger.app.info("🔧 MDM Kerberos realm '\(mdmRealm)' configured but no profile exists. Auto-opening settings for user setup.")
                await MainActor.run {
                    // Auto-open settings window with profile creation dialog
                    SettingsWindowManager.shared.showSettingsWindow(autoOpenProfileCreation: true, mdmRealm: mdmRealm)
                }
            }
            
            if mounter != nil {
                NotificationCenter.default.addObserver(self, selector: #selector(handleErrorNotification(_:)), name: .nsmNotification, object: nil)
                Logger.app.debug("✅ Error notification observer registered")
            } else {
                Logger.app.error("Could not initialize mounter class, this should never happen.")
            }
            
            Logger.app.debug("Trigger user authentication on app startup.")
            NotificationCenter.default.post(name: Defaults.nsmAuthTriggerNotification, object: nil)
            
            self.mountTimer = Timer.scheduledTimer(withTimeInterval: Defaults.mountTriggerTimer, repeats: true, block: { _ in
                Logger.app.debug("Passed \(Defaults.mountTriggerTimer, privacy: .public) seconds, performing operartions:")
                NotificationCenter.default.post(name: Defaults.nsmTimeTriggerNotification, object: nil)
            })
            
            self.authTimer = Timer.scheduledTimer(withTimeInterval: Defaults.authTriggerTimer, repeats: true, block: { _ in
                Logger.app.debug("Passed \(Defaults.authTriggerTimer, privacy: .public) seconds, performing operartions:")
                NotificationCenter.default.post(name: Defaults.nsmAuthTriggerNotification, object: nil)
            })
            
            Logger.app.info("Timer actualized on main thread - Mount: \(self.mountTimer.isValid, privacy: .public), Auth: \(self.authTimer.isValid, privacy: .public)")
            
            await monitor.startMonitoring { [weak self] connection, reachable in
                guard let self = self else { return }
                
                if reachable.rawValue == "yes" {
                    Logger.app.debug("Network is reachable, firing nsmNetworkChangeTriggerNotification and nsmAuthTriggerNotification.")
                    NotificationCenter.default.post(name: Defaults.nsmNetworkChangeTriggerNotification, object: nil)
                    NotificationCenter.default.post(name: Defaults.nsmAuthTriggerNotification, object: nil)
                } else {
                    let networkTask = Task { @MainActor in
                        Logger.app.debug("🔄 Network monitoring callback - unmounting shares")
                        NotificationCenter.default.post(name: Defaults.nsmAuthTriggerNotification, object: nil)
                        Logger.app.debug("Got network monitoring callback, unmount shares.")
                        if let mounter = self.mounter {
                            await mounter.setAllMountStatus(to: MountStatus.undefined)
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
            
            NotificationCenter.default.post(name: Defaults.nsmTimeTriggerNotification, object: nil)
            Logger.app.debug("🎉 App initialization completed successfully")
        }
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        monitor.monitor.cancel()
        
        if prefs.bool(for: .unmountOnExit) == true {
            Logger.app.debug("Exiting app, unmounting shares...")
            unmountShares(self)
            sleep(3)
        }
    }
    
    @objc func handleErrorNotification(_ notification: NSNotification) {
        if notification.userInfo?["KrbAuthError"] is Error {
            Logger.app.debug("🔔 [DEBUG] Processing KrbAuthError path")
            Task { @MainActor in
                let hasMountedShares = await mounter?.shareManager.allShares.contains { $0.mountStatus == .mounted } ?? false
                if hasMountedShares {
                    Logger.app.debug("🔔 [DEBUG] Shares are mounted - ignoring Kerberos error to prevent status override")
                    return
                }
                Logger.app.debug("🔔 [DEBUG] No mounted shares - proceeding with Kerberos error handling")
                if let button = self.statusItem.button, self.enableKerberos {
                    button.image = NSImage(named: NSImage.Name("networkShareMounterMenuRed"))
                    self.mounter?.setErrorStatus(.krbAuthenticationError)
                    await self.constructMenu(withMounter: self.mounter, andStatus: .krbAuthenticationError)
                }
            }
        }
        else if notification.userInfo?["AuthError"] is Error {
            Logger.app.debug("🔔 [DEBUG] Processing AuthError path")
            Task { @MainActor in
                let hasMountedShares = await mounter?.shareManager.allShares.contains { $0.mountStatus == .mounted } ?? false
                if hasMountedShares {
                    Logger.app.debug("🔔 [DEBUG] Shares are mounted - ignoring Auth error to prevent status override")
                    return
                }
                if let button = self.statusItem.button {
                    button.image = NSImage(named: NSImage.Name("networkShareMounterMenuYellow"))
                    self.mounter?.setErrorStatus(.authenticationError)
                    await self.constructMenu(withMounter: self.mounter, andStatus: .authenticationError)
                }
            }
        }
        else if notification.userInfo?["ClearError"] is Error {
            Logger.app.debug("🔔 [DEBUG] Processing ClearError path")
            Task { @MainActor in
                if let button = self.statusItem.button {
                    button.image = NSImage(named: NSImage.Name(MenuImageName.normal.imageName))
                    self.mounter?.setErrorStatus(.noError)
                    await self.constructMenu(withMounter: self.mounter)
                }
            }
        }
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
        else if notification.userInfo?["FailError"] is Error {
            Task { @MainActor in
                if let button = self.statusItem.button {
                    button.image = NSImage(named: NSImage.Name("networkShareMounterMenuFail"))
                    self.mounter?.setErrorStatus(.otherError)
                    await self.constructMenu(withMounter: self.mounter)
                }
            }
        }
        else if notification.userInfo?["krbOffDomain"] is Error {
            Logger.app.debug("🔔 [DEBUG] Processing krbOffDomain path")
            Task { @MainActor in
                // Change the color of the menu symbol to default when off domain
                if let button = self.statusItem.button, self.enableKerberos {
                    button.image = NSImage(named: NSImage.Name("networkShareMounter"))
                    self.mounter?.setErrorStatus(.offDomain)
                    await self.constructMenu(withMounter: self.mounter)
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

    @objc func openDirectory(_ sender: NSMenuItem) {
        if let openMountedDir = sender.representedObject as? String,
           let mountDirectory = URL(string: openMountedDir) {
            Logger.app.info("Trying to open \(mountDirectory, privacy: .public) in Finder...")
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: mountDirectory.path)
        } else {
            Logger.app.error("Could not initialize mounter class, this should never happen.")
        }
    }
    
    @objc func mountManually(_ sender: Any?) {
        Logger.app.debug("User triggered mount all shares")
        NotificationCenter.default.post(name: Defaults.nsmAuthTriggerNotification, object: nil)
        NotificationCenter.default.post(name: Defaults.nsmMountManuallyTriggerNotification, object: nil)
    }

    @objc func unmountShares(_ sender: Any?) {
        Logger.app.debug("User triggered unmount all shares")
        Task {
            if let mounter = mounter {
                await mounter.unmountAllMountedShares(userTriggered: true)
            } else {
                Logger.app.error("Could not initialize mounter class, this should never happen.")
            }
        }
    }
    
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

    @objc func openHelpURL(_ sender: Any?) {
        guard let url = prefs.string(for: .helpURL), let openURL = URL(string: url) else {
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
        let unmountSignal = SIGUSR1
        let mountSignal = SIGUSR2

        signal(unmountSignal, SIG_IGN)
        signal(mountSignal, SIG_IGN)

        unmountSignalSource = DispatchSource.makeSignalSource(signal: unmountSignal, queue: .main)
        mountSignalSource = DispatchSource.makeSignalSource(signal: mountSignal, queue: .main)

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

        // IMPROVED: Reentrancy guard + run mount off the MainActor with run ID logging
        mountSignalSource?.setEventHandler { [weak self] in
            guard let self = self else { return }
            Logger.app.debug("🚦Received mount signal.")
            
            // Debounce/Reentrancy: ignore if a mount is already in progress
            if self.isMountInProgress {
                Logger.app.info("⏭️ Mount signal ignored: another mount run is still in progress (runID=\(self.lastMountRunID ?? "-", privacy: .public)).")
                return
            }
            
            // Mark as in progress and assign a unique run ID
            self.isMountInProgress = true
            let runID = UUID().uuidString
            self.lastMountRunID = runID
            let startTime = Date()
            Logger.app.info("🔄 [Mount Run \(runID, privacy: .public)] Starting background mount (SIGUSR2).")
            
            // Offload the actual work
            let signalTask = Task.detached(priority: .utility) { [weak self] in
                guard let self = self else { return }
                do {
                    await self.mounter?.mountGivenShares(userTriggered: true)
                }
                
                // Finish and log duration on MainActor (to safely touch state/UI)
                await MainActor.run {
                    let duration = Date().timeIntervalSince(startTime)
                    let formattedDuration = String(format: "%.2f", duration)
                    Logger.app.info("✅ [Mount Run \(runID, privacy: .public)] Completed in \(formattedDuration)s.")
                    self.isMountInProgress = false
                }
            }
            _ = signalTask
        }

        unmountSignalSource?.resume()
        mountSignalSource?.resume()
        
        Logger.app.debug("✅ Signal handlers configured successfully")
    }
    
    @MainActor func constructMenu(withMounter mounter: Mounter?, andStatus: MounterError? = nil) async {
        let menu = NSMenu()
        menu.autoenablesItems = false
        
        let statusToUse = andStatus ?? mounter?.errorStatus
        
        if let mounter = mounter {
            switch statusToUse {
            case .krbAuthenticationError:
                Logger.app.debug("🏗️ Constructing Kerberos authentication problem menu.")
                menu.addItem(NSMenuItem(title: NSLocalizedString("⚠️ Kerberos SSO Authentication problem...", comment: "Kerberos Authentication problem"),
                                        action: #selector(AppDelegate.showSettingsWindowSwiftUI(_:)), keyEquivalent: ""))
                menu.addItem(NSMenuItem.separator())
            case .authenticationError:
                Logger.app.debug("🏗️ Constructing authentication problem menu.")
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
        
        if mounter != nil {
            if let newMenuItem = createMenuItem(title: "Mount shares",
                                                  comment: "Mount share",
                                                  action: #selector(AppDelegate.mountManually(_:)),
                                                  keyEquivalent: "m",
                                                  preferenceKey: .menuConnectShares,
                                                  prefs: prefs) {
                menu.addItem(newMenuItem)
            }
            if let newMenuItem = createMenuItem(title: "Unmount shares",
                                                  comment: "Unmount shares",
                                                  action: #selector(AppDelegate.unmountShares(_:)),
                                                  keyEquivalent: "u",
                                                  preferenceKey: .menuDisconnectShares,
                                                  prefs: prefs) {
                menu.addItem(newMenuItem)
            }
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
        
        if let mounter = mounter {
            let menuShowSharesValue = prefs.string(for: .menuShowShares) ?? ""
            if await !mounter.shareManager.getAllShares().isEmpty {
                menu.addItem(NSMenuItem.separator())
                for share in await mounter.shareManager.allShares {
                    var menuItem: NSMenuItem
                    
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
                    
                    switch menuShowSharesValue {
                    case "hidden":
                        continue
                    case "disabled":
                        menuItem.isEnabled = false
                    default:
                        menuItem.isEnabled = true
                    }
                    
                    menu.addItem(menuItem)
                }
            }
        }
        
        if let newMenuItem = createMenuItem(title: "Preferences ...",
                                              comment: "Preferences",
                                              action: #selector(AppDelegate.showSettingsWindowSwiftUI(_:)),
                                              keyEquivalent: ",",
                                              preferenceKey: .menuSettings,
                                              prefs: prefs) {
            menu.addItem(NSMenuItem.separator())
            menu.addItem(newMenuItem)
        }
        
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
        
        statusItem.menu = menu
    }
    
    func createMenuItem(title: String, comment: String, action: Selector, keyEquivalent: String, preferenceKey: PreferenceKeys, prefs: PreferenceManager) -> NSMenuItem? {
        let preferenceValue = prefs.string(for: preferenceKey) ?? ""
        let localizedTitle = NSLocalizedString(title, comment: "")
        let menuItem = NSMenuItem(title: NSLocalizedString(localizedTitle, comment: comment),
                                  action: action,
                                  keyEquivalent: keyEquivalent)
        
        switch preferenceValue {
        case "hidden":
            return nil
        case "disabled":
            menuItem.isEnabled = false
        default:
            menuItem.isEnabled = true
        }
        return menuItem
    }
    
    func createMenuIcon(withIcon: String, backgroundColor: NSColor, symbolColor: NSColor) -> NSImage {
        let symbolImage = NSImage(systemSymbolName: "externaldrive.connected.to.line.below.fill", accessibilityDescription: nil)!
        let templateImage = symbolImage.copy() as! NSImage
        templateImage.isTemplate = true
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        let configuredSymbolImage = templateImage.withSymbolConfiguration(symbolConfig)
        let circleSize = NSSize(width: 24, height: 24)
        let circleImage = NSImage(size: circleSize)
        circleImage.lockFocus()
        let circlePath = NSBezierPath(ovalIn: NSRect(origin: .zero, size: circleSize))
        backgroundColor.setFill()
        circlePath.fill()
        if let configuredSymbolImage = configuredSymbolImage {
            let symbolRect = NSRect(
                x: (circleSize.width - configuredSymbolImage.size.width) / 2,
                y: (circleSize.height - configuredSymbolImage.size.height) / 2,
                width: configuredSymbolImage.size.width,
                height: configuredSymbolImage.size.height
            )
            symbolColor.set()
            configuredSymbolImage.draw(in: symbolRect)
        }
        circleImage.unlockFocus()
        return circleImage
    }
    
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }
}

