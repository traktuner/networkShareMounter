//
//  AppDelegate.swift
//  Network Share Mounter
//
//  Created by Gregor Longariva on 24.11.21.
//  Copyright © 2024 Regionales Rechenzentrum Erlangen. All rights reserved.
//

@preconcurrency import Cocoa
import SwiftUI
import Network
import ServiceManagement
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
    /// NOTE: Instance is created by Network_Share_MounterApp and injected here.
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

    /// Timestamp when the app started, used for uptime calculations
    var appStartTime: Date?

    /// Days remaining until the AD password expires; nil when no warning is active.
    /// Set from the main thread only (inside Task { @MainActor in }).
    var passwordExpirationDaysRemaining: Int?

    /// The UPN of the user whose password expiration was detected.
    var passwordExpirationUserPrincipal: String = ""

    /// Retains the password expiration / change password dialog window to prevent early deallocation.
    var passwordExpirationWindow: NSWindow?

    /// Retains the credential onboarding window to prevent early deallocation.
    var credentialOnboardingWindow: NSWindow?

    /// Pending credential onboarding info; non-nil while snooze is active (drives menu reminder item).
    var pendingCredentialOnboarding: CredentialOnboardingInfo?

    /// The UPN of the currently authenticated Kerberos user; set on every successful auth regardless of expiry state.
    var kerberosUserPrincipal: String = ""

    /// Set to true after the user chose "Open System Settings" in the Full Disk Access prompt.
    /// Cleared when `applicationDidBecomeActive` fires so the app can retry mounts after FDA is granted.
    var waitingForFullDiskAccess: Bool = false

    /// The pending background update found by Sparkle; nil when no update is waiting.
    /// Used for gentle reminders: instead of stealing focus, a menu item is shown.
    var pendingUpdateItem: SUAppcastItem?
    
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
                userDriverDelegate: self)
            
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

        // Configure Sentry based on user preferences
        SentryManager.shared.configureSentry()
        appStartTime = Date()
        logAppVersion(context: "🚀 App starting")

#if DEBUG
        Logger.appStatistics.debug("🐛 Debugging app, not reporting anything to sentry server ...")
