//
//  PasswordManager.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 20.11.23.
//  Copyright © 2023 Regionales Rechenzentrum Erlangen. All rights reserved.
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
/// kSecAttrLabel -> the name of the keychain entry, shown as "Name:" in Schlüsselbundverwaltung
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

enum KeychainError: Error {
    case noPassword
    case malformedShare
    case unexpectedPasswordData
    case undefinedError
    case errorRemovingEntry
    case errorRetrievingPassword
    case errorWithStatus(status: OSStatus)
}

class PasswordManager: NSObject {
    /// function to create a query to use with keychain
    /// - Parameter forShare: ``String`` containing the URL of a network share
    /// - Parameter withUsername: ``String`` contining the username to connect the network share
    /// - Parameter andPassword: ``String`` containing the password for username
    /// - Parameter service: ``String?`` optional string containing keychain service name
    /// - Parameter accessGroup: ``String?`` optional string with access group to keychain entry
    /// - Parameter comment: ``String?`` optional string with a comment to the keychain entry
    func makeQuery(share shareURL: URL, username: String, service: String? = nil, accessGroup: String? = nil, comment: String? = nil) throws -> [String: Any]  {
        let host = shareURL.host
        let path = shareURL.lastPathComponent
        let urlScheme = shareURL.scheme

        var query: [String: Any] = [kSecClass as String: kSecClassInternetPassword,
                                    kSecAttrAccount as String: username,
                                    kSecAttrServer as String: host as Any,
                                    kSecAttrPath as String: path,
                                    kSecAttrLabel as String: host as Any,
                                    kSecAttrSynchronizable as String: UserDefaults.standard.bool(forKey: Settings.keychainiCloudSync)
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
    /// - Parameter label: ``String`` string containing keychain label name
    /// - Parameter withUsername: ``String`` contining the username to connect the network share
    /// - Parameter andPassword: ``String`` containing the password for username
    /// - Parameter accessGroup: ``String?`` optional string with access group to keychain entry
    /// - Parameter comment: ``String?`` optional string with a comment to the keychain entry
    func makeQuery(label: String, username: String, accessGroup: String? = nil, comment: String? = nil) throws -> [String: Any]  {
        var query: [String: Any] = [kSecClass as String: kSecClassInternetPassword,
                                    kSecAttrAccount as String: username,
                                    kSecAttrLabel as String: label]
        if let kcComment = comment {
            query[kSecAttrComment as String] = kcComment
        }
        if let kcAccessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = kcAccessGroup
        }
        return query
    }
    
    /// store a new keychain entry. An existing entry will be overwritten
    /// - Parameter forShare: ``String`` containing the URL of a network share
    /// - Parameter withUsername: ``String`` contining the username to connect the network share
    /// - Parameter andPassword: ``String`` containing the password for username
    /// - Parameter withService: ``String?`` optional string containing keychain service name
    /// - Parameter accessGroup: ``String?`` optional string with access group to keychain entry
    /// - Parameter comment: ``String?`` optional string with a comment to the keychain entry
    func saveCredential(forShare share: URL, withUsername username: String, andPassword password: String, withService service: String? = nil, accessGroup: String? = nil, comment: String? = nil) throws {
        do {
            var query = try makeQuery(share: share, username: username, service: service, accessGroup: accessGroup, comment: comment)
            query[kSecValueData as String] = password.data(using: String.Encoding.utf8)!
            /// Delete existing entry (if applicable)
            SecItemDelete(query as CFDictionary)
            
            let status = SecItemAdd(query as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw KeychainError.errorWithStatus(status: status)
            }
        } catch {
            throw KeychainError.undefinedError
        }
    }
    
    /// store a new keychain entry. An existing entry will be overwritten
    /// - Parameter forUsername: ``String`` contining the username to connect the network share
    /// - Parameter andPassword: ``String`` containing the password for username
    /// - Parameter accessGroup: ``String?`` optional string with access group to keychain entry
    /// - Parameter comment: ``String?`` optional string with a comment to the keychain entry
    func saveCredential(forUsername username: String, andPassword password: String, accessGroup: String? = nil, comment: String? = nil) throws {
        do {
            var query = try makeQuery(label: FAU.keyChainService, username: username, accessGroup: FAU.keyChainAccessGroup)
            query[kSecValueData as String] = password.data(using: String.Encoding.utf8)!
            /// Delete existing entry (if applicable)
            SecItemDelete(query as CFDictionary)
            
            let status = SecItemAdd(query as CFDictionary, nil)
            guard status == errSecSuccess else {
                throw KeychainError.errorWithStatus(status: status)
            }
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
            
            // try to get the password for share and username. If none is returned, the
            // entry does not exist and there is no need to remove an entry -> return
            do {
                _ = try retrievePassword(forShare: share, withUsername: username)
            } catch {
                return
            }
            
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess else {
                throw KeychainError.errorRemovingEntry
            }
        } catch {
            throw KeychainError.errorRemovingEntry
        }
    }
    
    /// delete a specific keychain entry defined by
    /// - Parameter forhUsername: ``username`` login for share
    func removeCredential(forUsername username: String) throws {
        do {
            let query = try makeQuery(label: FAU.keyChainService, username: username, accessGroup: FAU.keyChainAccessGroup)
            
            // try to get the password for share and username. If none is returned, the
            // entry does not exist and there is no need to remove an entry -> return
            do {
                _ = try retrievePassword(forUsername: username)
            } catch {
                return
            }
            
            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess else {
                throw KeychainError.errorRemovingEntry
            }
        } catch {
            throw KeychainError.errorRemovingEntry
        }
    }
    
    /// retrieve a password from the keychain
    /// - Parameter forShare: ``share`` name of the share
    /// - Parameter withUsername: ``username`` login for share
    func retrievePassword(forShare share: URL, withUsername username: String) throws -> String? {
        do {
            var query = try makeQuery(share: share, username: username)
            query[kSecReturnData as String] = kCFBooleanTrue!
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var ref: AnyObject? = nil
            
            let status = SecItemCopyMatching(query as CFDictionary, &ref)
            guard status == errSecSuccess else {
                throw KeychainError.errorRetrievingPassword
            }
            
            if let parsedData = ref as? Data {
                return String(data: parsedData, encoding: .utf8) ?? ""
            }
        } catch {
            throw KeychainError.errorRetrievingPassword
        }
        return nil
    }
    
    /// retrieve a password from the keychain
    /// - Parameter forUsername: ``username`` login for share
    func retrievePassword(forUsername username: String) throws -> String? {
        do {
            var query = try makeQuery(label: FAU.keyChainService, username: username, accessGroup: FAU.keyChainAccessGroup)
            query[kSecReturnData as String] = kCFBooleanTrue!
            query[kSecMatchLimit as String] = kSecMatchLimitOne
            var ref: AnyObject? = nil
            
            let status = SecItemCopyMatching(query as CFDictionary, &ref)
            guard status == errSecSuccess else {
                throw KeychainError.errorRetrievingPassword
            }
            
            if let parsedData = ref as? Data {
                return String(data: parsedData, encoding: .utf8) ?? ""
            }
        } catch {
            throw KeychainError.errorRetrievingPassword
        }
        return nil
    }
}
