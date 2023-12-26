//
//  PasswordManager.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 20.11.23.
//  Copyright © 2023 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation
import Security

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
    func makeQuery(share shareURL: URL, username: String) throws -> [String: Any]  {
        let host = shareURL.host
        let path = shareURL.lastPathComponent
        let urlScheme = shareURL.scheme
        /// Description of the CFDictionary for a new keychain entry
        ///
        /// kSecClass -> kSecClassInternetPassword (keychain entry with more than just the password
        /// kSecAttrAccount -> string with username
        /// kSecValueData -> data containing the utf8 encoded password string
        /// kSecAttrServer -> the server URL/IP address part of the share
        /// kSecAttrPath -> the path part of the share
        /// kSecAttrProtocol -> the protocol part of the share
        /// kSecAttrLabel -> the name of the keychain entry, shown as "Name:" in Schlüsselbundverwaltung
        /// kSecUseDataProtectionKeychain -> kCFBooleanTrue - a key whose value indicates whether to treat macOS keychain items like iOS keychain items
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
        ///                             kSecAttrProtocol as String: kSecAttrProtocolSMB, kSecAttrProtocolAFP, kSecAttrProtocolHTTPS, kSecAttrProtocolFTP
        ///                             kSecAttrLabel as String: Settings.defaultsDomain,
        ///                             kSecAttrLabel as String: "fileserver.batcave.org",
        ///                             kSecValueData as String: "!'mB4tM4n".data(using: String.Encoding.utf8)!]
        var query: [String: Any] = [kSecClass as String: kSecClassInternetPassword,
                                    kSecAttrAccount as String: username,
                                    kSecAttrServer as String: host as Any,
//                                    kSecAttrProtocol as String: kSecAttrProtocolSMB,
                                    kSecAttrPath as String: path,
                                    kSecAttrLabel as String: host as Any]
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
        return query
    }
    
    /// function to store a new keychain entry. An existing entry will be overwritten
    /// - Parameter forShare: ``String`` containing the URL of a network share
    /// - Parameter withUsername: ``String`` contining the username to connect the network share
    /// - Parameter andPassword: ``String`` containing the password for username
    func saveCredential(forShare share: URL, withUsername username: String, andPpassword password: String) throws {
        do {
            var query = try makeQuery(share: share, username: username)
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

    /// function to delete a specific keychain entry defined by
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
    
    /// function to retrieve a password from the keychain
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
}
