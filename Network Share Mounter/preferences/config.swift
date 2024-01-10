//
//  config.swift
//  networkShareMounter
//
//  Created by Kett, Oliver on 20.03.17.
//  bugfixing and enhancements by FAUmac Team
//  Copyright © 2017 RRZE. All rights reserved.
//

import NetFS
import Foundation

struct Settings {
    static let defaultsDomain = "de.fau.rrze.NetworkShareMounter"
    static let translation = [
        "en": "Networkshares",
        "de": "Netzlaufwerke"
        ]
    // swiftlint:disable force_cast
    static let openOptions = [
        kNAUIOptionKey: kNAUIOptionNoUI
        ] as! CFMutableDictionary
    static let mountOptions = [
        kNetFSAllowSubMountsKey: true,
        kNetFSSoftMountKey: true,
        kNetFSMountAtMountDirKey: true
        ] as! CFMutableDictionary
    // swiftlint:enable force_cast
    static let filesToDelete = [
        ".DS_Store",
        ".autodiskmounted"
    ]
    static let statisticsReportURL = "https://faumac.rrze.fau.de/apps"

    /// NSM version 1 and 2 the default path where shares got mounted
    static let oldDefaultsMountPath = NSString(string: "~/\(Settings.translation[Locale.current.languageCode!] ?? Settings.translation["en"]!)").expandingTildeInPath
    /// if not set otherwise mounts will be done under this path which defaults to macOS's efault `/Volumes`
    static let defaultMountPath = "/Volumes"
    
    /// **userDefaults dictionary names, used as keys in userDefaults:**
    ///
    /// key for a boolean value if shares should be unmounted on exit
    static let unmountOnExit = "unmountOnExit"
    /// key for a string kontaining help url
    static let helpURL = "helpURL"
    /// key for a boolean value defining if user can change autostart behaviour
    static let canChangeAutostart = "canChangeAutostart"
    /// key for a boolean value defining if user can quit the app
    static let canQuit = "canQuit"
    /// key for a boolean value defining if app will start on login
    static let autostart = "autostart"
    /// key for a string containing a boolean defining if mount directory will be cleaned up
    static let cleanupLocationDirectory = "cleanupLocationDirectory"
    /// key for a string containing apps UUID (used for app statistics)
    static let UUID = "UUID"
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
    /// optional location of the directory containig the mounts
    static let location = "location"
    /// optional string containing AD/Kerberos Domain
    static let kerberosDomain = "kerberosDomain"
    /// optional bool to define if user's keychain should sync via iCloud
    /// defaults to false
    static let keychainiCloudSync = "keychainiCloudSync"
    /// key to define the logo/image on kerbeors login screen, defaults to nsm_logo
    static let authenticationDialogImage = "authenticationDialogImage"
    /// optional key to define the service name used to stroe keychain entries
    static let keyChainService = "keyChainService"
    /// key to define keychain entry comment
    static let keyChainComment = "keyChainComment"
    /// key for values used to store user accounts
    static let Accounts = "Accounts"
}
