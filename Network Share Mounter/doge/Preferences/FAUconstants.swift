//
//  FAUconstants.swift
//  Network Share Mounter
//
//  Created by Gregor Longariva on 24.01.23.
//  Copyright © 2023 RRZE. All rights reserved.
//

import Foundation

struct FAU {
    static let keyChainService = "FAU IdM account"
    static let keyChainAccessGroup = "C8F68RFW4L.de.fau.rrze.faucredentials"
    static let keyChainComment = "FAU IdM credentials for Kerberos ticket management"
}

extension String {
    func removeDomain() -> String {
        if self.contains("@") {
            let split = self.components(separatedBy: "@")
            return split[0]
        } else {
            return self
        }
    }
    
    mutating func appendDomain(domain: String) {
        self = self.appending("@" + domain)
    }
}
