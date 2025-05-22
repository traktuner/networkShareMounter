//
//  AccountsManager.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 15.12.23.
//  Copyright © 2021 Orchard & Grove, Inc. All rights reserved.
//  Copyright © 2024 RRZE. All rights reserved.
//

import Foundation

/// Protocol defining the methods for updating account information.
protocol AccountUpdate: AnyObject {
    func updateAccounts(accounts: [DogeAccount])
}

/// Actor responsible for managing user accounts.
actor AccountsManager {
    var prefs = PreferenceManager()
    var accounts = [DogeAccount]()
    var delegates = [AccountUpdate]()
    
    /// Singleton instance of AccountsManager.
    static let shared = AccountsManager()
    
    private var isInitialized = false
    
    /// Private initializer to enforce singleton pattern.
    private init() {}
    
    /// Initializes the AccountsManager, performing necessary setup tasks.
    func initialize() async {
        guard !isInitialized else { return }
        
        // Load accounts from persistent storage.
        loadAccounts()
        
        isInitialized = true
    }
    
    /// Loads accounts from UserDefaults and updates the internal accounts list.
    private func loadAccounts() {
        let decoder = PropertyListDecoder()
        if let accountsData = prefs.data(for: .accounts),
           let accountsList = try? decoder.decode(DogeAccounts.self, from: accountsData) {
            var uniqueAccounts = [DogeAccount]()
            var processedUPNs = Set<String>()

            // Filter and store unique accounts based on UPN.
            for account in accountsList.accounts {
                let lowercasedUPN = account.upn.lowercased()
                if !lowercasedUPN.starts(with: "@") && !processedUPNs.contains(lowercasedUPN) {
                    uniqueAccounts.append(account)
                    processedUPNs.insert(lowercasedUPN)
                }
            }
            accounts = uniqueAccounts
        }
        
        // Notify delegates about the updated accounts list.
        updateDelegates()
    }
    
    /// Saves the current accounts list to UserDefaults.
    func saveAccounts() {
        let encoder = PropertyListEncoder()
        if let accountData = try? encoder.encode(DogeAccounts(accounts: accounts)) {
            prefs.set(for: .accounts, value: accountData)
        }
        
        // Notify delegates about the updated accounts list.
        updateDelegates()
    }
    
    /// Adds a new account and updates the persistent storage.
    func addAccount(account: DogeAccount) async {
        accounts.append(account)
        saveAccounts()
    }
    
    /// Deletes an existing account and updates the persistent storage.
    func deleteAccount(account: DogeAccount) async {
        accounts.removeAll { $0 == account }
        saveAccounts()
    }
    
    /// Retrieves an account for a given principal.
    func accountForPrincipal(principal: String) -> DogeAccount? {
        for account in accounts {
            if account.upn.lowercased() == principal.lowercased() {
                return account
            }
        }
        return nil
    }
    
    /// Returns a list of all unique domains from the accounts.
    func returnAllDomains() -> [String] {
        var domains = [String]()
        
        for account in accounts {
            if let userDomain = account.upn.userDomain(),
               !domains.contains(userDomain) {
                domains.append(userDomain)
            }
        }
        
        return domains
    }
    
    /// Notifies all registered delegates about account updates.
    private func updateDelegates() {
        for delegate in delegates {
            delegate.updateAccounts(accounts: accounts)
        }
    }
}

extension AccountsManager {
    /// Adds a delegate to receive account updates.
    func addDelegate(delegate: AccountUpdate) {
        delegates.append(delegate)
    }
}