#endif
  
        
        // Synchronize Sparkle settings with current preferences
        synchronizeSparkleSettings()
        
        // Set up the status item in the menu bar
        if let button = statusItem.button {
            let imageName = MenuImageName.normal.imageName
            if let image = NSImage(named: NSImage.Name(imageName)) {
                button.image = image
            } else {
                Logger.app.error("❌ Status bar icon image not found: \(imageName, privacy: .public) — falling back to system symbol")
                button.image = NSImage(systemSymbolName: "externaldrive.connected.to.line.below", accessibilityDescription: "Network Share Mounter")
            }
        }

        // Set up signal handlers for the app
        setupSignalHandlers()

        activityController = ActivityController(appDelegate: self)
        
        // Create mounter instance immediately (not waiting for SwiftUI)
        mounter = Mounter()
        
        // Restore accessory activation policy (no Dock icon) when all regular windows close
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleWindowWillClose(_:)),
            name: NSWindow.willCloseNotification,
            object: nil
        )

        // Start asynchronous initialization
        Task { @MainActor in
            await initializeApp()
            await performPostInitializationTasks()
        }
    }

    /// Re-checks Full Disk Access when the user returns to the app (e.g. from System Settings).
    /// Triggers a mount retry when FDA was just granted so shares connect without a manual action.
    func applicationDidBecomeActive(_ notification: Notification) {
        guard waitingForFullDiskAccess else { return }
        waitingForFullDiskAccess = false
        if FullDiskAccessChecker.hasAccess() {
            Logger.app.info("✅ Full Disk Access granted — triggering mount retry")
            NotificationCenter.default.post(name: Defaults.nsmNetworkChangeTriggerNotification, object: nil)
        }
    }

    /// Handles autostart configuration after app initialization.
    @MainActor
    private func performPostInitializationTasks() async {
        // Handle autostart configuration (MDM or first-time setup)
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }

            let defaults = UserDefaults.standard
            let service = SMAppService.mainApp
            let hasCompletedSetup = defaults.bool(forKey: PreferenceKeys.hasCompletedInitialAutostartSetup.rawValue)

            // Check if MDM has set an autostart preference.
            // MDM is considered active if either 'autostart' or 'canChangeAutostart' is forced,
            // since locking 'canChangeAutostart' implies MDM intends to control the autostart state.
            let hasMDMAutostart = defaults.objectIsForced(forKey: PreferenceKeys.autostart.rawValue)
                || defaults.objectIsForced(forKey: PreferenceKeys.canChangeAutostart.rawValue)

            if hasMDMAutostart {
                let mdmAutostart = self.prefs.bool(for: .autostart)
                let canChangeAutostart = self.prefs.bool(for: .canChangeAutostart)
                let currentStatus = service.status

                if !canChangeAutostart {
                    // Scenario 1: MDM enforces autostart on EVERY launch (not changeable by user)
                    Logger.app.info("🔧 MDM autostart enforced (canChangeAutostart=false): \(mdmAutostart), current system: \(String(describing: currentStatus), privacy: .public)")

                    let needsSync = (mdmAutostart && currentStatus != .enabled) || (!mdmAutostart && currentStatus == .enabled)

                    if needsSync {
                        do {
                            if mdmAutostart {
                                try service.register()
                                Logger.app.info("✅ Enforced MDM autostart: enabled")
                            } else {
                                try await service.unregister()
                                Logger.app.info("✅ Enforced MDM autostart: disabled")
                            }
                        } catch {
                            Logger.app.error("❌ Failed to enforce MDM autostart: \(error.localizedDescription, privacy: .public)")
                        }
                    }
                } else {
                    // Scenario 2: MDM provides initial value but user can change (canChangeAutostart=true)
                    if !hasCompletedSetup {
                        Logger.app.info("🎉 First launch with MDM default (canChangeAutostart=true): \(mdmAutostart)")

                        do {
                            if mdmAutostart {
                                try service.register()
                                Logger.app.info("✅ Applied MDM initial autostart: enabled")
                            } else {
                                try await service.unregister()
                                Logger.app.info("✅ Applied MDM initial autostart: disabled")
                            }
                        } catch {
                            Logger.app.error("❌ Failed to apply MDM initial autostart: \(error.localizedDescription, privacy: .public)")
                        }

                        // Mark setup as completed - from now on user controls it
                        defaults.set(true, forKey: PreferenceKeys.hasCompletedInitialAutostartSetup.rawValue)
                    } else {
                        // Setup already done - user has control, ignore MDM value
                        Logger.app.debug("Setup completed - user controls autostart (MDM value ignored)")
                    }
                }
            } else {
                // Scenario 3: No MDM - enable autostart on first launch
                if !hasCompletedSetup {
                    Logger.app.info("🎉 First launch without MDM - enabling autostart by default")

                    do {
                        try service.register()
                        Logger.app.info("✅ Autostart enabled on first launch")
                    } catch {
                        Logger.app.error("❌ Failed to enable autostart on first launch: \(error.localizedDescription, privacy: .public)")
                    }

                    // Mark setup as completed
                    defaults.set(true, forKey: PreferenceKeys.hasCompletedInitialAutostartSetup.rawValue)
                } else {
                    // Setup already done - respect user's choice
                    Logger.app.debug("Autostart setup completed - respecting user's system state")
                }
            }
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
    
    @MainActor
    private func initializeApp() async {
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

            // Perform share-linking migration (v3.0 → v4.0) - runs independently of AuthProfile migration
            let shareMigrationKey = "ShareLinkingMigrationCompleted_v4.0"
            if !UserDefaults.standard.bool(forKey: shareMigrationKey) {
                Logger.app.info("🔗 Starting share linking migration...")
                await AuthProfileManager.shared.updateExistingSharesWithProfiles()
                UserDefaults.standard.set(true, forKey: shareMigrationKey)
                Logger.app.info("✅ Share linking migration completed successfully")
            } else {
                Logger.app.debug("Share linking migration already completed, skipping")
            }

            // Initialize the mounter AFTER migration
            if let mounter = self.mounter {
                await mounter.asyncInit()
                Logger.app.debug("✅ Mounter successfully initialized")
            } else {
                Logger.app.error("❌ Mounter is not available for initialization - SwiftUI injection failed")
                return
            }

            // Check Full Disk Access on macOS 26+ when mount path is outside /Volumes.
            // promptIfNeeded is a no-op on macOS < 26 or when path is already under /Volumes.
            if let mounter = self.mounter {
                FullDiskAccessChecker.promptIfNeeded(
                    forMountPath: mounter.defaultMountPath,
                    onOpenSettings: {
                        self.waitingForFullDiskAccess = true
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                )
            }

            // NEW: Rescan existing mounts at app start, independent of network state
            if let mounter = self.mounter {
                Logger.app.debug("🔍 Performing initial rescan of existing mounts")
                await mounter.rescanExistingMounts()
            }
            
            await self.constructMenu(withMounter: self.mounter)
            Logger.app.debug("✅ Initial menu constructed")

            // Check for shares without assigned profiles after initialization
            if let mounter = self.mounter {
                await mounter.shareManager.checkForUnassignedProfiles()
            }

            // Proactively prompt for credentials if needed (Kerberos realm or MDM password shares without profiles)
            await checkCredentialOnboarding()

            // Check if Mac is bound to Active Directory
            if await isActiveDirectoryBound() {
                Logger.app.info("🎯 Mac is bound to Active Directory - using system Kerberos")

                // Inform the mounter about AD binding status
                if let mounter = self.mounter {
                    mounter.isActiveDirectoryBound = true
                }

                // Check for system Kerberos tickets (for icon feedback only)
                let klist = KlistUtil()
                let tickets = await klist.klist()

                if !tickets.isEmpty {
                    Logger.app.info("✅ System Kerberos tickets available - AD authentication ready")
                    await MainActor.run {
                        if let button = self.statusItem.button {
                            button.image = NSImage(named: NSImage.Name("networkShareMounterAD"))
                        }
                    }
                } else {
                    Logger.app.info("ℹ️ No system Kerberos tickets found (off-domain?) - using neutral icon")
                    // Icon bleibt normal (wurde bereits bei app launch gesetzt)
                }

                // No app-managed Kerberos authentication needed
                self.enableKerberos = false

            } else if let krbRealm = self.prefs.string(for: .kerberosRealm), !krbRealm.isEmpty {
                // Not AD-bound but Kerberos realm configured: use app-managed authentication
                Logger.app.info("Enabling app-managed Kerberos for Realm \(krbRealm, privacy: .public).")
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
                Logger.app.info("No Kerberos configuration found.")
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
                    // Auto-open settings window with profile creation dialog using the new SwiftUI system
                    NotificationCenter.default.post(
                        name: .showSettingsScene,
                        object: nil,
                        userInfo: [
                            "autoOpenProfileCreation": true,
                            "mdmRealm": mdmRealm
                        ]
                    )
                }
            }
            
            if mounter != nil {
                NotificationCenter.default.addObserver(self, selector: #selector(handleErrorNotification(_:)), name: .nsmNotification, object: nil)
                Logger.app.debug("✅ Error notification observer registered")
            } else {
                Logger.app.error("Could not initialize mounter class, this should never happen.")
            }

            UserDefaults.standard.removeObject(forKey: "lastKrbAuthAttempt")

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

            if self.enableKerberos {
                Logger.app.debug("App-managed Kerberos enabled - waiting for authentication before initial mount")
                await self.performInitialMountWithKerberosAuth()
            } else {
                Logger.app.debug("No app-managed Kerberos authentication required (AD-bound or no Kerberos) - performing initial mount")
                NotificationCenter.default.post(name: Defaults.nsmTimeTriggerNotification, object: nil)
            }

            Logger.app.debug("🎉 App initialization completed successfully")
    }

    @MainActor
    private func performInitialMountWithKerberosAuth() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let observerBox = ObserverBox()
            var hasResumed = false

            observerBox.value = NotificationCenter.default.addObserver(
                forName: .nsmNotification,
                object: nil,
                queue: .main
            ) { notification in
                guard !hasResumed else { return }

                if notification.userInfo?["krbAuthenticated"] is Error {
                    Logger.app.debug("✅ Kerberos authentication successful - triggering initial mount")
                    hasResumed = true

                    if let observer = observerBox.value {
                        NotificationCenter.default.removeObserver(observer)
                    }

                    NotificationCenter.default.post(name: Defaults.nsmTimeTriggerNotification, object: nil)
                    continuation.resume()
                }
            }

            Logger.app.debug("Trigger user authentication on app startup.")
            NotificationCenter.default.post(name: Defaults.nsmAuthTriggerNotification, object: nil)

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 30_000_000_000)

                guard !hasResumed else { return }
                hasResumed = true

                if let observer = observerBox.value {
                    NotificationCenter.default.removeObserver(observer)
                }

                Logger.app.warning("⚠️ Kerberos authentication timeout - proceeding with mount anyway")
                NotificationCenter.default.post(name: Defaults.nsmTimeTriggerNotification, object: nil)
                continuation.resume()
            }
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
            
            // Cache Kerberos error status for App Intents
            let kerbStatus: [String: Any] = [
                "hasValidTicket": false,
                "lastUpdated": Date().timeIntervalSince1970
            ]
            UserDefaults.standard.set(kerbStatus, forKey: "kerberosTicketStatus")
            
            Task { @MainActor in
                let hasMountedShares = await mounter?.shareManager.allShares.contains { $0.mountStatus == .mounted } ?? false
                if hasMountedShares {
                    Logger.app.debug("🔔 [DEBUG] Shares are mounted - ignoring Kerberos error to prevent status override")
                    return
                }
                Logger.app.debug("🔔 [DEBUG] No mounted shares - proceeding with Kerberos error handling")
                if let button = self.statusItem.button, self.enableKerberos {
                    button.image = NSImage(named: NSImage.Name(MenuImageName.red.imageName))
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
                    button.image = NSImage(named: NSImage.Name(MenuImageName.yellow.imageName))
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
            
            // Cache Kerberos status for App Intents
            let kerbStatus: [String: Any] = [
                "hasValidTicket": true,
                "lastUpdated": Date().timeIntervalSince1970
            ]
            UserDefaults.standard.set(kerbStatus, forKey: "kerberosTicketStatus")
            
            Task { @MainActor in
                if let button = self.statusItem.button, self.enableKerberos {
                    button.image = NSImage(named: NSImage.Name(MenuImageName.green.imageName))
                    self.mounter?.setErrorStatus(.noError)
                    await self.constructMenu(withMounter: self.mounter)
                }
            }
        }
        else if notification.userInfo?["FailError"] is Error {
            Task { @MainActor in
                if let button = self.statusItem.button {
                    button.image = NSImage(named: NSImage.Name(MenuImageName.yellow.imageName))
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
                    button.image = NSImage(named: NSImage.Name(MenuImageName.normal.imageName))
                    self.mounter?.setErrorStatus(.offDomain)
                    await self.constructMenu(withMounter: self.mounter)
                }
            }
        }
        else if notification.userInfo?["UnassignedProfiles"] is Error {
            Logger.app.debug("🔔 [DEBUG] Processing UnassignedProfiles path")
            Task { @MainActor in
                if let button = self.statusItem.button {
                    button.image = NSImage(named: NSImage.Name(MenuImageName.yellow.imageName))
                    self.mounter?.setErrorStatus(.unassignedProfile)
                    await self.constructMenu(withMounter: self.mounter, andStatus: .unassignedProfile)
                }
            }
        }
        else if notification.userInfo?["AllProfilesAssigned"] != nil {
            Task { @MainActor in
                self.mounter?.setErrorStatus(.noError)
                if let button = self.statusItem.button {
                    button.image = NSImage(named: NSImage.Name(MenuImageName.normal.imageName))
                }
                await self.constructMenu(withMounter: self.mounter)
            }
        }
        else if let days = notification.userInfo?["passwordExpirationWarning"] as? Int {
            let userPrincipal = notification.userInfo?["passwordExpirationUser"] as? String ?? ""
            Logger.app.debug("🔔 Processing passwordExpirationWarning: \(days) days for \(userPrincipal, privacy: .public)")
            Task { @MainActor in
                self.passwordExpirationDaysRemaining = days
                self.passwordExpirationUserPrincipal = userPrincipal
                if days <= 0, let button = self.statusItem.button {
                    button.image = NSImage(named: NSImage.Name(MenuImageName.yellow.imageName))
                }
                await self.constructMenu(withMounter: self.mounter)
            }
        }
        else if notification.userInfo?["showPasswordExpirationDialog"] != nil {
            Task { @MainActor in
                self.showPasswordExpirationWindow()
            }
        }
        else if notification.userInfo?["clearPasswordExpiration"] != nil {
            Task { @MainActor in
                guard self.passwordExpirationDaysRemaining != nil else { return }
                self.passwordExpirationDaysRemaining = nil
                self.passwordExpirationUserPrincipal = ""
                await self.constructMenu(withMounter: self.mounter)
            }
        }
        else if let upn = notification.userInfo?["kerberosUserAuthenticated"] as? String {
            Task { @MainActor in
                let wasEmpty = self.kerberosUserPrincipal.isEmpty
                self.kerberosUserPrincipal = upn
                if wasEmpty, self.prefs.bool(for: .allowPasswordChange) {
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
    
    /// Shows the password expiration warning dialog.
    ///
    /// Presents a non-modal SwiftUI panel with expiration details.
    /// - If `passwordChangeURL` is set via MDM → "Change Password" opens that URL.
    /// - Otherwise → "Change Password" opens an in-app kpasswd sheet.
    @objc func showPasswordExpirationWindow(_ sender: Any? = nil) {
        if let existing = passwordExpirationWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let days = passwordExpirationDaysRemaining else { return }

        let changeURL: URL?
        if let urlString = prefs.string(for: .passwordChangeURL),
           !urlString.isEmpty,
           let url = URL(string: urlString) {
            changeURL = url
        } else {
            changeURL = nil
        }

        let userPrincipal = passwordExpirationUserPrincipal

        let onChangePassword: ((String, String) async throws -> Void)? = changeURL == nil ? { [weak self] old, new in
            try await AutomaticSignIn.shared.changePassword(for: userPrincipal, oldPass: old, newPass: new)
            await MainActor.run { [weak self] in
                self?.passwordExpirationDaysRemaining = nil
                self?.passwordExpirationUserPrincipal = ""
                self?.passwordExpirationWindow?.close()
            }
            Task { @MainActor [weak self] in
                guard let self else { return }
                await constructMenu(withMounter: mounter)
            }
        } : nil

        let view = PasswordExpirationView(
            daysRemaining: days,
            userPrincipal: userPrincipal,
            passwordChangeURL: changeURL,
            onChangePassword: onChangePassword,
            onDismiss: { [weak self] in
                self?.passwordExpirationWindow?.close()
            }
        )

        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.title = NSLocalizedString("Password Expiration Warning", comment: "Password expiration window title")
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        passwordExpirationWindow = window
    }

    /// Shows the proactive change-password dialog (no expiry context).
    ///
    /// Called when the user clicks "Change Password…" from the menu while the password is not yet
    /// close to expiry. If `passwordChangeURL` is configured, opens that URL in the default browser.
    /// Otherwise presents the in-app kpasswd sheet directly.
    @objc func showChangePasswordWindow(_ sender: Any? = nil) {
        if let urlString = prefs.string(for: .passwordChangeURL),
           !urlString.isEmpty,
           let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
            return
        }

        let userPrincipal = kerberosUserPrincipal
        guard !userPrincipal.isEmpty else { return }

        let view = ChangePasswordView(
            userPrincipal: userPrincipal,
            onChangePassword: { old, new in
                try await AutomaticSignIn.shared.changePassword(for: userPrincipal, oldPass: old, newPass: new)
            },
            onDismiss: { [weak self] in
                self?.passwordExpirationWindow?.close()
            }
        )

        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.title = NSLocalizedString("Change Password", comment: "Change password window title")
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        passwordExpirationWindow = window
    }

    // MARK: - Credential Onboarding

    /// Evaluates whether the user needs to be prompted for credentials and either shows
    /// the onboarding dialog or surfaces a gentle menu reminder when the snooze is active.
    @MainActor
    private func checkCredentialOnboarding() async {
        let realm = prefs.string(for: .kerberosRealm)
        let allShares = await mounter?.shareManager.allShares ?? []
        let isADBound = mounter?.isActiveDirectoryBound ?? false

        guard let info = AuthProfileManager.shared.credentialOnboardingInfo(
            realm: realm,
            allShares: allShares,
            isADBound: isADBound
        ) else {
            pendingCredentialOnboarding = nil
            return
        }

        pendingCredentialOnboarding = info

        // If still within the 7-day snooze window, show only the menu reminder
        let snoozedUntil = UserDefaults.standard.double(forKey: PreferenceKeys.credentialOnboardingSnoozedUntil.rawValue)
        if snoozedUntil > Date().timeIntervalSince1970 {
            await constructMenu(withMounter: mounter)
            return
        }

        showCredentialOnboardingWindow(info: info)
    }

    /// Presents the credential onboarding sheet. Retained in `credentialOnboardingWindow` to
    /// prevent early deallocation.
    @MainActor
    private func showCredentialOnboardingWindow(info: CredentialOnboardingInfo) {
        guard let mounter = mounter else { return }

        let view = CredentialOnboardingView(
            info: info,
            mounter: mounter,
            onComplete: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    credentialOnboardingWindow?.close()
                    credentialOnboardingWindow = nil
                    pendingCredentialOnboarding = nil
                    UserDefaults.standard.removeObject(forKey: PreferenceKeys.credentialOnboardingSnoozedUntil.rawValue)
                    await constructMenu(withMounter: self.mounter)
                    NotificationCenter.default.post(name: Defaults.nsmAuthTriggerNotification, object: nil)
                    NotificationCenter.default.post(name: Defaults.nsmTimeTriggerNotification, object: nil)
                    Logger.app.info("✅ Credential onboarding completed — triggering mount")
                }
            },
            onSnooze: { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let snoozedUntil = Date().addingTimeInterval(7 * 24 * 3600).timeIntervalSince1970
                    UserDefaults.standard.set(snoozedUntil, forKey: PreferenceKeys.credentialOnboardingSnoozedUntil.rawValue)
                    credentialOnboardingWindow?.close()
                    credentialOnboardingWindow = nil
                    await constructMenu(withMounter: self.mounter)
                    Logger.app.info("🔔 Credential onboarding snoozed for 7 days")
                }
            }
        )

        let controller = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled, .closable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.title = NSLocalizedString("Network Credentials", comment: "Credential onboarding window title")
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        credentialOnboardingWindow = window
    }

    /// Called when the user clicks the "Network credentials required…" menu reminder.
    /// Clears the snooze and re-triggers the onboarding check so the dialog appears immediately.
    @objc func showCredentialOnboarding(_ sender: Any) {
        Task { @MainActor in
            UserDefaults.standard.removeObject(forKey: PreferenceKeys.credentialOnboardingSnoozedUntil.rawValue)
            await checkCredentialOnboarding()
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
        Logger.app.debug("🔧 [DEBUG] showSettingsWindowSwiftUI called")

        // Activate the app to bring it to foreground (necessary for menu bar apps)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Use the new SwiftUI app notification system
        NotificationCenter.default.post(name: .showSettingsScene, object: nil)
        Logger.app.debug("🔧 [DEBUG] Posted showSettingsScene notification")
    }
    
    /// Restores the app's accessory activation policy (hiding Dock icon) when all
    /// regular-sized windows close. The hidden SwiftUI placeholder window (10×10 pt)
    /// is excluded from the check via its minimal frame width.
    @objc private func handleWindowWillClose(_ notification: Notification) {
        guard NSApp.activationPolicy() == .regular,
              let closingWindow = notification.object as? NSWindow else { return }
        let hasOtherVisibleWindows = NSApp.windows.contains { window in
            window !== closingWindow && window.isVisible && window.frame.width > 100
        }
        if !hasOtherVisibleWindows {
            NSApp.setActivationPolicy(.accessory)
        }
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

        // Check MDM policy for settings menu access
        let menuSettingsValue = prefs.string(for: .menuSettings) ?? ""
        let canShowSettings = menuSettingsValue != "hidden"

        // Password change / expiration slot – one slot, two states
        if let days = passwordExpirationDaysRemaining {
            let expirationTitle: String
            if days <= 0 {
                expirationTitle = String(localized: String.LocalizationValue("🔴 Password has expired..."), comment: "Password expired menu item")
            } else if days == 1 {
                expirationTitle = String(localized: String.LocalizationValue("⚠️ Password expires tomorrow..."), comment: "Password expires tomorrow menu item")
            } else {
                expirationTitle = String(format: NSLocalizedString("⚠️ Password expires in %d days...", comment: "Password expiration countdown menu item"), days)
            }
            let expirationItem = NSMenuItem(
                title: expirationTitle,
                action: #selector(AppDelegate.showPasswordExpirationWindow(_:)),
                keyEquivalent: ""
            )
            expirationItem.isEnabled = true
            menu.addItem(expirationItem)
            menu.addItem(NSMenuItem.separator())
        } else if prefs.bool(for: .allowPasswordChange), !kerberosUserPrincipal.isEmpty {
            let changeItem = NSMenuItem(
                title: NSLocalizedString("Change Password\u{2026}", comment: "Proactive change password menu item"),
                action: #selector(AppDelegate.showChangePasswordWindow(_:)),
                keyEquivalent: ""
            )
            changeItem.isEnabled = true
            menu.addItem(changeItem)
            menu.addItem(NSMenuItem.separator())
        }

        // Gentle update reminder (Sparkle background update found, no focus stealing)
        if let pendingUpdate = pendingUpdateItem {
            let updateTitle = String(format: NSLocalizedString("🔔 Update available: Version %@", comment: "Gentle update reminder menu item"), pendingUpdate.displayVersionString)
            let updateItem = NSMenuItem(title: updateTitle, action: #selector(AppDelegate.showPendingUpdate(_:)), keyEquivalent: "")
            updateItem.isEnabled = true
            menu.addItem(updateItem)
            menu.addItem(NSMenuItem.separator())
        }

        // Credential onboarding reminder (user tapped "Not Now" but credentials are still missing)
        if pendingCredentialOnboarding != nil {
            let snoozedUntil = UserDefaults.standard.double(forKey: PreferenceKeys.credentialOnboardingSnoozedUntil.rawValue)
            if snoozedUntil > Date().timeIntervalSince1970 {
                let reminderItem = NSMenuItem(
                    title: NSLocalizedString("🔑 Network credentials required...", comment: "Credential onboarding menu reminder"),
                    action: #selector(AppDelegate.showCredentialOnboarding(_:)),
                    keyEquivalent: ""
                )
                reminderItem.isEnabled = true
                menu.addItem(reminderItem)
                menu.addItem(NSMenuItem.separator())
            }
        }

        if let mounter = mounter {
            switch statusToUse {
            case .krbAuthenticationError:
                Logger.app.debug("🏗️ Constructing Kerberos authentication problem menu.")
                let errorItem = NSMenuItem(title: String(localized: String.LocalizationValue("⚠️ Kerberos SSO Authentication problem..."), comment: "Kerberos Authentication problem"),
                                          action: canShowSettings ? #selector(AppDelegate.showSettingsWindowSwiftUI(_:)) : nil,
                                          keyEquivalent: "")
                errorItem.isEnabled = canShowSettings
                menu.addItem(errorItem)
                menu.addItem(NSMenuItem.separator())
            case .authenticationError:
                Logger.app.debug("🏗️ Constructing authentication problem menu.")
                let errorItem = NSMenuItem(title: String(localized: String.LocalizationValue("⚠️ Authentication problem..."), comment: "Authentication problem"),
                                          action: canShowSettings ? #selector(AppDelegate.showSettingsWindowSwiftUI(_:)) : nil,
                                          keyEquivalent: "")
                errorItem.isEnabled = canShowSettings
                menu.addItem(errorItem)
                menu.addItem(NSMenuItem.separator())
            case .unassignedProfile:
                Logger.app.debug("🏗️ Constructing unassigned profile menu.")
                let errorItem = NSMenuItem(title: String(localized: String.LocalizationValue("⚠️ Profile assignment required..."), comment: "Profile assignment required"),
                                          action: canShowSettings ? #selector(AppDelegate.showSettingsWindowSwiftUI(_:)) : nil,
                                          keyEquivalent: "")
                errorItem.isEnabled = canShowSettings
                menu.addItem(errorItem)
                menu.addItem(NSMenuItem.separator())

            default:
                mounter.setErrorStatus(.noError)
                Logger.app.debug("🏗️ Constructing default menu.")
            }
        } else {
            Logger.app.debug("🏗️ Constructing basic menu without mounter.")
        }
        
        if let urlString = prefs.string(for: .helpURL), URL(string: urlString) != nil {
            if let newMenuItem = createMenuItem(title: String(localized: String.LocalizationValue("About Network Share Mounter"), comment: "About Network Share Mounter"),
                                                  comment: "About Network Share Mounter",
                                                  action: #selector(AppDelegate.openHelpURL(_:)),
                                                  keyEquivalent: "",
                                                  preferenceKey: .menuAbout,
                                                  prefs: prefs) {
                menu.addItem(newMenuItem)
            }
        }
        
        if mounter != nil {
            if let newMenuItem = createMenuItem(title: String(localized: String.LocalizationValue("Mount shares"), comment: "Mount shares"),
                                                  comment: "Mount share",
                                                  action: #selector(AppDelegate.mountManually(_:)),
                                                  keyEquivalent: "m",
                                                  preferenceKey: .menuConnectShares,
                                                  prefs: prefs) {
                menu.addItem(newMenuItem)
            }
            if let newMenuItem = createMenuItem(title: String(localized: String.LocalizationValue("Unmount shares"), comment: "Unmount shares"),
                                                  comment: "Unmount shares",
                                                  action: #selector(AppDelegate.unmountShares(_:)),
                                                  keyEquivalent: "u",
                                                  preferenceKey: .menuDisconnectShares,
                                                  prefs: prefs) {
                menu.addItem(newMenuItem)
            }
            if let newMenuItem = createMenuItem(title: String(localized: String.LocalizationValue("Show mounted shares"), comment: "Show mounted shares"),
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
            if let newMenuItem = createMenuItem(title: String(localized: String.LocalizationValue("Check for Updates..."), comment: "Check for Updates"),
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
                        let mountDir = URL(fileURLWithPath: mountpoint).lastPathComponent
                        Logger.app.debug("  Menu: 🍰 Adding mountpoint \(mountDir, privacy: .public) for \(share.networkShare, privacy: .public) to menu.")

                        let menuIcon = createMenuIcon(withIcon: "externaldrive.connected.to.line.below.fill", backgroundColor: NSColor.systemBlue.withAlphaComponent(0.75), symbolColor: .white)
                        menuItem = NSMenuItem(title: mountDir,
                                              action: #selector(AppDelegate.openDirectory(_:)),
                                              keyEquivalent: "")
                        menuItem.representedObject = mountpoint
                        menuItem.image = menuIcon
                    } else {
                        Logger.app.debug("  Menu: 🍰 Adding remote share \(share.networkShare, privacy: .public).")
                        let iconName = share.autoMount
                            ? "externaldrive.connected.to.line.below.fill"
                            : "externaldrive.connected.to.line.below"
                        let menuIcon = createMenuIcon(withIcon: iconName, backgroundColor: NSColor.systemGray.withAlphaComponent(0.5), symbolColor: .white)
                        let menuItemTitle = share.effectiveMountPoint
                        menuItem = NSMenuItem(title: menuItemTitle,
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
        
        if let newMenuItem = createMenuItem(title: String(localized: String.LocalizationValue("Preferences ..."), comment: "Preferences"),
                                              comment: "Preferences",
                                              action: #selector(AppDelegate.showSettingsWindowSwiftUI(_:)),
                                              keyEquivalent: ",",
                                              preferenceKey: .menuSettings,
                                              prefs: prefs) {
            menu.addItem(NSMenuItem.separator())
            menu.addItem(newMenuItem)
        }
        
        if prefs.bool(for: .canQuit) != false {
            if let newMenuItem = createMenuItem(title: String(localized: String.LocalizationValue("Quit Network Share Mounter"), comment: "Quit Network Share Mounter"),
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

        // Ensure the status bar icon is always set after menu reconstruction.
        // macOS 26 Liquid Glass can lose the icon when the status item scene is rebuilt.
        if let button = statusItem.button, button.image == nil {
            let imageName = MenuImageName.normal.imageName
            if let image = NSImage(named: NSImage.Name(imageName)) {
                button.image = image
            }
        }
    }
    
    func createMenuItem(title: String, comment: StaticString, action: Selector, keyEquivalent: String, preferenceKey: PreferenceKeys, prefs: PreferenceManager) -> NSMenuItem? {
        let preferenceValue = prefs.string(for: preferenceKey) ?? ""
        let menuItem = NSMenuItem(title: String(localized: String.LocalizationValue(title), comment: comment),
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
    
    /// Logs the app version, build number, and uptime
    ///
    /// - Parameter context: Description of when this log is being generated
    func logAppVersion(context: String) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "UNKNOWN"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "UNKNOWN"
        let uptime = getUptime()
        Logger.app.info("📱 \(context, privacy: .public) - NSM v\(version, privacy: .public) (Build \(build, privacy: .public)) - Uptime: \(uptime, privacy: .public)")
    }

    /// Calculates the app uptime since launch
    ///
    /// - Returns: Formatted uptime string (e.g., "2h 34m" or "45m 12s")
    private func getUptime() -> String {
        guard let startTime = appStartTime else {
            return "unknown"
        }

        let uptimeSeconds = Date().timeIntervalSince(startTime)
        let hours = Int(uptimeSeconds) / 3600
        let minutes = (Int(uptimeSeconds) % 3600) / 60
        let seconds = Int(uptimeSeconds) % 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }

    func createMenuIcon(withIcon: String, backgroundColor: NSColor, symbolColor: NSColor) -> NSImage {
        let symbolImage = NSImage(systemSymbolName: withIcon, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "externaldrive.connected.to.line.below.fill", accessibilityDescription: nil)!
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

    @objc func showPendingUpdate(_ sender: Any) {
        updaterController?.checkForUpdates(sender)
    }
}

// MARK: - Sparkle Gentle Reminders

extension AppDelegate: SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        // Never steal focus for background update checks — the menu indicator handles it
        return false
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard !handleShowingUpdate else { return }
        // Background update found: store it and surface a gentle reminder in the menu
        Task { @MainActor in
            pendingUpdateItem = update
            await constructMenu(withMounter: mounter)
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        Task { @MainActor in
            pendingUpdateItem = nil
            await constructMenu(withMounter: mounter)
        }
    }

    func standardUserDriverWillFinishUpdateSession() {
        Task { @MainActor in
            pendingUpdateItem = nil
            await constructMenu(withMounter: mounter)
        }
    }
}

/// Reference-type box used to safely share an `NSObjectProtocol` observer token across
/// `@Sendable` closures without triggering "variable mutated after capture" warnings.
private final class ObserverBox: @unchecked Sendable {
    var value: (any NSObjectProtocol)?
}

