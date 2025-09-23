//
//  PreferenceManager.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 15.12.23.
//  Copyright © 2025 RRZE. All rights reserved.
//

import Foundation
import dogeADAuth
import OSLog

/// Constants for UserDefaults domains
private enum UserDefaultsDomains {
    static let stateDomain = "de.fau.rrze.NetworkShareMounter.doge.state"
    static let sharedDefaultsName = "de.fau.rrze.NetworkShareMounter"
}

/// Extension to UserDefaults for dynamic property support
extension UserDefaults {
    @objc dynamic var Accounts: Data? {
        return data(forKey: Defaults.Accounts)
    }
}

/// Manages application preferences and user state using UserDefaults
/// 
/// This class handles all preference-related operations including:
/// - Reading and writing user preferences
/// - Managing AD user information
/// - Handling state persistence
/// - Loading default values
struct PreferenceManager {
    /// Logger instance for preference operations
    private static let logger = Logger.preferences
    
    /// Standard UserDefaults instance for general preferences
    private let defaults = UserDefaults.standard
    
    /// State-specific UserDefaults instance for user state
    private let stateDefaults: UserDefaults?
    
    /// Initializes a new PreferenceManager
    /// 
    /// This initializer sets up the UserDefaults instances and loads default values
    init() {
        stateDefaults = UserDefaults(suiteName: UserDefaultsDomains.stateDomain)
        
        if let defaultValues = readPropertyList() {
            defaults.register(defaults: defaultValues)
            Self.logger.debug("Default values loaded successfully")
        } else {
            Self.logger.error("Failed to load default values")
        }
    }
    
    // MARK: - Preference Access Methods
    
    /// Retrieves an array for the specified preference key
    /// - Parameter prefKey: The preference key to look up
    /// - Returns: The array value if found, nil otherwise
    func array(for prefKey: PreferenceKeys) -> [Any]? {
        defaults.array(forKey: prefKey.rawValue)
    }
    
    /// Retrieves a string for the specified preference key
    /// - Parameter prefKey: The preference key to look up
    /// - Returns: The string value if found, nil otherwise
    func string(for prefKey: PreferenceKeys) -> String? {
        defaults.string(forKey: prefKey.rawValue)
    }
    
    /// Retrieves an object for the specified preference key
    /// - Parameter prefKey: The preference key to look up
    /// - Returns: The object value if found, nil otherwise
    func object(for prefKey: PreferenceKeys) -> Any? {
        defaults.object(forKey: prefKey.rawValue)
    }
    
    /// Retrieves a dictionary for the specified preference key
    /// - Parameter prefKey: The preference key to look up
    /// - Returns: The dictionary value if found, nil otherwise
    func dictionary(for prefKey: PreferenceKeys) -> [String:Any]? {
        defaults.dictionary(forKey: prefKey.rawValue)
    }
    
    /// Retrieves a boolean for the specified preference key
    /// - Parameter prefKey: The preference key to look up
    /// - Returns: The boolean value
    func bool(for prefKey: PreferenceKeys) -> Bool {
        defaults.bool(forKey: prefKey.rawValue)
    }
    
    /// Retrieves a boolean for the specified preference key with a default value
    /// - Parameters:
    ///   - key: The preference key to look up
    ///   - defaultValue: The default value to return if the key doesn't exist
    /// - Returns: The boolean value or the default value
    func bool(for key: PreferenceKeys, defaultValue: Bool) -> Bool {
        guard let value = defaults.object(forKey: key.rawValue) as? Bool else {
            return defaultValue
        }
        return value
    }
    
    /// Sets a value for the specified preference key
    /// - Parameters:
    ///   - prefKey: The preference key to set
    ///   - value: The value to set
    func set<T>(for prefKey: PreferenceKeys, value: T) {
        defaults.set(value, forKey: prefKey.rawValue)
    }
    
    /// Retrieves an integer for the specified preference key
    /// - Parameter prefKey: The preference key to look up
    /// - Returns: The integer value
    func int(for prefKey: PreferenceKeys) -> Int {
        defaults.integer(forKey: prefKey.rawValue)
    }
    
