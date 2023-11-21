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
    case errorWithStatus(status: OSStatus)
}

class PasswordManager: NSObject {
    /// function to store a new keychain entry. An existing entry will be overwritten
    /// - Parameter forShare: ``String`` containing the URL of a network share
    /// - Parameter withUsername: ``String`` contining the username to connect the network share
    /// - Parameter andPassword: ``String`` containing the password for username
    func saveCredential(forShare share: String, withUsername username: String, andPpassword password: String) throws {
        guard let shareURL = URL(string: share) else {
            throw KeychainError.malformedShare
        }
        guard let host = shareURL.host else {
            throw KeychainError.malformedShare
        }
        let path = shareURL.lastPathComponent
        /// Description of the CFDictionary for a new keychain entry
        ///
        /// kSecClass -> kSecClassInternetPassword (keychain entry with more than just the password
        /// kSecAttrAccount -> string with username
        /// kSecValueData -> data containing the utf8 encoded password string
        /// kSecAttrServer -> the server URL/IP address part of the share
        /// kSecAttrPath -> the path part of the share
        /// kSecAttrProtocol -> the protocol part of the share
        /// kSecAttrLabel -> the name of the keychain entry, shown as "Name:" in Schlüsselbundverwaltung
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
        var query: [String: Any] = [kSecClass as String: kSecClassInternetPassword,
                                    kSecAttrAccount as String: username,
                                    kSecAttrServer as String: host,
                                    kSecAttrProtocol as String: kSecAttrProtocolSMB,
                                    kSecAttrPath as String: path,
                                    kSecAttrLabel as String: host,
                                    kSecValueData as String: password.data(using: String.Encoding.utf8)!]
        /// Delete existing entry (if applicable)
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.errorWithStatus(status: status)
        }
        
    }

    /// function to delete a specific keychain entry defined by
    /// - Parameter _: hash to reference stored keychain item
    func removeCredential(_ key: String) {
        guard let object = PasswordManager.get(key) else {
            return
        }
        
        var q: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword as String,
            kSecValueData as String: object.data(using: .utf8)!,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: kCFBooleanTrue as Any
        ]
        
        // Delete existing (if applicable)
        let sanityCheck = SecItemDelete(q as CFDictionary)
        if sanityCheck != noErr {
            print("Error deleting keychain item: \(sanityCheck.description)")
        }
    }
    
    /// internal class function to retrieve keychain entry
    /// - Parameter key: hash to reference the stored Keychain item
    /// - Returns: optional String containing
    internal class func get(_ key: String) -> String? {
        var q: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecReturnData as String: kCFBooleanTrue!,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecAttrAccount as String: key,
            kSecUseDataProtectionKeychain as String: kCFBooleanTrue as Any
        ]
        
        q[kSecUseDataProtectionKeychain as String] = kCFBooleanTrue
        var ref: AnyObject? = nil
        
        let sanityCheck = SecItemCopyMatching(q as CFDictionary, &ref)
        if sanityCheck != noErr { return nil }
        
        if let parsedData = ref as? Data {
            return String(data: parsedData, encoding: .utf8)
        }
        return nil
    }
}
