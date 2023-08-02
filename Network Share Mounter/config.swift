//
//  config.swift
//  networkShareMounter
//
//  Created by Kett, Oliver on 20.03.17.
//  bugfixing and enhancements by FAUmac Team
//  Copyright © 2017 RRZE. All rights reserved.
//

import NetFS

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
        kNetFSSoftMountKey: true
        ] as! CFMutableDictionary
    // swiftlint:enable force_cast
    static let filesToDelete = [
        ".DS_Store",
        ".autodiskmounted"
    ]
    static let statisticsReportURL = "https://faumac.rrze.fau.de/apps"
    
    /// userDefaults dictionary names
    static let networkSharesKey = "networkShares"
    static let managedNetworkSharesKey = "managedNetworkShares"
    static let customSharesKey = "customNetworkShares"
    static let authType = "authType"
    static let networkShare = "networkShare"
    static let username = "username"
}
