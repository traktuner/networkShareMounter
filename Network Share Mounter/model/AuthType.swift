//
//  AuthType.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 04.02.24.
//  Copyright © 2024 Regionales Rechenzentrum Erlangen. All rights reserved.
//

/// defines authentication type to mount a share
/// - Parameter krb: kerberos authentication
/// - Parameter pwd: username/password authentication
enum AuthType: String {
    case krb = "krb"
    case pwd = "pwd"
    case guest = "guest"

    /// Custom RawRepresentable initializer to be tolerant with legacy/raw string values.
    ///
    /// Background: In older docs/configs we used the string value "password" for the
    /// username/password authentication case, but the actual raw value in code is "pwd".
    /// To keep backward compatibility (and avoid crashes/decoding failures), we map
    /// the legacy value "password" to `.pwd` here. This lets existing persisted data,
    /// configs, or code that still uses "password" continue to work without changes.
    init?(rawValue: String) {
        switch rawValue {
        case "password":
            self = .pwd
        case "pwd":
            self = .pwd
        case "krb":
            self = .krb
        case "guest":
            self = .guest
        default:
            return nil
        }
    }
}

