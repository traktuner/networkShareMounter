//
//  PreferenceKeys.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 15.12.23.
//  Copyright © 2020 Orchard & Grove, Inc. All rights reserved.
//  Copyright © 2024 RRZE. All rights reserved.
//

import Foundation
import OSLog

/// Keys used for accessing user preferences in the application
///
/// This enumeration defines all preference keys used throughout the application.
/// Each key corresponds to a specific setting that can be stored in and retrieved from `UserDefaults`.
enum PreferenceKeys: String, CaseIterable {
    
    typealias RawValue = String
    
    // MARK: - User Account Settings
    
    /// List of user accounts
    case accounts = "Accounts"
    
    /// Active Directory domain
    case aDDomain = "ADDomain"
    
    /// Active Directory domain controller
    case aDDomainController = "ADDomainController"
    
    /// Dictionary of all user information
    case allUserInformation = "AllUserInformation"
    
    /// Custom LDAP attributes to query
    case customLDAPAttributes = "CustomLDAPAttributes"
    
    /// Results of custom LDAP attribute queries
    case customLDAPAttributesResults = "CustomLDAPAttributesResults"
    
    /// User's display name
    case displayName = "DisplayName"
    
    /// Whether to hide the last user in UI
    case hideLastUser = "HideLastUser"
    
    /// Kerberos realm for authentication
    case kerberosRealm = "kerberosRealm"
    
    /// Whether LDAP queries should be anonymous
    case ldapAnonymous = "LDAPAnonymous"
    
    /// List of LDAP servers to query
    case lDAPServerList = "LDAPServerList"
    
    /// Whether to use SSL for LDAP connections
    case lDAPoverSSL = "LDAPOverSSL"
    
    /// Last logged in user
    case lastUser = "LastUser"
    
    /// Whether to use single user mode
    case singleUserMode = "SingleUserMode"
    
    /// User's Common Name (CN)
    case userCN = "UserCN"
    
    /// User's group memberships
    case userGroups = "UserGroups"
    
    /// User's Kerberos principal
    case userPrincipal = "UserPrincipal"
    
    /// User's home directory
    case userHome = "UserHome"
    
    /// User's password expiration date
    case userPasswordExpireDate = "UserPasswordExpireDate"
    
    /// Date when user's password was last set
    case userPasswordSetDate = "UserPasswordSetDate"
    
    /// Whether to use Keychain for password storage
    case useKeychain = "UseKeychain"
    
    /// User's email address
    case userEmail = "UserEmail"
    
    /// User's first name
    case userFirstName = "UserFirstName"
    
    /// User's full name
    case userFullName = "UserFullName"
    
    /// User's last name
    case userLastName = "UserLastName"
    
    /// Last time user information was checked
    case userLastChecked = "UserLastChecked"
    
    /// User's short name (username)
    case userShortName = "UserShortName"
    
    /// User's User Principal Name (UPN)
    case userUPN = "UserUPN"
    
    // MARK: - Application Settings
    
    /// Whether to unmount shares on application exit
    case unmountOnExit = "unmountOnExit"
    
    /// URL for help documentation
    case helpURL = "helpURL"
    
    /// Whether user can change autostart setting
    case canChangeAutostart = "canChangeAutostart"
    
    /// Whether user can quit the application
    case canQuit = "canQuit"
    
    /// Whether application starts automatically at login
    case autostart = "autostart"
    
    /// Whether auto-updater is enabled.
    /// Since NSM 4 this is a legacy value and is essentially serving as an inverted alias for disableAutoUpdateFramework
    case enableAutoUpdater = "enableAutoUpdater"
    
    /// Wheter Sparkle framework is enabled/loaded
    case disableAutoUpdateFramework = "disableAutoUpdateFramework"
    
    /// Sparkle: Whether to automatically check for updates
    case automaticallyChecksForUpdates = "automaticallyChecksForUpdates"
    
    /// Sparkle: Whether to automatically install updates
    case automaticallyDownloadsUpdates = "automaticallyDownloadsUpdates"
    
    /// OBSOLETE: Sparkle: Whether to automatically check for updates
    case SUEnableAutomaticChecks = "SUEnableAutomaticChecks"
    
    /// OBSOLETE: Sparkle: Whether to automatically install updates
    case SUAutomaticallyUpdate = "SUAutomaticallyUpdate"
    
