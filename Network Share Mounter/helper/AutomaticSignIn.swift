//
//  AutomaticSignIn.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 15.12.23.
//  Copyright © 2020 Orchard & Grove, Inc. All rights reserved.
//  Copyright © 2024 RRZE. All rights reserved.
//

import Foundation
import OSLog
import dogeADAuth

public struct Doge_SessionUserObject {
    var userPrincipal: String
    var session: dogeADSession
    var aging: Bool
    var expiration: Date?
    var daysToGo: Int?
    var userInfo: ADUserRecord?
}

class AutomaticSignIn {
    static let shared = AutomaticSignIn()
    
    var prefs = PreferenceManager()
    
    let accountsManager = AccountsManager.shared
    
    private init() {}
    
    func signInAllAccounts() async {
        let klist = KlistUtil()
        _ = await klist.klist().map({ $0.principal })
        let defaultPrinc = await klist.defaultPrincipal
        
        // sign in only for defaultPrinc-Account if singleUserMode == true or only one account exists, walk through all accounts
        // if singleUserMode == false and more than 1 account exists
        let accounts = await accountsManager.accounts
        let accountsCount = accounts.count
        for account in accounts {
            if !prefs.bool(for: .singleUserMode) || account.upn == defaultPrinc || accountsCount == 1 {
                let worker = AutomaticSignInWorker(account: account)
                await worker.checkUser()
            }
        }
        if let defPrinc = defaultPrinc {
            _ = try? await cliTask("kswitch -p \(defPrinc)")
        }
    }
}

class AutomaticSignInWorker: dogeADUserSessionDelegate {
    
    var prefs = PreferenceManager()
    var account: DogeAccount
    var session: dogeADSession
    var resolver = SRVResolver()
    let domain: String
    
    init(account: DogeAccount) {
        self.account = account
        domain = account.upn.userDomain() ?? ""
        self.session = dogeADSession(domain: domain, user: account.upn.user())
        self.session.setupSessionFromPrefs(prefs: prefs)
    }
    
    func checkUser() async {
        let klist = KlistUtil()
        let princs = await klist.klist().map({ $0.principal })
        
        await withCheckedContinuation { continuation in
            resolver.resolve(query: "_ldap._tcp." + domain.lowercased()) { result in
                Logger.automaticSignIn.info("SRV Response for: _ldap._tcp.\(self.domain, privacy: .public)")
                switch result {
                case .success(let records):
                    if !records.SRVRecords.isEmpty {
                        if princs.contains(where: { $0.lowercased() == self.account.upn }) {
                            Task {
                                await self.getUserInfo()
                            }
                        }
                    } else {
                        Logger.automaticSignIn.info("No SRV records found.")
                    }
                case .failure(let error):
                    Logger.automaticSignIn.error("No DNS results for domain \(self.domain, privacy: .public), unable to automatically login. Error: \(error, privacy: .public)")
                }
                continuation.resume()
            }
        }
        
        await auth()
    }
    
    func auth() async {
        let keyUtil = KeychainManager()
        do {
            if let pass = try keyUtil.retrievePassword(forUsername: account.upn.lowercaseDomain(), andService: Defaults.keyChainService) {
                account.hasKeychainEntry = true
                session.userPass = pass
                session.delegate = self
                await session.authenticate()
            }
        } catch {
            account.hasKeychainEntry = false
            NotificationCenter.default.post(name: .nsmNotification, object: nil, userInfo: ["KrbAuthError": MounterError.authenticationError])
        }
    }
    
    func getUserInfo() async {
        _ = try? await cliTask("kswitch -p \(session.userPrincipal)")
        session.delegate = self
        await session.userInfo()
    }
    
    func dogeADAuthenticationSucceded() async {
        Logger.automaticSignIn.info("Auth succeeded for user: \(self.account.upn, privacy: .public)")
        _ = try? await cliTask("kswitch -p \(session.userPrincipal)")
        NotificationCenter.default.post(name: .nsmNotification, object: nil, userInfo: ["krbAuthenticated": MounterError.krbAuthSuccessful])
        await session.userInfo()
    }
    
    func dogeADAuthenticationFailed(error: dogeADSessionError, description: String) {
        Logger.automaticSignIn.info("Auth failed for user: \(self.account.upn, privacy: .public), Error: \(description, privacy: .public)")
        switch error {
        case .AuthenticationFailure, .PasswordExpired:
            NotificationCenter.default.post(name: .nsmNotification, object: nil, userInfo: ["KrbAuthError": MounterError.krbAuthenticationError])
            Logger.automaticSignIn.info("Removing bad password from keychain")
            let keyUtil = KeychainManager()
            do {
                try keyUtil.removeCredential(forUsername: account.upn)
                Logger.automaticSignIn.info("Successfully removed keychain item")
            } catch {
                Logger.automaticSignIn.info("Failed to remove keychain item for username \(self.account.upn)")
            }
        case .OffDomain:
            Logger.automaticSignIn.info("Outside Kerberos realm network")
            NotificationCenter.default.post(name: .nsmNotification, object: nil, userInfo: ["krbOffDomain": MounterError.offDomain])
        default:
            break
        }
    }
    
    func dogeADUserInformation(user: ADUserRecord) {
        Logger.automaticSignIn.debug("User info: \(user.userPrincipal)")
        prefs.setADUserInfo(user: user)
    }
}
