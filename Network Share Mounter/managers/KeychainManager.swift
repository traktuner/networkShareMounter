//
//  PasswordManager.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 20.11.23.
//  Copyright © 2024 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation
import Security

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

enum KeychainError: Error, Equatable {
    case noPassword
    case malformedShare
    case unexpectedPasswordData
    case undefinedError
    case errorRemovingEntry
    case errorRetrievingPassword
    case errorAccessingPassword
    case errorWithStatus(status: OSStatus)
    case itemNotFound
}

class KeychainManager: NSObject {
    var prefs = PreferenceManager()
    
    /// function to create a query to use with keychain
    /// - Parameter forShare: ``String`` containing the URL of a network share
    /// - Parameter withUsername: ``String`` contining the username to connect the network share
    /// - Parameter andPassword: ``String`` containing the password for username
    /// - Parameter service: ``String?`` optional string containing keychain service name
    /// - Parameter accessGroup: ``String?`` optional string with access group to keychain entry
    /// - Parameter comment: ``String?`` optional string with a comment to the keychain entry
    func makeQuery(share shareURL: URL, username: String, service: String? = nil, accessGroup: String? = nil, comment: String? = nil) throws -> [String: Any]  {
        guard let host = shareURL.host else {
            throw KeychainError.malformedShare
        }
        let path = shareURL.lastPathComponent
        let urlScheme = shareURL.scheme

        var query: [String: Any] = [kSecClass as String: kSecClassInternetPassword,
                                    kSecAttrAccount as String: username,
                                    kSecAttrServer as String: host,
                                    kSecAttrPath as String: path,
                                    kSecAttrLabel as String: host,
                                    kSecAttrSynchronizable as String: kCFBooleanFalse as Any
                                    ]
        switch urlScheme {
        case "https":
            query[kSecAttrProtocol as String] = kSecAttrProtocolHTTPS
        case "afp":
            query[kSecAttrProtocol as String] = kSecAttrProtocolAFP
        case "smb":
            query[kSecAttrProtocol as String] = kSecAttrProtocolSMB
        case "cifs":
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
                                    kSecAttrSynchronizable as String: kCFBooleanFalse as Any
                                    ]
        if let kcComment = comment {
            query[kSecAttrComment as String] = kcComment
        }
        if let kcAccessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = kcAccessGroup
        }
        if let kSecAttrLabel = label {
            query[kSecAttrLabel as String] = kSecAttrLabel
        }
        
