//
//  Account.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 15.12.23.
//  Copyright © 2020 Orchard & Grove, Inc. All rights reserved.
//  Copyright © 2024 RRZE. All rights reserved.
//

import Foundation

struct DogeAccount: Codable, Equatable {
    var displayName: String
    var upn: String
    var hasKeychainEntry: Bool? = nil
}

struct DogeAccounts: Codable {
    var accounts: [DogeAccount]
}
