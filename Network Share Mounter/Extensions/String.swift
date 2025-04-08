//
//  String.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 15.12.23.
//  Copyright © 2020 Orchard & Grove, Inc. All rights reserved.
//  Copyright © 2025 RRZE. All rights reserved.
//

import Foundation

extension String {
    /// Returns a URL by appending the specified path component to self
    /// - Parameter string: A string containing the part of the path to be appended
    /// - Returns: A string containing a path URL
    func appendingPathComponent(_ string: String) -> String {
        return URL(fileURLWithPath: self).appendingPathComponent(string).path
    }
    
    /// Checks if the string itself is a valid URL
    /// - Returns: `true` if the string is a valid URL, `false` otherwise
    var isValidURL: Bool {
        // Verwende do-catch statt force-try
        do {
            let detector = try NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
            if let match = detector.firstMatch(in: self, options: [], range: NSRange(location: 0, length: self.utf16.count)) {
                // Es ist ein Link, wenn der Match den gesamten String abdeckt
                return match.range.length == self.utf16.count
            }
        } catch {
            // Logger könnte hier verwendet werden
            print("Fehler beim Erstellen des NSDataDetector: \(error)")
        }
        return false
    }
    
    /// Extracts the domain part from an email address or UPN
    /// - Returns: The domain part of the string if it contains '@', `nil` otherwise
    func userDomain() -> String? {
        if self.components(separatedBy: "@").count > 1 {
            return self.components(separatedBy: "@").last
        }
        return nil
    }
    
    /// Extracts the username part from an email address or UPN
    /// - Returns: The username part of the string before '@', or the entire string if no '@' is found
    func user() -> String {
        self.components(separatedBy: "@").first ?? ""
    }
    
    /// Placeholder for translation functionality
    /// - Returns: The string itself (currently no translation is performed)
    var translate: String {
        //return Localizator.sharedInstance.translate(self)
        self
    }
    
    /// Removes leading and trailing whitespace from the string
    /// - Returns: A new string with whitespace removed from both ends
    func trim() -> String {
        return self.trimmingCharacters(in: CharacterSet.whitespaces)
    }
    
    /// Checks if the string contains another string, ignoring case
    /// - Parameter find: The string to search for
    /// - Returns: `true` if the string contains the search string (ignoring case), `false` otherwise
    func containsIgnoringCase(_ find: String) -> Bool {
        return self.range(of: find, options: NSString.CompareOptions.caseInsensitive) != nil
    }
    
    /// Percent-encodes the string for use in a URL path component
    /// - Returns: The percent-encoded string, or `nil` if encoding fails
    func safeURLPath() -> String? {
        let allowedCharacters = CharacterSet(bitmapRepresentation: CharacterSet.urlPathAllowed.bitmapRepresentation)
        return addingPercentEncoding(withAllowedCharacters: allowedCharacters)
    }
    
    /// Percent-encodes the string for use in a URL query component
    /// - Returns: The percent-encoded string, or `nil` if encoding fails
    func safeURLQuery() -> String? {
        let allowedCharacters = CharacterSet(bitmapRepresentation: CharacterSet.urlQueryAllowed.bitmapRepresentation)
        return addingPercentEncoding(withAllowedCharacters: allowedCharacters)
    }

    /// Safely adds percent encoding to a string using a copy of the character set
    /// to workaround a Swift issue with urlQueryAllowed and similar character sets
    /// - Parameter allowedCharacters: The character set that shouldn't be percent-encoded
    /// - Returns: The percent-encoded string, or `nil` if encoding fails
    func safeAddingPercentEncoding(withAllowedCharacters allowedCharacters: CharacterSet) -> String? {
        // Using a copy to workaround magic: https://stackoverflow.com/q/44754996/1033581
        let allowedCharacters = CharacterSet(bitmapRepresentation: allowedCharacters.bitmapRepresentation)
        return addingPercentEncoding(withAllowedCharacters: allowedCharacters)
    }
    
    /// Replaces variable placeholders in the string with actual values from user defaults
    /// 
    /// Supported placeholders:
    /// - `<<domain>>`: AD domain
    /// - `<<fullname>>`: User's full name
    /// - `<<serial>>`: Device serial number
    /// - `<<shortname>>`: User's short name
    /// - `<<upn>>`: User's UPN
    /// - `<<email>>`: User's email
    /// - `<<domaincontroller>>`: Current domain controller
    /// - `<<noACL>>` and `<<proxy>>`: Removed (replaced with empty string)
    ///
    /// - Parameter encoding: Whether to encode spaces as %20
    /// - Returns: The string with variables replaced with their values
    func variableSwap(_ encoding: Bool = true) -> String {
        var cleanString = self
        
        // Hole Werte aus UserDefaults
        let defaults = UserDefaults.standard
        let domain = defaults.string(forKey: PreferenceKeys.aDDomain.rawValue) ?? ""
        let fullName = defaults.string(forKey: PreferenceKeys.displayName.rawValue)?.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) ?? ""
        let serial = getSerial().addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) ?? ""
        let shortName = defaults.string(forKey: PreferenceKeys.userShortName.rawValue) ?? ""
        let upn = defaults.string(forKey: PreferenceKeys.userUPN.rawValue) ?? ""
        let email = defaults.string(forKey: PreferenceKeys.userEmail.rawValue) ?? ""
        let currentDC = defaults.string(forKey: PreferenceKeys.aDDomainController.rawValue) ?? "NONE"
        
        // Kodiere Leerzeichen wenn nötig
        if encoding {
            cleanString = cleanString.replacingOccurrences(of: " ", with: "%20")
        }
        
        // Ersetze alle Platzhalter
        let replacements: [String: String] = [
            "<<domain>>": domain,
            "<<fullname>>": fullName,
            "<<serial>>": serial,
            "<<shortname>>": shortName,
            "<<upn>>": upn,
            "<<email>>": email,
            "<<noACL>>": "",
            "<<domaincontroller>>": currentDC,
            "<<proxy>>": ""
        ]
        
        for (placeholder, value) in replacements {
            cleanString = cleanString.replacingOccurrences(of: placeholder, with: value)
        }
        
        return cleanString
    }
    
    /// Removes the domain part from an email address or UPN
    /// - Returns: The part of the string before '@', or the entire string if no '@' is found
    func removeDomain() -> String {
        if self.contains("@") {
            let split = self.components(separatedBy: "@")
            return split[0]
        } else {
            return self
        }
    }
    
    /// Appends a domain to the string
    /// - Parameter domain: The domain to append (without '@')
    mutating func appendDomain(domain: String) {
        self = self.appending("@" + domain)
    }
    
    /// Returns a string with the domain part converted to lowercase
    /// - Returns: A string with the domain part (after '@') in lowercase
    func lowercaseDomain() -> String {
        if self.contains("@") {
            let split = self.components(separatedBy: "@")
            return split[0] + "@" + split[1].lowercased()
        } else {
            return self
        }
    }
    
    /// Returns a string with the domain part converted to uppercase
    /// - Returns: A string with the domain part (after '@') in uppercase
    func uppercaseDomain() -> String {
        if self.contains("@") {
            let split = self.components(separatedBy: "@")
            return split[0] + "@" + split[1].uppercased()
        } else {
            return self
        }
    }
}
