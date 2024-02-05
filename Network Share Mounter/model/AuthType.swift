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
}
