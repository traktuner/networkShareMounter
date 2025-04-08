//
//  SetupSession.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 15.12.23.
//  Copyright © 2020 Orchard & Grove, Inc. All rights reserved.
//  Copyright © 2025 RRZE. All rights reserved.
//

import Foundation
import dogeADAuth

extension dogeADSession {
    /// Configures the AD session with settings from the preference manager
    ///
    /// This method loads various LDAP/AD connection settings from the application
    /// preferences and applies them to the current session. It sets up:
    /// - SSL connection preference
    /// - Anonymous binding preference
    /// - Custom LDAP attributes to retrieve
    /// - LDAP server list
    ///
    /// - Parameter prefs: The PreferenceManager instance containing the configuration
    func setupSessionFromPrefs(prefs: PreferenceManager) {
        self.useSSL = prefs.bool(for: .lDAPoverSSL)
        self.anonymous = prefs.bool(for: .ldapAnonymous)
        self.customAttributes = prefs.array(for: .customLDAPAttributes) as? [String]
        self.ldapServers = prefs.array(for: .lDAPServerList) as? [String]
    }
}
