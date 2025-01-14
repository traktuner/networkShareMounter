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

struct Defaults {
    static let defaultsDomain = "de.fau.rrze.NetworkShareMounter"
    static let keyChainService = "Network Share Mounter account"
    static let keyChainLabel = "Network Share Mounter account"
    static let keyChainLabelKerberos = "Network Share Mounter Kerberos account"
    static let keyChainAccessGroup = "C8F68RFW4L.de.fau.rrze.faucredentials"
    static let translation = [
        "en": "Networkshares",
        "de": "Netzlaufwerke"
        ]
    // number of seconds bevor triggering actions
    static let mountTriggerTimer: Double = 5.0 * 60
    static let authTriggerTimer: Double = 30.0 * 60
    static let nsmTimeTriggerNotification = Notification.Name("nsmTimeTriggerNotification")
    static let nsmAuthTriggerNotification = Notification.Name("nsmAuthTriggerNotification")
    static let nsmMountTriggerNotification = Notification.Name("nsmMountTriggerNotification")
    static let nsmNetworkChangeTriggerNotification = Notification.Name("nsmNetworkChangeTriggerNotification")
    static let nsmUnmountTriggerNotification = Notification.Name("nsmUnmountTriggerNotification")
    static let nsmMountManuallyTriggerNotification = Notification.Name("nsmMountManuallyTriggerNotification")
    static let nsmReconstructMenuTriggerNotification = Notification.Name("nsmReconstructMenuTriggerNotification")
    
    static let sentryDSN = "https://a0768af20276c5f3b9bcd16a8d89e460@apps.faumac.de:8443/2"
    // swiftlint:disable force_cast
    static let openOptions = [
        kNAUIOptionKey: kNAUIOptionNoUI
        ] as! CFMutableDictionary
    static let openOptionsGuest = [
        kNAUIOptionKey: kNAUIOptionNoUI,
        kNetFSUseGuestKey: true
        ] as! CFMutableDictionary
    static let mountOptions = [
        kNetFSAllowSubMountsKey: true,
        kNetFSSoftMountKey: true,
        kNetFSMountAtMountDirKey: true
        ] as! CFMutableDictionary
    static let mountOptionsForSystemMountDir = [
        kNetFSAllowSubMountsKey: true,
        kNetFSSoftMountKey: true,
        kNetFSMountAtMountDirKey: false
        ] as! CFMutableDictionary
    // swiftlint:enable force_cast
    static let filesToDelete = [
        ".DS_Store",
        ".autodiskmounted"
    ]
    static let statisticsReportURL = "https://faumac.rrze.fau.de/apps"

    /// NSM version 1 and 2 the default path where shares got mounted
    static let oldDefaultsMountPath = NSString(string: "~/\(Defaults.translation[Locale.current.languageCode!] ?? Defaults.translation["en"]!)").expandingTildeInPath
    /// if not set otherwise mounts will be done under this path which defaults to macOS's efault `/Volumes`
    static let defaultMountPath = "/Volumes"
    /// key for values used to store user accounts
    static let Accounts = "Accounts"
    
    /// legacy key for former MDM defined shares
    static let networkSharesKey = "networkShares"
    /// MDM key
    static let managedNetworkSharesKey = "managedNetworkShares"
    /// **The following keys are used as dictionary keys for mdm managed network shares:**
        /// auhType of the share (.krb or pwd)
        static let authType = "authType"
        /// share export path
        static let networkShare = "networkShare"
        /// optional mount point of the specific share
        static let mountPoint = "mountPoint"
        /// optional username to use on mount
        static let username = "username"
    /// legacy key for user defined shares
    static let customSharesKey = "customNetworkShares"
    /// key for user defined shares
    static let userNetworkShares = "userNetworkShares"
}
