//
//  NoMADSession.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 15.12.23.
//  Copyright © 2020 Orchard & Grove, Inc. All rights reserved.
//  Copyright © 2023 RRZE. All rights reserved.
//

import Foundation
import dogeADAuth

class DogeSessionManager {
   
    var session: dogeADSession?
    
    init(domain: String, user: String) {
        session = dogeADSession.init(domain: domain, user: user)
    }
}

extension DogeSessionManager: dogeADUserSessionDelegate {

    func dogeADAuthenticationSucceded() {
        session?.userInfo()
    }
    
    func dogeADAuthenticationFailed(error: dogeADSessionError, description: String) {
    }
    
    func dogeADUserInformation(user: ADUserRecord) {

    }
    
    
}
//
//  DogeSession.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 26.12.23.
//  Copyright © 2023 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation
