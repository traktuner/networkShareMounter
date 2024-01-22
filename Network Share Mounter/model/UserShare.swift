//
//  UserShare.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 16.11.23.
//  Copyright © 2024 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation

class UserShare: NSObject {
    @objc dynamic var networkShare: String
    @objc dynamic var authType: String
    @objc dynamic var username: String?
    @objc dynamic var password: String?
    @objc dynamic var mountPoint: String?
    @objc dynamic var managed: Bool
    @objc dynamic var mountStatus: String
    @objc dynamic var mountSymbol: String
    
    init(networkShare: String, authType: String, username: String?, password: String?, mountPoint: String?, managed: Bool, mountStatus: String, mountSymbol: String) {
        self.networkShare = networkShare
        self.authType = authType
        self.username = username
        self.password = password
        self.mountPoint = mountPoint
        self.managed = managed
        self.mountStatus = mountStatus
        self.mountSymbol = mountSymbol
    }
}
