//
//  DomainManager.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 15.12.23.
//  Copyright © 2021 Orchard & Grove, Inc. All rights reserved.
//  Copyright © 2023 RRZE. All rights reserved.
//

import Foundation

class DomainManager {
    
    static let shared = DomainManager()
    var domains = [String:Bool]()
    
    init() {
        let accountDomains = AccountsManager.shared.returnAllDomains()
        for domain in accountDomains {
            domains[domain] = false
        }
        AccountsManager.shared.delegates.append(self)
    }
    
    func checkDomains() {
        for domain in domains {
            let resolver = SRVResolver()
            resolver.resolve(query: domain.key, completion: { result in
                switch result {
                case .success(let records):
                    if records.SRVRecords.count > 0 {
                        self.domains[domain.key] = true
                    } else {
                        self.domains[domain.key] = false
                    }
                case .failure( _):
                    self.domains[domain.key] = false
                }
            })
        }
    }
}

extension DomainManager: AccountUpdate {
    func updateAccounts(accounts: [DogeAccount]) {
        let accountDomains = AccountsManager.shared.returnAllDomains()
        domains.removeAll()
        for domain in accountDomains {
            domains[domain] = false
        }
    }
}
