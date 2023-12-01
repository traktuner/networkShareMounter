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
    
    /// userDefaults dictionary names, used as keys in userDefaults:
    /// legacy MDM key
    static let networkSharesKey = "networkShares"
    /// MDM key
    static let managedNetworkSharesKey = "managedNetworkShares"
    /// legacy user defined key
    static let customSharesKey = "customNetworkShares"
    /// user defined key
    static let userNetworkShares = "userNetworkShares"
    /// auhType of the share (.krb or pwd)
    static let authType = "authType"
    /// share export path
    static let networkShare = "networkShare"
    /// optional mount point of the specific share
    static let mountPoint = "mountPoint"
    /// optional username to use on mount
    static let username = "username"
    /// optional location of the directory containig the mounts
    static let location = "location"
}
