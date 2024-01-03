//
//  String.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 15.12.23.
//  Copyright © 2020 Orchard & Grove, Inc. All rights reserved.
//  Copyright © 2023 RRZE. All rights reserved.
//

import Foundation

extension String {
    /// Returns a URL by appending the specified path component to self
    /// - Parameter _: A string containing the part of the path to be appended
    /// - Returns: A string containing a path URL
    func appendingPathComponent(_ string: String) -> String {
        return URL(fileURLWithPath: self).appendingPathComponent(string).path
    }
    
    /// Extension for ``String`` to check if the string itself is a valid URL
    /// - Returns: true if the string is a valid URL
    var isValidURL: Bool {
        // swiftlint:disable force_try
        let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        // swiftlint:denable force_try
        if let match = detector.firstMatch(in: self, options: [], range: NSRange(location: 0, length: self.utf16.count)) {
            // it is a link, if the match covers the whole string
            return match.range.length == self.utf16.count
        } else {
            return false
        }
    }
    
    func userDomain() -> String? {
        if self.components(separatedBy: "@").count > 1 {
            return self.components(separatedBy: "@").last
        }
        return nil
    }
    
    func user() -> String {
        self.components(separatedBy: "@").first ?? ""
    }
    
    var translate: String {
        //return Localizator.sharedInstance.translate(self)
        self
    }
    
    func trim() -> String {
        return self.trimmingCharacters(in: CharacterSet.whitespaces)
    }
    
    func containsIgnoringCase(_ find: String) -> Bool {
        return self.range(of: find, options: NSString.CompareOptions.caseInsensitive) != nil
    }
    
    func safeURLPath() -> String? {
        let allowedCharacters = CharacterSet(bitmapRepresentation: CharacterSet.urlPathAllowed.bitmapRepresentation)
        return addingPercentEncoding(withAllowedCharacters: allowedCharacters)
    }
    
    func safeURLQuery() -> String? {
        let allowedCharacters = CharacterSet(bitmapRepresentation: CharacterSet.urlQueryAllowed.bitmapRepresentation)
        return addingPercentEncoding(withAllowedCharacters: allowedCharacters)
    }

    func safeAddingPercentEncoding(withAllowedCharacters allowedCharacters: CharacterSet) -> String? {
            // using a copy to workaround magic: https://stackoverflow.com/q/44754996/1033581
            let allowedCharacters = CharacterSet(bitmapRepresentation: allowedCharacters.bitmapRepresentation)
            return addingPercentEncoding(withAllowedCharacters: allowedCharacters)
    }
    
    func variableSwap(_ encoding: Bool=true) -> String {
        
        var cleanString = self
        
        let domain = UserDefaults.standard.string(forKey: PreferenceKeys.aDDomain.rawValue) ?? ""
        let fullName = UserDefaults.standard.string(forKey: PreferenceKeys.displayName.rawValue)?.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) ?? ""
        let serial = getSerial().addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) ?? ""
        let shortName = UserDefaults.standard.string(forKey: PreferenceKeys.userShortName.rawValue) ?? ""
        let upn = UserDefaults.standard.string(forKey: PreferenceKeys.userUPN.rawValue) ?? ""
        let email = UserDefaults.standard.string(forKey: PreferenceKeys.userEmail.rawValue) ?? ""
        let currentDC = UserDefaults.standard.string(forKey: PreferenceKeys.aDDomainController.rawValue) ?? "NONE"
        
        if encoding {
            cleanString = cleanString.replacingOccurrences(of: " ", with: "%20") //cleanString.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlHostAllowed) ?? cleanString
        }
        
        cleanString = cleanString.replacingOccurrences(of: "<<domain>>", with: domain)
        cleanString = cleanString.replacingOccurrences(of: "<<fullname>>", with: fullName)
        cleanString = cleanString.replacingOccurrences(of: "<<serial>>", with: serial)
        cleanString = cleanString.replacingOccurrences(of: "<<shortname>>", with: shortName)
        cleanString = cleanString.replacingOccurrences(of: "<<upn>>", with: upn)
        cleanString = cleanString.replacingOccurrences(of: "<<email>>", with: email)
        cleanString = cleanString.replacingOccurrences(of: "<<noACL>>", with: "")
        cleanString = cleanString.replacingOccurrences(of: "<<domaincontroller>>", with: currentDC)

        
        // now to remove any proxy settings
        
        cleanString = cleanString.replacingOccurrences(of: "<<proxy>>", with: "")
        
        return cleanString //.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
        
    }
}
