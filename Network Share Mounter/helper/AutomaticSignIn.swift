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
        
        for account in AccountsManager.shared.accounts {
            Task {
                let worker = AutomaticSignInWorker(userName: account.upn)
                await worker.checkUser()
                self.workers.append(worker)
            }
        }
        cliTask("kswitch -p \(defaultPrinc ?? "")")
    }
}

class AutomaticSignInWorker: dogeADUserSessionDelegate {
    
    var prefs = PreferenceManager()
    var userName: String
    var session: dogeADSession
    var resolver = SRVResolver()
    let domain: String
    
    init(userName: String) {
        self.userName = userName
        domain = userName.userDomain() ?? ""
        self.session = dogeADSession(domain: domain, user: userName.user())
        self.session.setupSessionFromPrefs(prefs: prefs)
    }
    
    func checkUser() async {
        
        let klist = KlistUtil()
        let princs = klist.klist().map({ $0.principal })
        
        resolver.resolve(query: "_ldap._tcp." + domain.lowercased(), completion: { i in
            Logger.automaticSignIn.info("SRV Response for: _ldap._tcp.\(self.domain, privacy: .public)")
            switch i {
            case .success(let result):
                if result.SRVRecords.count > 0 {
                    if princs.contains(where: { $0.lowercased() == self.userName }) {
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
        let keyUtil = PasswordManager()
        
        do {
            if let pass = try keyUtil.retrievePassword(forUsername: userName) {
                session.userPass = pass
                session.delegate = self
                session.authenticate()
            }
        } catch {
            Logger.automaticSignIn.error("unable to find keychain item for user: \(self.userName, privacy: .public)")
        }
    }
    
    func getUserInfo() {
        cliTask("kswitch -p \(self.session.userPrincipal )")
        session.delegate = self
        session.userInfo()
    }
    
    func dogeADAuthenticationSucceded() {
        Logger.automaticSignIn.info("Auth succeded for user: \(self.userName, privacy: .public)")
        cliTask("kswitch -p \(self.session.userPrincipal )")
        session.userInfo()
    }
    
    func dogeADAuthenticationFailed(error: dogeADSessionError, description: String) {
        Logger.automaticSignIn.info("Auth failed for user: \(self.userName, privacy: .public), Error: \(description, privacy: .public)")
        switch error {
        case .AuthenticationFailure, .PasswordExpired:
            Logger.automaticSignIn.info("Removing bad password from keychain")
            let keyUtil = PasswordManager()
            do {
                try keyUtil.removeCredential(forUsername: self.userName)
                Logger.automaticSignIn.info("Successfully removed keychain item")
            } catch {
                Logger.automaticSignIn.info("Failed to remove keychain item for username \(self.userName)")
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
