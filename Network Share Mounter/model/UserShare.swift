//
//  UserShare.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 16.11.23.
//  Copyright © 2023 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation

class UserShare: NSObject {
    @objc dynamic var networkShare: String
    @objc dynamic var authType: Bool
    @objc dynamic var username: String?
    @objc dynamic var password: String?
    @objc dynamic var mountPoint: String?
    @objc dynamic var managed: Bool
    
    init(networkShare: String, authType: Bool, username: String?, password: String?, mountPoint: String?, managed: Bool) {
        self.networkShare = networkShare
        self.authType = authType
        self.username = username
        self.password = password
        self.mountPoint = mountPoint
        self.managed = managed
    }
}
