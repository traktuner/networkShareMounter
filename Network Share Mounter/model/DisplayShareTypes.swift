//
//  DisplayShareTypes.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 22.12.23.
//  Copyright © 2024 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation

///
/// enum containig type of shares to display in the tableView
/// managed: share is managed, whether krb, guest or pwd
/// unmanaged: share is unmanage, whether krb or pwd
/// pwd: share is password authenticated, whether managed or unmanaged
/// krb: share is kerbeors authenticated, whether managed or unmanaged
/// managedPwd: share is managed and password authenticated
/// managedOrPwd: share is managed or password authenticated
enum DisplayShareTypes: String {
    case managed = "managed"
    case unmanaged = "unmanaged"
    case pwd = "pwd"
    case krb = "krb"
    case guest = "guest"
    case managedAndPwd = "managedPwd"
    case managedOrPwd = "managedOrPwd"
    case missingPassword = "missingPassword"
}
