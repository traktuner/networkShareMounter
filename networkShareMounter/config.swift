//
//  config.swift
//  networkShareMounter
//
//  Created by Kett, Oliver on 20.03.17.
//  bugfixing and enhancements by FAUmac Team
//  Copyright © 2017 RRZE. All rights reserved.
//

import NetFS

struct config {
    static let defaultsDomain = "de.uni-erlangen.rrze.networkShareMounter"
    static let translation = [
        "en": "Networkshares",
        "de": "Netzlaufwerke",
        ]
    static let open_options = [
        kNAUIOptionKey: kNAUIOptionNoUI
        ] as! CFMutableDictionary
    static let mount_options = [
        kNetFSMountFlagsKey: MNT_DONTBROWSE,
        kNetFSAllowSubMountsKey: true,
        kNetFSSoftMountKey: true
        ] as! CFMutableDictionary
    static let filesToDelete = [
        ".DS_Store",
        ".autodiskmounted"
    ]
}