    /// Retrieves a date for the specified preference key
    /// - Parameter prefKey: The preference key to look up
    /// - Returns: The date value if found, nil otherwise
    func date(for prefKey: PreferenceKeys) -> Date? {
        defaults.object(forKey: prefKey.rawValue) as? Date
    }
    
    /// Clears the value for the specified preference key
    /// - Parameter prefKey: The preference key to clear
    func clear(for prefKey: PreferenceKeys) {
        defaults.set(nil, forKey: prefKey.rawValue)
    }
    
    /// Retrieves data for the specified preference key
    /// - Parameter prefKey: The preference key to look up
    /// - Returns: The data value if found, nil otherwise
    func data(for prefKey: PreferenceKeys) -> Data? {
        defaults.data(forKey: prefKey.rawValue)
    }
    
    // MARK: - AD User Information Management
    
    /// Sets AD user information in UserDefaults
    /// - Parameter user: The AD user record to store
    func setADUserInfo(user: ADUserRecord) {
        Self.logger.debug("Setting AD user info for user: \(user.userPrincipal)")
        
        defaults.set(user.userPrincipal.lowercased(), forKey: PreferenceKeys.lastUser.rawValue)
        
        if let passwordAging = user.passwordAging, passwordAging {
            if let expireDate = user.computedExpireDate {
                self.set(for: .userPasswordExpireDate, value: expireDate)
                Self.logger.debug("Password expiration date set: \(expireDate)")
            }
        } else {
            self.clear(for: .userPasswordExpireDate)
            Self.logger.debug("Password expiration date cleared")
        }
        
        guard let stateDefaults = stateDefaults else {
            Self.logger.error("Failed to access state defaults")
            return
        }
        
        // Store user information in state defaults
        let userInfo: [PreferenceKeys: Any?] = [
            .userCN: user.cn,
            .userGroups: user.groups,
            .userPasswordExpireDate: user.computedExpireDate,
            .userPasswordSetDate: user.passwordSet,
            .userHome: user.homeDirectory,
            .userPrincipal: user.userPrincipal,
            .customLDAPAttributesResults: user.customAttributes,
            .userShortName: user.shortName,
            .userUPN: user.upn,
            .userEmail: user.email,
            .userFullName: user.fullName,
            .userFirstName: user.firstName,
            .userLastName: user.lastName,
            .userLastChecked: Date()
        ]

        for (key, value) in userInfo {
            if let validValue = value {
                stateDefaults.set(validValue, forKey: key.rawValue)
            } else {
                stateDefaults.removeObject(forKey: key.rawValue)
            }
        }
        
        // Update all users dictionary
        var allUsers = stateDefaults.dictionary(forKey: PreferenceKeys.allUserInformation.rawValue) as? [String: [String: AnyObject]] ?? [:]

        var userInfoDict = [String: AnyObject]()
        for (key, value) in userInfo {
            if let validValue = value {
                userInfoDict[key.rawValue] = validValue as AnyObject
            }
        }

        allUsers[user.userPrincipal] = userInfoDict
        stateDefaults.setValue(allUsers, forKey: PreferenceKeys.allUserInformation.rawValue)
        
        Self.logger.debug("Successfully updated user information for: \(user.userPrincipal)")
    }
    
    // MARK: - Private Methods
    
    /// Reads the default values from the property list
    /// - Returns: Dictionary of default values if successful, nil otherwise
    private func readPropertyList() -> [String: Any]? {
        guard let plistPath = Bundle.main.path(forResource: "DefaultValues", ofType: "plist") else {
            Self.logger.error("DefaultValues.plist not found")
            return nil
        }
        
        guard let plistData = FileManager.default.contents(atPath: plistPath) else {
            Self.logger.error("Failed to read DefaultValues.plist")
            return nil
        }
        
        do {
            let defaults = try PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
            if defaults == nil {
                Self.logger.error("Failed to parse DefaultValues.plist")
            }
            return defaults
        } catch {
            Self.logger.error("Error parsing DefaultValues.plist: \(error.localizedDescription)")
            return nil
        }
    }
}
