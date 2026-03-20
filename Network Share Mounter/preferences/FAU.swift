//
//  FAUconstants.swift
//  Network Share Mounter
//
//  Created by Gregor Longariva on 24.01.23.
//  Copyright © 2024 RRZE. All rights reserved.
//

import Foundation
import OSLog
import dogeADAuth

/// Constants specific to FAU (Friedrich-Alexander-Universität) authentication
struct FAU {
    /// Service name for FAU IdM keychain entries
    static let keyChainServiceFAUIdM = "FAU IdM account"
    
    /// Comment for keychain entries
    static let keyChainComment = "FAU IdM credentials for Kerberos ticket management"
    
    /// Kerberos realm for FAU (intentionally lowercase)
    static let kerberosRealm = "fauad.fau.de"
    
    /// Logo image name for authentication dialogs
    static let authenticationDialogImage = "FAUMac_Logo_512"
}
