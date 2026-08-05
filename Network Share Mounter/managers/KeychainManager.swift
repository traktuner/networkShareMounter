//
//  PasswordManager.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 20.11.23.
//  Copyright © 2024 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation
import Security
import OSLog

/// Description of the CFDictionary for a new keychain entry
///
/// kSecClass -> kSecClassInternetPassword (keychain entry with more than just the password
/// kSecAttrService -> string indicating the item's service
/// kSecAttrComment -> string containing a comment to the keychain entry
/// kSecAttrAccessGroup -> string with identifier for group with access to keychain entry
/// kSecAttrAccount -> string with username
/// kSecValueData -> data containing the utf8 encoded password string
/// kSecAttrServer -> the server URL/IP address part of the share
/// kSecAttrPath -> the path part of the share
/// kSecAttrProtocol -> the protocol part of the share (kSecAttrProtocolSMB, kSecAttrProtocolAFP, kSecAttrProtocolHTTPS, kSecAttrProtocolFTP)
/// kSecAttrLabel -> the name of the keychain entry, shown as "Name:" in Schlüsselbundverwaltung, can be used to filter for multiple keychain entries
/// kSecUseDataProtectionKeychain -> kCFBooleanTrue - a key whose value indicates whether to treat macOS keychain items like iOS keychain items
/// kSecAttrSynchronizable -> CFbool indicating whether the item synchronizes through iCloud.
///     (look at https://developer.apple.com/forums/thread/114456)
///
/// example
///     username: batman
///     password: !'mB4tM4n
///     share: smb//fileserver.batcave.org/enemies
///     keychain entry name: fileserver.batcave.org
/// will result in:
/// var query: [String: Any] = [kSecClass as String: kSecClassInternetPassword,
///                             kSecAttrAccount as String: "batman"",
///                             kSecAttrServer as String: "fileserver.batcave.org",
///                             kSecAttrPath as String: "enemies",
///                             kSecAttrProtocol as String: kSecAttrProtocolSMB,
///                             kSecAttrLabel as String: Settings.defaultsDomain,
///                             kSecAttrLabel as String: "fileserver.batcave.org",
///                             kSecValueData as String: "!'mB4tM4n".data(using: String.Encoding.utf8)!]

struct Credentials {
    var username: String
    var password: String
}

enum KeychainError: Error, Equatable, LocalizedError {
    case noPassword
    case malformedShare
    case unexpectedPasswordData
    case undefinedError
    case errorRemovingEntry
    case errorRetrievingPassword
    case errorAccessingPassword
    case errorWithStatus(status: OSStatus)
    case itemNotFound

    var errorDescription: String? {
        switch self {
        case .noPassword:
            return "No password found"
        case .malformedShare:
            return "Malformed share URL"
        case .unexpectedPasswordData:
            return "Unexpected password data format"
        case .undefinedError:
            return "Undefined keychain error"
        case .errorRemovingEntry:
            return "Error removing keychain entry"
        case .errorRetrievingPassword:
            return "Error retrieving password from keychain"
        case .errorAccessingPassword:
            return "Error accessing password in keychain"
        case .itemNotFound:
            return "Error accessing entry, not found in keychain"
        case .errorWithStatus(let status):
            return "Keychain error: OSStatus \(status) (\(Self.describeStatus(status)))"
        }
    }

    private static func describeStatus(_ status: OSStatus) -> String {
        switch status {
        case errSecSuccess: return "Success"
        case errSecItemNotFound: return "Item not found"
        case errSecDuplicateItem: return "Duplicate item"
        case errSecParam: return "Invalid parameter"
        case errSecAuthFailed: return "Authentication failed"
        case errSecInteractionRequired: return "User interaction required"
        case errSecNotAvailable: return "Keychain not available"
        case -34018: return "Missing entitlement or access denied"
        case -25243: return "No access to item"
        case -25291: return "Keychain not available (FileVault?)"
        case -25308: return "User interaction required"
        case -25293: return "Authentication failed"
        default: return "Unknown error"
        }
    }
}

class KeychainManager: NSObject {
    // MARK: - Configuration
    
    /// Controls whether created items are iCloud-synchronizable.
    /// Defaults to false to preserve existing behavior.
    private let synchronizable: Bool
    
    /// Controls the accessibility of created items.
    /// Defaults to kSecAttrAccessibleAfterFirstUnlock.
    private let accessibility: CFString
    
