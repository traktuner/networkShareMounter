//
//  AutomaticSignIn.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 15.12.23.
//  Copyright © 2020 Orchard & Grove, Inc. All rights reserved.
//  Copyright © 2023 RRZE. All rights reserved.
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
    
    var prefs = PreferenceManager()
//    var dogeAccounts = [DogeAccount]()
    var workers = [AutomaticSignInWorker]()
    
    init() {
        signInAllAccounts()
    }
    
    private func signInAllAccounts() {
        let klist = KlistUtil()
        let princs = klist.klist().map({ $0.principal })
        let defaultPrinc = klist.defaultPrincipal
        self.workers.removeAll()
        
        // sign in only for defaultPrinc-Account if singleUserMode == true or only one account exists, walk through alle accounts
        // if singleUserMode == false and more than 1 account exists
        for account in AccountsManager.shared.accounts {
            if !prefs.bool(for: .singleUserMode) || account.upn == defaultPrinc || AccountsManager.shared.accounts.count == 1 {
                Task {
                    let worker = AutomaticSignInWorker(account: account)
                    await worker.checkUser()
                    self.workers.append(worker)
                }
            }
        }

        cliTask("kswitch -p \(defaultPrinc ?? "")")
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
        let princs = klist.klist().map({ $0.principal })
        
        resolver.resolve(query: "_ldap._tcp." + domain.lowercased(), completion: { i in
            Logger.automaticSignIn.info("SRV Response for: _ldap._tcp.\(self.domain, privacy: .public)")
            switch i {
            case .success(let result):
                if !result.SRVRecords.isEmpty {
                    if princs.contains(where: { $0.lowercased() == self.account.upn }) {
                        self.getUserInfo()
                    } else {
                        self.auth()
                    }
                } else {
                    Logger.automaticSignIn.info("No RSV records found.")
                }
            case .failure(let error):
                Logger.automaticSignIn.error("No DNS results for domain \(self.domain, privacy: .public), unable to automatically login. Error: \(error, privacy: .public)")
            }
        })
    }
    
    func auth() {
        let keyUtil = KeychainManager()
        do {
            print(self.account.upn.lowercaseDomain())
            if let pass = try keyUtil.retrievePassword(forUsername: self.account.upn.lowercaseDomain(), andService: Defaults.keyChainService) {
                session.userPass = pass
                session.delegate = self
                session.authenticate()
                self.account.keychain = true
            }
        } catch {
            self.account.keychain = false
            NotificationCenter.default.post(name: .nsmNotification, object: nil, userInfo: ["AuthError": MounterError.authenticationError])
        }
    }
    
    func getUserInfo() {
        cliTask("kswitch -p \(self.session.userPrincipal )")
        session.delegate = self
        session.userInfo()
    }
    
    func dogeADAuthenticationSucceded() {
        Logger.automaticSignIn.info("Auth succeded for user: \(self.account.upn, privacy: .public)")
        cliTask("kswitch -p \(self.session.userPrincipal )")
        session.userInfo()
    }
    
    func dogeADAuthenticationFailed(error: dogeADSessionError, description: String) {
        Logger.automaticSignIn.info("Auth failed for user: \(self.account.upn, privacy: .public), Error: \(description, privacy: .public)")
        switch error {
        case .AuthenticationFailure, .PasswordExpired:
            Logger.automaticSignIn.info("Removing bad password from keychain")
            let keyUtil = KeychainManager()
            do {
                try keyUtil.removeCredential(forUsername: self.account.upn)
                Logger.automaticSignIn.info("Successfully removed keychain item")
            } catch {
                Logger.automaticSignIn.info("Failed to remove keychain item for username \(self.account.upn)")
            }
        default:
            break
        }
    }
    
    func dogeADUserInformation(user: ADUserRecord) {
        Logger.automaticSignIn.debug("User info: \(user.userPrincipal)")
        prefs.setADUserInfo(user: user)
    }
}
