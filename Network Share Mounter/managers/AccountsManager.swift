//
//  AccountsManager.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 15.12.23.
//  Copyright © 2021 Orchard & Grove, Inc. All rights reserved.
//  Copyright © 2024 RRZE. All rights reserved.
//

import Foundation

protocol AccountUpdate {
    func updateAccounts(accounts: [DogeAccount])
}

class AccountsManager {
    
    var prefs = PreferenceManager()
    var accounts = [DogeAccount]()
    var delegates = [AccountUpdate]()
    
    static let shared = AccountsManager()
    
    init() {
        // perform some FAU tasks
        if prefs.string(for: .kerberosRealm)?.lowercased() == FAU.kerberosRealm.lowercased() {
            if !prefs.bool(for: .keyChainPrefixManagerMigration) {
                let migrator = Migrator(accountsManager: self)
                migrator.migrate()
            }
        }
        loadAccounts()
    }
    
    private func loadAccounts() {
        let decoder = PropertyListDecoder.init()
        if let accountsData = prefs.data(for: .accounts),
           let accountsList = try? decoder.decode(DogeAccounts.self, from: accountsData) {
            accounts = accountsList.accounts
        }
        updateDelegates()
    }
    
    func saveAccounts() {
        let encoder = PropertyListEncoder.init()
        if let accountData = try? encoder.encode(DogeAccounts.init(accounts: accounts))  {
            prefs.set(for: .accounts, value: accountData)
            prefs.defaults.setValue(accountData, forKey: PreferenceKeys.accounts.rawValue)
        }
        updateDelegates()
    }
    
    func addAccount(account: DogeAccount) {
        accounts.append(account)
        saveAccounts()
    }
    
    func deleteAccount(account: DogeAccount) {
        accounts.removeAll() { $0 == account }
        saveAccounts()
    }
    
    func accountForPrincipal(principal: String) -> DogeAccount? {
        
        for account in accounts {
            if account.upn.lowercased() == principal.lowercased() {
                return account
            }
        }
        
        return nil
    }
    
    func returnAllDomains() -> [String] {
        var domains = [String]()
        
        for account in accounts {
            if let userDomain = account.upn.userDomain(),
               !domains.contains(userDomain){
                domains.append(userDomain)
            }
        }
        
        return domains
    }
    
    private func updateDelegates() {
        for delegate in delegates {
            delegate.updateAccounts(accounts: accounts)
        }
    }
}
