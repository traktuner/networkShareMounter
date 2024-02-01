//
//  SetupSession.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 15.12.23.
//  Copyright © 2020 Orchard & Grove, Inc. All rights reserved.
//  Copyright © 2024 RRZE. All rights reserved.
//

import Foundation
import dogeADAuth

extension dogeADSession {
    
    func setupSessionFromPrefs(prefs: PreferenceManager) {
        self.useSSL = prefs.bool(for: .lDAPoverSSL)
        self.anonymous = prefs.bool(for: .ldapAnonymous)
        self.customAttributes = prefs.array(for: .customLDAPAttributes) as? [String]
        self.ldapServers = prefs.array(for: .lDAPServerList) as? [String]
    }
}