    /// OBSOLETE: Sparkle: Whether the app has been launched before
    case SUHasLaunchedBefore = "SUHasLaunchedBefore"
    
    /// Whether to automatically check for updates
    case autoUpdate = "autoUpdate"
    
    /// Directory for cleanup operations
    case cleanupLocationDirectory = "cleanupLocationDirectory"
    
    /// Unique identifier for the application instance
    case UUID = "UUID"
    
    /// Override for username if local and remote usernames differ
    case usernameOverride = "usernameOverride"
    
    /// Whether to send diagnostic data
    case sendDiagnostics = "sendDiagnostics"
    
    /// Whether to use new default location for mounts
    case useNewDefaultLocation = "useNewDefaultLocation"
    
    /// Whether to use localized directory names for mount points
    /// When false, always uses "Networkshares" for backward compatibility
    case useLocalizedMountDirectories = "useLocalizedMountDirectories"
    
    // MARK: - Network Share Settings
    
    /// List of network shares
    case networkSharesKey = "networkShares"
    
    /// List of managed network shares (from MDM)
    case managedNetworkSharesKey = "managedNetworkShares"
    
    /// Authentication type for shares
    case authType = "authType"
    
    /// Network share path
    case networkShare = "networkShare"
    
    /// Mount point for shares
    case mountPoint = "mountPoint"
    
    /// Username for share authentication
    case username = "username"
    
    /// List of custom network shares
    case customSharesKey = "customNetworkShares"
    
    /// List of user-specific network shares
    case userNetworkShares = "userNetworkShares"
    
    /// Location for network shares
    case location = "location"
    
    // MARK: - UI Settings
    
    /// Image name for authentication dialog
    case authenticationDialogImage = "authenticationDialogImage"
    
    /// Service name for keychain entries
    case keyChainService = "keyChainService"
    
    /// Label for keychain entries
    case keyChainLabel = "keyChainLabel"
    
    /// Comment for keychain entries
    case keyChainComment = "keyChainComment"
    
    /// Whether keychain migration from Prefix Manager is done
    case keyChainPrefixManagerMigration = "keyChainPrefixManagerMigration"
    
    // MARK: - Menu Items
    
    /// Whether to show Quit menu item
    case menuQuit = "menuQuit"
    
    /// Whether to show About menu item
    case menuAbout = "menuAbout"
    
    /// Whether to show Connect Shares menu item
    case menuConnectShares = "menuConnectShares"
    
    /// Whether to show Disconnect Shares menu item
    case menuDisconnectShares = "menuDisconnectShares"
    
    /// Whether to show Check Updates menu item
    case menuCheckUpdates = "menuCheckUpdates"
    
    /// Whether to show Show Shares Mount Directory menu item
    case menuShowSharesMountDir = "menuShowSharesMountDir"
    
    /// Whether to show Show Shares menu item
    case menuShowShares = "menuShowShares"
    
    /// Whether to show Settings menu item
    case menuSettings = "menuSettings"
    
    // MARK: - Utility Functions
    
    /// Prints all preferences and their values to the console
    ///
    /// This function iterates through all preference keys and prints
    /// their current values from UserDefaults, formatting them according
    /// to their type.
    func printAllPrefs() {
        let defaults = UserDefaults.standard
        
        Logger.preferences.debug("Printing all preference values:")
        
        for key in PreferenceKeys.allCases {
            guard let value = defaults.object(forKey: key.rawValue) else {
                Logger.preferences.debug("\(key.rawValue): Unset")
                continue
            }
            
            // Format the value based on its type
            let formattedValue: String
            
            switch value {
            case let boolValue as Bool:
                formattedValue = String(describing: boolValue)
                
            case let arrayValue as [Any]:
                formattedValue = String(describing: arrayValue)
                
            case let dateValue as Date:
                formattedValue = dateValue.description(with: Locale.current)
                
            case let dictValue as [String: Any]:
                formattedValue = String(describing: dictValue)
                
            case let dataValue as Data:
                formattedValue = dataValue.base64EncodedString()
                
            case let stringValue as String:
                formattedValue = stringValue
                
            default:
                formattedValue = String(describing: value)
            }
            
            // Log the key and its value
            if defaults.objectIsForced(forKey: key.rawValue) {
                Logger.preferences.debug("\(key.rawValue): \(formattedValue) (Forced)")
            } else {
                Logger.preferences.debug("\(key.rawValue): \(formattedValue)")
            }
        }
    }
}