        return query
    }
    
    /// store a new keychain entry. An existing entry will be overwritten
    /// - Parameter forShare: ``String`` containing the URL of a network share
    /// - Parameter withUsername: ``String`` contining the username to connect the network share
    /// - Parameter andPassword: ``String`` containing the password for username
    /// - Parameter withLabel: ``String?`` optional string containing keychain service name
    /// - Parameter accessGroup: ``String?`` optional string with access group to keychain entry
    /// - Parameter comment: ``String?`` optional string with a comment to the keychain entry
    func saveCredential(forShare share: URL, withUsername username: String, andPassword password: String, withLabel label: String? = Defaults.keyChainService, accessGroup: String? = Defaults.keyChainAccessGroup, comment: String? = nil) throws {
        do {
            var query = try makeQuery(share: share, username: username, accessGroup: accessGroup, comment: comment)
            
            // Ensure that password data can be successfully encoded
            guard let passwordData = password.data(using: String.Encoding.utf8) else {
                throw KeychainError.unexpectedPasswordData
            }
            query[kSecValueData as String] = passwordData
            
            // Delete existing entry (if present)
            // Ignore the return value since it's normal if no entry exists
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
    
    /// store a new keychain entry. An existing entry will be overwritten
    /// - Parameter forUsername: ``String`` contining the username to connect the network share
    /// - Parameter andPassword: ``String`` containing the password for username
    /// - Parameter withService: ``String?`` containing the service for keychain entry, defaults to Defaults.keyChainService
    /// - Parameter andLabel: ``String?`` an optional label for the kexchain entry
    /// - Parameter accessGroup: ``String?`` optional string with access group to keychain entry
    /// - Parameter comment: ``String?`` optional string with a comment to the keychain entry
    func saveCredential(forUsername username: String, andPassword password: String, withService service: String = Defaults.keyChainService, andLabel label: String? = nil, accessGroup: String? = nil, comment: String? = nil) throws {
        do {
            var query = try makeQuery(username: username, service: service, accessGroup: accessGroup, label: label, comment: comment)
            
            // Ensure that password data can be successfully encoded
            guard let passwordData = password.data(using: String.Encoding.utf8) else {
                throw KeychainError.unexpectedPasswordData
            }
            query[kSecValueData as String] = passwordData
            
            // Delete existing entry (if present)
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

    /// delete a specific keychain entry defined by
    /// - Parameter forShare: ``share`` name of the share
    /// - Parameter withUsername: ``username`` login for share
    func removeCredential(forShare share: URL, withUsername username: String) throws {
        do {
            let query = try makeQuery(share: share, username: username)
            let status = SecItemDelete(query as CFDictionary)
            
            // Treat item not found as success for removal
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError.errorWithStatus(status: status)
            }
        } catch let error as KeychainError {
             // Don't re-throw itemNotFound if that was somehow thrown by makeQuery (unlikely)
            if error != .itemNotFound {
                 throw error
            }
        } catch {
            throw KeychainError.errorRemovingEntry
        }
    }
    
    /// delete a specific keychain entry defined by
    /// - Parameter forhUsername: ``String`` login for share
    /// - Parameter andService: ``String`` keychain service
    /// - Parameter accessGroup: ``String`` access group
    func removeCredential(forUsername username: String, andService service: String = Defaults.keyChainService, accessGroup: String = Defaults.keyChainAccessGroup) throws {
        do {
            let query = try makeQuery(username: username, service: service, accessGroup: accessGroup)
            let status = SecItemDelete(query as CFDictionary)
            
            // Treat item not found as success for removal
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError.errorWithStatus(status: status)
            }
        } catch let error as KeychainError {
             // Don't re-throw itemNotFound if that was somehow thrown by makeQuery (unlikely)
            if error != .itemNotFound {
                 throw error
            }
        } catch {
            throw KeychainError.errorRemovingEntry
        }
    }
    
    /// retrieve a password from the keychain
    /// - Parameter forShare: ``URL`` name of the share
    /// - Parameter withUsername: ``String`` login for share
    func retrievePassword(forShare share: URL, withUsername username: String) throws -> String? {
        do {
            var query = try makeQuery(share: share, username: username)
            query[kSecReturnData as String] = kCFBooleanTrue!
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
            
            var ref: AnyObject? = nil
            
            let status = SecItemCopyMatching(query as CFDictionary, &ref)
            
            // Handle item not found specifically
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            
            guard status == errSecSuccess else {
                throw KeychainError.errorWithStatus(status: status)
            }
            
            if let parsedData = ref as? Data {
                return String(data: parsedData, encoding: .utf8) ?? ""
            }
        } catch let error as KeychainError {
            throw error // Re-throw known KeychainErrors
        } catch {
            throw KeychainError.errorRetrievingPassword
        }
        return nil // Should not be reached if successful
    }
    
    /// retrieve a password from the keychain
    /// - Parameter forUsername: ``String`` username
    /// - Parameter andService: ``String`` service, defaults to Defaults.keyChainService
    /// - Parameter accessGroup: ``String`` accessGroup, defaults to Defaults.keyChainAccessGroup
    func retrievePassword(forUsername username: String, andService service: String = Defaults.keyChainService, accessGroup: String? = nil) throws -> String? {
        do {
            var query = try makeQuery(username: username, service: service, accessGroup: accessGroup)
            query[kSecReturnData as String] = kCFBooleanTrue!
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
            var ref: AnyObject? = nil
            
            let status = SecItemCopyMatching(query as CFDictionary, &ref)

            // Handle item not found specifically
            if status == errSecItemNotFound {
                throw KeychainError.itemNotFound
            }
            
            guard status == errSecSuccess else {
                throw KeychainError.errorWithStatus(status: status)
            }
            
            if let parsedData = ref as? Data {
                return String(data: parsedData, encoding: .utf8) ?? ""
            }
        } catch let error as KeychainError {
            throw error // Re-throw known KeychainErrors
        } catch {
            throw KeychainError.errorRetrievingPassword
        }
        return nil // Should not be reached if successful
    }
    
    /// retrieve entries from the keychain
    /// - Parameter forService: ``String`` service
    /// - Parameter accessGroup: ``String`` accessGroup, defaults to Defaults.keyChainAccessGroup
    /// Returns: array of [username: String, password: String]
    ///
    func retrieveAllEntries(forService service: String = Defaults.keyChainService, accessGroup: String = Defaults.keyChainAccessGroup) throws -> [(username: String, password: String)] {
        do {
            let query: [String: Any?] = [kSecClass as String: kSecClassGenericPassword,
                                         kSecAttrService as String: service,
                                         kSecAttrAccessGroup as String: accessGroup,
                                         // return data, not only if there was found something
                                         kSecReturnData as String: kCFBooleanTrue!,
                                         // return all found entries
                                         kSecMatchLimit as String: kSecMatchLimitAll,
                                         // return all attributes
                                         kSecReturnAttributes as String: kCFBooleanTrue,
                                         // ignore if entry is synchornizable with iCloud
                                         kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
            ]
            var ref: AnyObject? = nil
            
            let status = SecItemCopyMatching(query as CFDictionary, &ref)
            
            // throw error of something went wrong
            guard status == errSecItemNotFound || status == errSecSuccess else {
                throw KeychainError.errorWithStatus(status: status)
            }
            
            // return empty array if no matching entries where found
            guard status != errSecItemNotFound else {
                return []
            }
            
            // swiftlint:disable force_cast
            let array = ref as! CFArray
            // swiftlint:enable force_cast
            let dict: [[String: Any]] = array.toSwiftArray()
            let pairs = dict.compactMap { $0.accountPasswordPair }
            return pairs
        }
    }

    /// Checks if a keychain entry exists without retrieving the password
    /// - Parameter forShare: Share URL
    /// - Parameter withUsername: Username
    /// - Returns: true if the entry exists, false otherwise
    private func credentialExists(forShare share: URL, withUsername username: String) -> Bool {
        do {
            var query = try makeQuery(share: share, username: username)
            // Only check if the entry exists without retrieving data
            query[kSecReturnData as String] = kCFBooleanFalse
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
            
            var ref: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &ref)
            return status == errSecSuccess
        } catch {
            return false
        }
    }
    
    /// Checks if a keychain entry exists without retrieving the password
    /// - Parameter forUsername: Username
    /// - Parameter andService: Service name
    /// - Parameter accessGroup: Access group
    /// - Returns: true if the entry exists, false otherwise
    private func credentialExists(forUsername username: String, andService service: String, accessGroup: String? = nil) -> Bool {
        do {
            var query = try makeQuery(username: username, service: service, accessGroup: accessGroup)
            // Only check if the entry exists without retrieving data
            query[kSecReturnData as String] = kCFBooleanFalse
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            query[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
            
            var ref: AnyObject?
            let status = SecItemCopyMatching(query as CFDictionary, &ref)
            return status == errSecSuccess
        } catch {
            return false
        }
    }
}


// MARK: - Helper extensions to extract data from CFArray and Dictionaries
extension CFArray {
  func toSwiftArray<T>() -> [T] {
    let array = Array<AnyObject>(_immutableCocoaArray: self)
    return array.compactMap { $0 as? T }
  }
}

// MARK: - Helper extenstion to retrieve username - password pair form dictionary
extension Dictionary where Key == String, Value == Any {
  var accountPasswordPair: (username: String, password: String)? {

    guard
      let username = self[kSecAttrAccount as String] as? String,
      let password = self[kSecValueData as String] as? Data
      else {
        return nil
    }
    return (username, String(data: password, encoding: .utf8) ?? "")
  }
}
