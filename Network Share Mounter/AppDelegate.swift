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

@main
class AppDelegate: NSObject, NSApplicationDelegate {

    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    var window = NSWindow()
    var mountpath = ""
    var mounter: Mounter?
    var prefs = PreferenceManager()
    var enableKerberos = false
    var authDone = false
    var automaticSignIn = AutomaticSignIn.shared
    let monitor = Monitor.shared
    var mountTimer = Timer()
    var authTimer = Timer()
    var unmountSignalSource: DispatchSourceSignal?
    var mountSignalSource: DispatchSourceSignal?
    var updaterController: SPUStandardUpdaterController?
    var activityController: ActivityController?

    override init() {
        super.init()
        if prefs.bool(for: .enableAutoUpdater) == true {
            let sparkleDefaults = UserDefaults.standard
            let enableChecks = prefs.bool(for: .SUEnableAutomaticChecks)
            sparkleDefaults.set(enableChecks, forKey: "SUEnableAutomaticChecks")
            let autoUpdate = prefs.bool(for: .SUAutomaticallyUpdate)
            sparkleDefaults.set(autoUpdate, forKey: "SUAutomaticallyUpdate")
            
            updaterController = SPUStandardUpdaterController(
                startingUpdater: enableChecks,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            
            Logger.app.debug("Sparkle initialized with: checks=\(enableChecks), auto-update=\(autoUpdate)")
        } else {
            UserDefaults.standard.set(false, forKey: "SUEnableAutomaticChecks")
            Logger.app.debug("Auto-updater disabled via preferences")
        }
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
#if DEBUG
        Logger.appStatistics.debug("🐛 Debugging app, not reporting anything to sentry server ...")
#else
        if prefs.bool(for: .sendDiagnostics) == true {
            Logger.app.debug("Initializing sentry SDK...")
            SentrySDK.start { options in
                options.dsn = Defaults.sentryDSN
                options.debug = true
                options.tracesSampleRate = 1.0
            }
            SentrySDK.startProfiler()
            // Some code that you profile
            SentrySDK.stopProfiler()
        }
#endif

        synchronizeSparkleSettings()
        window.isReleasedWhenClosed = false
        mounter = Mounter()

        LaunchAtLogin.isEnabled = prefs.bool(for: .autostart)
        if let button = statusItem.button {
            button.image = NSImage(named: NSImage.Name("networkShareMounter"))
        }
        window.contentViewController = NetworkShareMounterViewController.newInstance()

        Task {
            await initializeApp()
        }
        
        setupSignalHandlers()
        activityController = ActivityController(appDelegate: self)
    }

    private func synchronizeSparkleSettings() {
        let sparkleDefaults = UserDefaults.standard
        let autoUpdaterEnabled = prefs.bool(for: .enableAutoUpdater)

        if !autoUpdaterEnabled {
            sparkleDefaults.set(false, forKey: "SUEnableAutomaticChecks")
            sparkleDefaults.set(false, forKey: "SUAutomaticallyUpdate")
            sparkleDefaults.set(true, forKey: "SUHasLaunchedBefore")
            Logger.app.info("Auto-updater disabled: Setting all Sparkle settings to false")
            return
        }
        let enableChecks = prefs.bool(for: .SUEnableAutomaticChecks)
        let autoUpdate = prefs.bool(for: .SUAutomaticallyUpdate)
        let hasLaunchedBefore = prefs.bool(for: .SUHasLaunchedBefore)

        sparkleDefaults.set(enableChecks, forKey: "SUEnableAutomaticChecks")
        sparkleDefaults.set(autoUpdate, forKey: "SUAutomaticallyUpdate")
        sparkleDefaults.set(hasLaunchedBefore, forKey: "SUHasLaunchedBefore")

        Logger.app.info("Sparkle settings synchronized: enableAutoUpdater=\(autoUpdaterEnabled), enableChecks=\(enableChecks), autoUpdate=\(autoUpdate), hasLaunchedBefore=\(hasLaunchedBefore)")
    }

    private func initializeApp() async {
        Task {
            await mounter?.asyncInit()
            await self.constructMenu(withMounter: self.mounter)
            
            if let krbRealm = self.prefs.string(for: .kerberosRealm), !krbRealm.isEmpty {
                Logger.app.info("Enabling Kerberos Realm \(krbRealm, privacy: .public).")
                self.enableKerberos = true
            } else {
                Logger.app.info("No Kerberos Realm found.")
            }

            let stats = AppStatistics.init()
            await stats.reportAppInstallation()
            await AccountsManager.shared.initialize()

            if mounter != nil {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(handleErrorNotification(_:)),
                    name: .nsmNotification,
                    object: nil
                )
            } else {
                Logger.app.error("Could not initialize mounter class, this should never happen.")
            }

            Logger.app.debug("Trigger user authentication on app startup.")
            NotificationCenter.default.post(name: Defaults.nsmAuthTriggerNotification, object: nil)

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.mountTimer = Timer.scheduledTimer(withTimeInterval: Defaults.mountTriggerTimer, repeats: true) { _ in
                    Logger.app.debug("Passed \(Defaults.mountTriggerTimer, privacy: .public) seconds, performing operations:")
                    NotificationCenter.default.post(name: Defaults.nsmTimeTriggerNotification, object: nil)
                }
                self.authTimer = Timer.scheduledTimer(withTimeInterval: Defaults.authTriggerTimer, repeats: true) { _ in
                    Logger.app.debug("Passed \(Defaults.authTriggerTimer, privacy: .public) seconds, performing operations:")
                    NotificationCenter.default.post(name: Defaults.nsmAuthTriggerNotification, object: nil)
                }
                Logger.app.info("Timer wurden auf dem Hauptthread initialisiert - Mount: \(self.mountTimer.isValid), Auth: \(self.authTimer.isValid)")
            }

            monitor.startMonitoring { connection, reachable in
                if reachable.rawValue == "yes" {
                    Logger.app.debug("Network is reachable, firing nsmNetworkChangeTriggerNotification and nsmAuthTriggerNotification.")
                    NotificationCenter.default.post(name: Defaults.nsmNetworkChangeTriggerNotification, object: nil)
                    NotificationCenter.default.post(name: Defaults.nsmAuthTriggerNotification, object: nil)
                } else {
                    Task {
                        NotificationCenter.default.post(name: Defaults.nsmAuthTriggerNotification, object: nil)
                        Logger.app.debug("Got network monitoring callback, unmount shares.")
                        if let mounter = self.mounter {
                            await mounter.setAllMountStatus(to: MountStatus.undefined)
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
        monitor.monitor.cancel()
        if prefs.bool(for: .unmountOnExit) == true {
            Logger.app.debug("Exiting app, unmounting shares...")
            unmountShares(self)
            sleep(3)
        }
    }

    @objc func handleErrorNotification(_ notification: NSNotification) {
        if notification.userInfo?["KrbAuthError"] is Error {
            DispatchQueue.main.async {
                if let button = self.statusItem.button, self.enableKerberos {
                    button.image = NSImage(named: NSImage.Name("networkShareMounterMenuRed"))
                    Task { @MainActor in
                        await self.constructMenu(withMounter: self.mounter, andStatus: .krbAuthenticationError)
                    }
                }
            }
        } else if notification.userInfo?["AuthError"] is Error {
            DispatchQueue.main.async {
                if let button = self.statusItem.button {
                    button.image = NSImage(named: NSImage.Name("networkShareMounterMenuYellow"))
                    Task { @MainActor in
                        await self.constructMenu(withMounter: self.mounter, andStatus: .authenticationError)
                    }
                }
            }
        } else if notification.userInfo?["ClearError"] is Error {
            DispatchQueue.main.async {
                if let button = self.statusItem.button {
                    button.image = NSImage(named: NSImage.Name("networkShareMounter"))
                    Task { @MainActor in
                        await self.constructMenu(withMounter: self.mounter)
                    }
                }
            }
        } else if notification.userInfo?["krbAuthenticated"] is Error {
            DispatchQueue.main.async {
                if let button = self.statusItem.button, self.enableKerberos {
                    button.image = NSImage(named: NSImage.Name("networkShareMounterMenuGreen"))
                }
            }
        } else if notification.userInfo?["FailError"] is Error {
            DispatchQueue.main.async {
                if let button = self.statusItem.button {
                    button.image = NSImage(named: NSImage.Name("networkShareMounterMenuFail"))
                }
            }
        } else if notification.userInfo?["krbOffDomain"] is Error {
            DispatchQueue.main.async {
                if let button = self.statusItem.button, self.enableKerberos {
                    button.image = NSImage(named: NSImage.Name("networkShareMounter"))
                }
            }
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
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

    @objc func openHelpURL(_ sender: Any?) {
        guard let url = prefs.string(for: .helpURL), let openURL = URL(string: url) else {
            return
        }
        NSWorkspace.shared.open(openURL)
    }

    @objc func showWindow(_ sender: Any?) {
        window.title = NSLocalizedString("Preferences", comment: "Preferences")
        window.styleMask.insert([.closable])
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        window.makeKey()
    }

    func setupSignalHandlers() {
        let unmountSignal = SIGUSR1
        let mountSignal = SIGUSR2

        signal(unmountSignal, SIG_IGN)
        signal(mountSignal, SIG_IGN)

        unmountSignalSource = DispatchSource.makeSignalSource(signal: unmountSignal, queue: .main)
        mountSignalSource = DispatchSource.makeSignalSource(signal: mountSignal, queue: .main)

        unmountSignalSource?.setEventHandler { [self] in
            Logger.app.debug("🚦Received unmount signal.")
            Task {
                await self.mounter?.unmountAllMountedShares(userTriggered: false)
            }
        }

        mountSignalSource?.setEventHandler { [self] in
            Logger.app.debug("🚦Received mount signal.")
            Task {
                await self.mounter?.mountGivenShares(userTriggered: true)
            }
        }

        unmountSignalSource?.resume()
        mountSignalSource?.resume()
    }

    @MainActor
    func constructMenu(withMounter mounter: Mounter?, andStatus: MounterError? = nil) async {
        let menu = NSMenu()
        menu.autoenablesItems = false
        
        if let mounter = mounter {
            switch andStatus {
            case .krbAuthenticationError:
                Logger.app.debug("🏗️ Constructing Kerberos authentication problem menu.")
                mounter.errorStatus = .authenticationError
                menu.addItem(NSMenuItem(
                    title: NSLocalizedString("⚠️ Kerberos SSO Authentication problem...", comment: "Kerberos Authentication problem"),
                    action: #selector(AppDelegate.showWindow(_:)),
                    keyEquivalent: ""
                ))
                menu.addItem(NSMenuItem.separator())
            case .authenticationError:
                Logger.app.debug("🏗️ Constructing authentication problem menu.")
                mounter.errorStatus = .authenticationError
                menu.addItem(NSMenuItem(
                    title: NSLocalizedString("⚠️ Authentication problem...", comment: "Authentication problem"),
                    action: #selector(AppDelegate.showWindow(_:)),
                    keyEquivalent: ""
                ))
                menu.addItem(NSMenuItem.separator())
            default:
                mounter.errorStatus = .noError
                Logger.app.debug("🏗️ Constructing default menu.")
            }
        } else {
            Logger.app.debug("🏗️ Constructing basic menu without mounter.")
        }

        if let urlString = prefs.string(for: .helpURL), URL(string: urlString) != nil {
            if let newMenuItem = createMenuItem(
                title: "About Network Share Mounter",
                comment: "About Network Share Mounter",
                action: #selector(AppDelegate.openHelpURL(_:)),
                keyEquivalent: "",
                preferenceKey: .menuAbout,
                prefs: prefs
            ) {
                menu.addItem(newMenuItem)
            }
        }

        if mounter != nil {
            if let newMenuItem = createMenuItem(
                title: "Mount shares",
                comment: "Mount share",
                action: #selector(AppDelegate.mountManually(_:)),
                keyEquivalent: "m",
                preferenceKey: .menuConnectShares,
                prefs: prefs
            ) {
                menu.addItem(newMenuItem)
            }
            if let newMenuItem = createMenuItem(
                title: "Unmount shares",
                comment: "Unmount shares",
                action: #selector(AppDelegate.unmountShares(_:)),
                keyEquivalent: "u",
                preferenceKey: .menuDisconnectShares,
                prefs: prefs
            ) {
                menu.addItem(newMenuItem)
            }
            if let newMenuItem = createMenuItem(
                title: "Show mounted shares",
                comment: "Show mounted shares",
                action: #selector(AppDelegate.openDirectory(_:)),
                keyEquivalent: "f",
                preferenceKey: .menuShowSharesMountDir,
                prefs: prefs
            ) {
                newMenuItem.representedObject = mounter?.defaultMountPath
                menu.addItem(newMenuItem)
            }
        }

        if prefs.bool(for: .enableAutoUpdater) == true && updaterController != nil {
            if let newMenuItem = createMenuItem(
                title: "Check for Updates...",
                comment: "Check for Updates",
                action: #selector(SPUStandardUpdaterController.checkForUpdates(_:)),
                keyEquivalent: "",
                preferenceKey: .menuCheckUpdates,
                prefs: prefs
            ) {
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
                        Logger.app.debug("  🍰 Adding mountpoint \(mountDir, privacy: .public) for \(share.networkShare, privacy: .public) to menu.")
                        
                        let menuIcon = createMenuIcon(withIcon: "externaldrive.connected.to.line.below.fill", backgroundColor: .systemBlue, symbolColor: .white)
                        menuItem = NSMenuItem(
                            title: NSLocalizedString(mountDir, comment: ""),
                            action: #selector(AppDelegate.openDirectory(_:)),
                            keyEquivalent: ""
                        )
                        menuItem.representedObject = mountpoint
                        menuItem.image = menuIcon
                    } else {
                        Logger.app.debug("  🍰 Adding remote share \(share.networkShare, privacy: .public).")
                        let menuIcon = createMenuIcon(withIcon: "externaldrive.connected.to.line.below", backgroundColor: .systemGray, symbolColor: .white)
                        menuItem = NSMenuItem(
                            title: NSLocalizedString(share.networkShare, comment: ""),
                            action: #selector(AppDelegate.mountSpecificShare(_:)),
                            keyEquivalent: ""
                        )
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

        if let newMenuItem = createMenuItem(
            title: "Preferences ...",
            comment: "Preferences",
            action: #selector(AppDelegate.showWindow(_:)),
            keyEquivalent: ",",
            preferenceKey: .menuSettings,
            prefs: prefs
        ) {
            menu.addItem(NSMenuItem.separator())
            menu.addItem(newMenuItem)
        }

        if prefs.bool(for: .canQuit) != false {
            if let newMenuItem = createMenuItem(
                title: "Quit Network Share Mounter",
                comment: "Quit Network Share Mounter",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q",
                preferenceKey: .menuQuit,
                prefs: prefs
            ) {
                menu.addItem(NSMenuItem.separator())
                menu.addItem(newMenuItem)
            }
        }

        statusItem.menu = menu
    }

    func createMenuItem(
        title: String,
        comment: String,
        action: Selector,
        keyEquivalent: String,
        preferenceKey: PreferenceKeys,
        prefs: PreferenceManager
    ) -> NSMenuItem? {
        let preferenceValue = prefs.string(for: preferenceKey) ?? ""
        // Ruf nur einmal NSLocalizedString auf.
        // (Die zweite Lokalisation von localizedTitle entfällt.)
        let localizedTitle = NSLocalizedString(title, comment: comment)
        
        let menuItem = NSMenuItem(
            title: localizedTitle,
            action: action,
            keyEquivalent: keyEquivalent
        )

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
        // Falls du mehrere Icons baust, könnte man hier ebenfalls Caching einbauen
        guard let symbolImage = NSImage(systemSymbolName: withIcon, accessibilityDescription: nil) else {
            return NSImage()
        }

        let templateImage = (symbolImage.copy() as? NSImage) ?? NSImage()
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
}

