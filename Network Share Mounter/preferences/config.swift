//
//  config.swift
//  networkShareMounter
//
//  Created by Kett, Oliver on 20.03.17.
//  bugfixing and enhancements by FAUmac Team
//  Copyright © 2024 RRZE. All rights reserved.
//

import NetFS
import Foundation
import Cocoa
import OSLog

/// Default configuration values for the Network Share Mounter application
///
/// This structure defines constants and default values used throughout the application.
struct Defaults {
    
    // MARK: - Application Identification
    
    /// Bundle identifier for the application
    static let defaultsDomain = "de.fau.rrze.NetworkShareMounter"
    
    /// Unique identifier for Sentry error tracking
    static let sentryDSN = "https://a0768af20276c5f3b9bcd16a8d89e460@apps.faumac.de:8443/2"
    
    /// URL for sending anonymous statistics
    static let statisticsReportURL = "https://faumac.rrze.fau.de/apps"
    
    // MARK: - Keychain Settings
    
    /// Service name for keychain entries
    static let keyChainService = "Network Share Mounter account"
    
    /// Label for regular keychain entries
    static let keyChainLabel = "Network Share Mounter account"
    
    /// Label for Kerberos-related keychain entries
    static let keyChainLabelKerberos = "Network Share Mounter Kerberos account"
    
    /// Access group for shared keychain access
    static let keyChainAccessGroup = "C8F68RFW4L.de.fau.rrze.faucredentials"
    
    // MARK: - Localization
    
    /// Translations for the network shares folder name in different languages
    // FIXME: temporarely disable feature
//    static let translation = [
//        "en": "Networkshares",
//        "de": "Netzlaufwerke",
//        "es": "Recursos de red",
//        "fr": "Partages réseau",
//        "nl": "Netwerkschijven"
//    ]
    static let translation = [
        "en": "Networkshares",
        "de": "Netzlaufwerke",
        "es": "Networkshares",
        "fr": "Networkshares",
        "nl": "Networkshares"
    ]
    
    // MARK: - Timer Settings
    
    /// Time interval for triggering mount operations (5 minutes)
    static let mountTriggerTimer: Double = 5.0 * 60
    
    /// Time interval for triggering authentication operations (30 minutes)
    static let authTriggerTimer: Double = 30.0 * 60
    
    // MARK: - Notification Names
    
    /// Notification for timer-triggered actions
    static let nsmTimeTriggerNotification = Notification.Name("nsmTimeTriggerNotification")
    
    /// Notification for authentication-triggered actions
    static let nsmAuthTriggerNotification = Notification.Name("nsmAuthTriggerNotification")
    
    /// Notification for mount-triggered actions
    static let nsmMountTriggerNotification = Notification.Name("nsmMountTriggerNotification")
    
    /// Notification for network change events
    static let nsmNetworkChangeTriggerNotification = Notification.Name("nsmNetworkChangeTriggerNotification")
    
    /// Notification for unmount operations
    static let nsmUnmountTriggerNotification = Notification.Name("nsmUnmountTriggerNotification")
    
    /// Notification for manually-triggered mount operations
    static let nsmMountManuallyTriggerNotification = Notification.Name("nsmMountManuallyTriggerNotification")
    
    /// Notification for menu reconstruction
    static let nsmReconstructMenuTriggerNotification = Notification.Name("nsmReconstructMenuTriggerNotification")
    
    // MARK: - NetFS Mount Options
    
    /// Options for regular mounting without UI
    // swiftlint:disable force_cast
    static let openOptions = [
        kNAUIOptionKey: kNAUIOptionNoUI
    ] as! CFMutableDictionary
    
    /// Options for guest mounting without UI
    static let openOptionsGuest = [
        kNAUIOptionKey: kNAUIOptionNoUI,
        kNetFSUseGuestKey: true
    ] as! CFMutableDictionary
    
    /// Common mount options
    static let mountOptions = [
        kNetFSAllowSubMountsKey: true,
        kNetFSSoftMountKey: true,
        kNetFSMountAtMountDirKey: true
    ] as! CFMutableDictionary
    
    /// Mount options for system mount directory
    static let mountOptionsForSystemMountDir = [
        kNetFSAllowSubMountsKey: true,
        kNetFSSoftMountKey: true,
        kNetFSMountAtMountDirKey: false
    ] as! CFMutableDictionary
    // swiftlint:enable force_cast
    
    // MARK: - Cleanup Settings
    
    /// Files to delete during cleanup operations
    static let filesToDelete = [
        ".DS_Store",
        ".autodiskmounted"
    ]
    
    // MARK: - Path Settings
    
    /// Legacy default path for mounted shares (NSM versions 1 and 2)
    static let oldDefaultsMountPath = NSString(string: "~/\(Defaults.translation[Locale.current.languageCode!] ?? Defaults.translation["en"]!)").expandingTildeInPath
    
    /// Current default mount path (macOS standard)
    static let defaultMountPath = "/Volumes"
    
    // MARK: - Preference Keys
    
    /// Key for storing user accounts
    static let Accounts = "Accounts"
    
    /// Legacy key for MDM-defined shares
    static let networkSharesKey = "networkShares"
    
    /// Current MDM key for network shares
    static let managedNetworkSharesKey = "managedNetworkShares"
    
    /// Share configuration dictionary keys
    
    /// Authentication type of the share (.krb or pwd)
    static let authType = "authType"
    
    /// Share export path
    static let networkShare = "networkShare"
    
    /// Optional mount point for a specific share
    static let mountPoint = "mountPoint"
    
    /// Optional username to use on mount
    static let username = "username"
    
    /// Legacy key for user-defined shares
    static let customSharesKey = "customNetworkShares"
    
    /// Current key for user-defined shares
    static let userNetworkShares = "userNetworkShares"
}