    /// Initialize a KeychainManager with configuration.
    /// - Parameters:
    ///   - synchronizable: If true, created items will be iCloud-synchronizable.
    ///   - accessibility: kSecAttrAccessible* value to use for created items.
    init(synchronizable: Bool = false, accessibility: CFString = kSecAttrAccessibleAfterFirstUnlock) {
        self.synchronizable = synchronizable
        self.accessibility = accessibility
        super.init()
    }
    
    // MARK: - Query builders
    
    /// function to create a query to use with keychain
    /// - Parameter forShare: ``String`` containing the URL of a network share
    /// - Parameter withUsername: ``String`` contining the username to connect the network share
    /// - Parameter andPassword: ``String`` containing the password for username
    /// - Parameter service: ``String?`` optional string containing keychain service name
    /// - Parameter accessGroup: ``String?`` optional string with access group to keychain entry
    /// - Parameter comment: ``String?`` optional string with a comment to the keychain entry
    /// - Parameter label: ``String?`` optional string for kSecAttrLabel
    func makeQuery(share shareURL: URL, username: String, service: String? = nil, accessGroup: String? = nil, comment: String? = nil, label: String? = nil) throws -> [String: Any]  {
        guard let host = shareURL.host else {
            throw KeychainError.malformedShare
        }
        let path = shareURL.path
        let urlScheme = shareURL.scheme

        var query: [String: Any] = [kSecClass as String: kSecClassInternetPassword,
                                    kSecAttrAccount as String: username,
                                    kSecAttrServer as String: host,
                                    kSecAttrPath as String: path,
                                    kSecAttrAccessible as String: accessibility
                                    ]
        // Synchronizable flag according to configuration (for write/update queries)
        query[kSecAttrSynchronizable as String] = synchronizable ? kCFBooleanTrue as Any : kCFBooleanFalse as Any
        
        switch urlScheme {
        case "https":
            query[kSecAttrProtocol as String] = kSecAttrProtocolHTTPS
        case "afp":
            query[kSecAttrProtocol as String] = kSecAttrProtocolAFP
        case "smb", "cifs":
            query[kSecAttrProtocol as String] = kSecAttrProtocolSMB
        default:
            query[kSecAttrProtocol as String] = kSecAttrProtocolSMB
        }
        if let kcComment = comment {
            query[kSecAttrComment as String] = kcComment
        }
        if let kcAccessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = kcAccessGroup
        }
        if let kcService = service {
            query[kSecAttrService as String] = kcService
        }
        if let labelValue = label {
            query[kSecAttrLabel as String] = labelValue
        } else {
            // default label: host
            query[kSecAttrLabel as String] = host
        }
        return query
    }
    
    /// create a query to use with keychain
    /// - Parameter withUsername: ``String`` contining the username to connect the network share
    /// - Parameter service: ``String`` string containing keychain service name
    /// - Parameter accessGroup: ``String?`` optional string with access group to keychain entry
    /// - Parameter label: ``String`` string containing keychain label name
    /// - Parameter comment: ``String?`` optional string with a comment to the keychain entry
    func makeQuery(username: String, service: String = Defaults.keyChainService, accessGroup: String? = nil, label: String? = nil, comment: String? = nil) throws -> [String: Any]  {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrAccount as String: username,
                                    kSecAttrService as String: service,
                                    kSecAttrAccessible as String: accessibility
                                    ]
        // Synchronizable flag according to configuration (for write/update queries)
        query[kSecAttrSynchronizable as String] = synchronizable ? kCFBooleanTrue as Any : kCFBooleanFalse as Any
        
        if let kcComment = comment {
            query[kSecAttrComment as String] = kcComment
        }
        if let kcAccessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = kcAccessGroup
        }
        if let labelValue = label {
            query[kSecAttrLabel as String] = labelValue
        }
        
        return query
    }
    
    // MARK: - Create / Update
    
    func saveCredential(forShare share: URL, withUsername username: String, andPassword password: String, withLabel label: String? = Defaults.keyChainService, accessGroup: String? = Defaults.keyChainAccessGroup, comment: String? = nil) throws {
        do {
            var query = try makeQuery(share: share, username: username, accessGroup: accessGroup, comment: comment, label: label)
            
            guard let passwordData = password.data(using: String.Encoding.utf8) else {
                throw KeychainError.unexpectedPasswordData
            }
            query[kSecValueData as String] = passwordData
            
            SecItemDelete(query as CFDictionary)
            
            let status = SecItemAdd(query as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw KeychainError.errorWithStatus(status: status)
            }
        } catch let error as KeychainError {
            throw error
        } catch {
            throw KeychainError.undefinedError
        }
    }
    
    func saveCredential(forUsername username: String, andPassword password: String, withService service: String = Defaults.keyChainService, andLabel label: String? = nil, accessGroup: String? = nil, comment: String? = nil) throws {
        do {
            var query = try makeQuery(username: username, service: service, accessGroup: accessGroup, label: label, comment: comment)
            
            guard let passwordData = password.data(using: String.Encoding.utf8) else {
                throw KeychainError.unexpectedPasswordData
            }
            query[kSecValueData as String] = passwordData
            
            SecItemDelete(query as CFDictionary)
            
            let status = SecItemAdd(query as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw KeychainError.errorWithStatus(status: status)
            }
        } catch let error as KeychainError {
            throw error
        } catch {
            throw KeychainError.undefinedError
        }
    }

    // MARK: - Delete
    
    func removeCredential(forShare share: URL, withUsername username: String) throws {
        do {
            guard credentialExists(forShare: share, withUsername: username) else {
                return
            }
            
            let query = try makeQuery(share: share, username: username)
            let status = SecItemDelete(query as CFDictionary)
            
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError.errorWithStatus(status: status)
            }
        } catch let error as KeychainError {
            throw error
        } catch {
            throw KeychainError.errorRemovingEntry
        }
    }
    
    func removeCredential(forUsername username: String, andService service: String = Defaults.keyChainService, accessGroup: String? = Defaults.keyChainAccessGroup) throws {
        do {
            guard credentialExists(forUsername: username, andService: service, accessGroup: accessGroup) else {
                return
            }
            
            let query = try makeQuery(username: username, service: service, accessGroup: accessGroup)
            let status = SecItemDelete(query as CFDictionary)
            
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError.errorWithStatus(status: status)
            }
        } catch let error as KeychainError {
            throw error
        } catch {
            throw KeychainError.errorRemovingEntry
        }
    }
    
    // MARK: - Read
    
    func retrievePassword(forShare share: URL, withUsername username: String) throws -> String? {
        do {
            Logger.keychain.debug("🔐 Retrieving password for share: \(share.absoluteString, privacy: .public), username: \(username, privacy: .public)")

            // Try with original case first
            var query = try makeQuery(share: share, username: username, accessGroup: Defaults.keyChainAccessGroup, label: Defaults.keyChainService)
            query[kSecReturnData as String] = kCFBooleanTrue!
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            // Always search both local and iCloud-synced items to preserve compatibility.
            query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny

            Logger.keychain.debug("🔐 Keychain query: \(query, privacy: .public)")

            var ref: AnyObject? = nil
            let status = SecItemCopyMatching(query as CFDictionary, &ref)
            Logger.keychain.debug("🔐 Keychain status: \(status, privacy: .public)")

            if status == errSecSuccess {
                if let parsedData = ref as? Data {
                    let password = String(data: parsedData, encoding: .utf8)
                    Logger.keychain.debug("🔐 Successfully retrieved password for \(share.absoluteString, privacy: .public)")
                    return password
                } else {
                    Logger.keychain.error("🔐 Failed to parse password data from keychain for \(share.absoluteString, privacy: .public)")
                    Logger.keychain.error("🔐 Retrieved data type: \(type(of: ref), privacy: .public)")
                    return nil
                }
            } else if status == errSecItemNotFound {
                Logger.keychain.debug("🔐 No keychain entry found for \(share.absoluteString, privacy: .public)")

                // Fallback: Try with lowercase username if different from original
                let lowercasedUsername = username.lowercased()
                if lowercasedUsername != username {
                    Logger.keychain.debug("🔍 Trying lowercase fallback for username: \(username)")

                    var lowercaseQuery = try makeQuery(share: share, username: lowercasedUsername, accessGroup: Defaults.keyChainAccessGroup, label: Defaults.keyChainService)
                    lowercaseQuery[kSecReturnData as String] = kCFBooleanTrue!
                    lowercaseQuery[kSecMatchLimit as String] = kSecMatchLimitOne
                    lowercaseQuery[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
                    var lowercaseRef: AnyObject? = nil

                    let lowercaseStatus = SecItemCopyMatching(lowercaseQuery as CFDictionary, &lowercaseRef)

                    if lowercaseStatus == errSecSuccess, let parsedData = lowercaseRef as? Data, let password = String(data: parsedData, encoding: .utf8) {
                        Logger.keychain.info("🔄 Found share credential with lowercase username, migrating: \(lowercasedUsername) -> \(username)")

                        // Migrate: Save with correct case, then delete old entry
                        do {
                            try saveCredential(forShare: share, withUsername: username, andPassword: password, withLabel: Defaults.keyChainService, accessGroup: Defaults.keyChainAccessGroup)
                            try removeCredential(forShare: share, withUsername: lowercasedUsername)
                            Logger.keychain.info("✅ Successfully migrated share credential to correct case")
                        } catch {
                            Logger.keychain.warning("⚠️ Migration failed but password retrieved: \(error.localizedDescription)")
                        }

                        return password
                    }
                }
                return nil
            } else {
                Logger.keychain.error("🔐 Keychain error: \(status, privacy: .public)")
                throw KeychainError.errorWithStatus(status: status)
            }
        } catch let error as KeychainError {
            throw error
        } catch {
            throw KeychainError.errorRetrievingPassword
        }
        return nil // Should not be reached if successful
    }
    
    func retrievePassword(forUsername username: String, andService service: String = Defaults.keyChainService, accessGroup: String? = nil) throws -> String? {
        do {
            // Try with original case first
            var query = try makeQuery(username: username, service: service, accessGroup: accessGroup)
            query[kSecReturnData as String] = kCFBooleanTrue!
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            // Always search both local and iCloud-synced items to preserve compatibility.
            query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
            var ref: AnyObject? = nil

            let status = SecItemCopyMatching(query as CFDictionary, &ref)

            if status == errSecSuccess {
                if let parsedData = ref as? Data {
                    return String(data: parsedData, encoding: .utf8)
                }
            } else if status == errSecItemNotFound {
                // Fallback: Try with lowercase if different from original
                let lowercasedUsername = username.lowercased()
                if lowercasedUsername != username {
                    Logger.keychain.debug("🔍 Entry not found with original case, trying lowercase fallback for: \(username)")

                    var lowercaseQuery = try makeQuery(username: lowercasedUsername, service: service, accessGroup: accessGroup)
                    lowercaseQuery[kSecReturnData as String] = kCFBooleanTrue!
                    lowercaseQuery[kSecMatchLimit as String] = kSecMatchLimitOne
                    lowercaseQuery[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
                    var lowercaseRef: AnyObject? = nil

                    let lowercaseStatus = SecItemCopyMatching(lowercaseQuery as CFDictionary, &lowercaseRef)

                    if lowercaseStatus == errSecSuccess, let parsedData = lowercaseRef as? Data, let password = String(data: parsedData, encoding: .utf8) {
                        Logger.keychain.info("🔄 Found keychain entry with lowercase, migrating: \(lowercasedUsername) -> \(username)")

                        // Migrate: Save with correct case, then delete old entry
                        do {
                            try saveCredential(forUsername: username, andPassword: password, withService: service, andLabel: nil, accessGroup: accessGroup)
                            try removeCredential(forUsername: lowercasedUsername, andService: service, accessGroup: accessGroup)
                            Logger.keychain.info("✅ Successfully migrated keychain entry to correct case")
                        } catch {
                            Logger.keychain.warning("⚠️ Migration failed but password retrieved: \(error.localizedDescription)")
                        }

                        return password
                    }
                }
                return nil
            } else {
                throw KeychainError.errorWithStatus(status: status)
            }
        } catch let error as KeychainError {
            throw error
        } catch {
            throw KeychainError.errorRetrievingPassword
        }
        return nil // Should not be reached if successful
    }
    
    /// Returns the account names (e.g. profile UUIDs) of all generic-password items for the given service,
    /// without restricting to a specific access group.
    func retrieveAllAccountNames(forService service: String) -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: kCFBooleanTrue,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
        var ref: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &ref) == errSecSuccess,
              let items = ref as? [[String: Any]] else { return [] }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    func retrieveAllEntries(forService service: String = Defaults.keyChainService, accessGroup: String = Defaults.keyChainAccessGroup) throws -> [(username: String, password: String)] {
        do {
            var query: [String: Any?] = [kSecClass as String: kSecClassGenericPassword,
                                         kSecAttrService as String: service,
                                         kSecAttrAccessGroup as String: accessGroup,
                                         kSecReturnData as String: kCFBooleanTrue!,
                                         kSecMatchLimit as String: kSecMatchLimitAll,
                                         kSecReturnAttributes as String: kCFBooleanTrue
            ]
            // Always search both local and iCloud-synced items to preserve compatibility.
            query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
            
            var ref: AnyObject? = nil
            
            let status = SecItemCopyMatching(query as CFDictionary, &ref)
            
            guard status == errSecItemNotFound || status == errSecSuccess else {
                throw KeychainError.errorWithStatus(status: status)
            }
            
            guard status != errSecItemNotFound else {
                return []
            }
            
            guard let dictArray = ref as? [[String: Any]] else {
                return []
            }
            let pairs = dictArray.compactMap { $0.accountPasswordPair }
            return pairs
        }
    }

    // MARK: - Existence checks
    
    private func credentialExists(forShare share: URL, withUsername username: String) -> Bool {
        do {
            var query = try makeQuery(share: share, username: username)
            query[kSecReturnData as String] = kCFBooleanFalse
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            // Always search both local and iCloud-synced items to preserve compatibility.
            query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
            
            var ref: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &ref)
            return status == errSecSuccess
        } catch {
            return false
        }
    }
    
    private func credentialExists(forUsername username: String, andService service: String, accessGroup: String? = nil) -> Bool {
        do {
            var query = try makeQuery(username: username, service: service, accessGroup: accessGroup)
            query[kSecReturnData as String] = kCFBooleanFalse
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            // Always search both local and iCloud-synced items to preserve compatibility.
            query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
            
            var ref: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &ref)
            return status == errSecSuccess
        } catch {
            return false
        }
    }
    
    // MARK: - Migration Support
    
    /// Retrieves all entries from FAU shared keychain for Kerberos migration
    /// Uses the same pattern as retrieveAllEntries but with FAU access group
    func retrieveAllFAUSharedCredentials() throws -> [(username: String, password: String)] {
        // Check if FAU access group is configured
        let fauAccessGroup = Defaults.keyChainAccessGroup
        guard !fauAccessGroup.isEmpty else {
            Logger.keychain.info("No FAU access group configured")
            return [] // No FAU access group configured
        }
        
        do {
            // Query for FAU shared credentials with specific service and access group
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "de.fau.rrze.faucredentials", // FAU specific service
                kSecAttrAccessGroup as String: fauAccessGroup,
                kSecReturnData as String: kCFBooleanTrue,
                kSecMatchLimit as String: kSecMatchLimitAll,
                kSecReturnAttributes as String: kCFBooleanTrue,
                kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
            ]
            
            var ref: AnyObject? = nil
            let status = SecItemCopyMatching(query as CFDictionary, &ref)
            
            // Handle no items found gracefully
            if status == errSecItemNotFound {
                Logger.keychain.info("No FAU shared credentials found")
                return []
            }
            
            guard status == errSecSuccess else {
                Logger.keychain.warning("Error retrieving FAU credentials: \(status)")
                return [] // Return empty array instead of throwing
            }
            
            let array = ref as! CFArray
            let dict: [[String: Any]] = array.toSwiftArray()
            let pairs = dict.compactMap { $0.accountPasswordPair }
            
            Logger.keychain.info("Retrieved \(pairs.count) FAU shared credentials")
            return pairs
            
        } catch {
            Logger.keychain.warning("Error in FAU credentials query: \(error)")
            return [] // Return empty array instead of throwing
        }
    }
}


// MARK: - Helper extensions to extract data from CFArray and Dictionaries
extension CFArray {
  func toSwiftArray<T>() -> [T] {
    let array = Array<AnyObject>(_immutableCocoaArray: self)
    return array.compactMap { $0 as? T }
  }
    // MARK: - OSStatus helper
    
    func describe(status: OSStatus) -> String {
        if let message = SecCopyErrorMessageString(status, nil) as String? {
            return "\(status) (\(message))"
        } else {
            return "\(status)"
        }
    }
}

// MARK: - Helper extenstion to retrieve username - password pair form dictionary
extension Dictionary where Key == String, Value == Any {
  var accountPasswordPair: (username: String, password: String)? {

    guard
      let username = self[kSecAttrAccount as String] as? String,
      let passwordData = self[kSecValueData as String] as? Data,
      let password = String(data: passwordData, encoding: .utf8)
      else {
        return nil
    }
    return (username, password)
  }
}

