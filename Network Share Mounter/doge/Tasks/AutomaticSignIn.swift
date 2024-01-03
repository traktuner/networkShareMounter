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
    
    let workQueue = DispatchQueue(label: "de.fau.rrze.doge.kerberos", qos: .userInitiated, attributes: [], autoreleaseFrequency: .inherit, target: nil)
    
    var prefs = PreferenceManager()
    var nomadAccounts = [DogeAccount]()
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
            if account.automatic {
                workQueue.async {
                    let worker = AutomaticSignInWorker(userName: account.upn, pubkeyHash: account.pubkeyHash)
                    worker.checkUser()
                    self.workers.append(worker)
                }
            }
        }
        cliTask("kswitch -p \(defaultPrinc ?? "")")
    }
}

class AutomaticSignInWorker: dogeADUserSessionDelegate {
    
    var prefs = PreferenceManager()
    var userName: String
    var pubkeyHash: String?
    var session: dogeADSession
    var resolver = SRVResolver()
    let domain: String
    
    init(userName: String, pubkeyHash: String?) {
        self.userName = userName
        self.pubkeyHash = pubkeyHash
        domain = userName.userDomain() ?? ""
        self.session = dogeADSession(domain: domain, user: userName.user())
        self.session.setupSessionFromPrefs(prefs: prefs)
    }
    
    func checkUser() {
        
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
                    Logger.networkQueries.info("No RSV records found.")
                }
            case .failure(let error):
                Logger.networkQueries.error("No DNS results for domain \(self.domain, privacy: .public), unable to automatically login. Error: \(error, privacy: .public)")
            }
        })
    }
    
    func auth() {
        let keyUtil = KeychainUtil()
        
        do {
            if pubkeyHash == nil || pubkeyHash == "" {
                try keyUtil.findPassword(userName.lowercased())
                session.userPass = keyUtil.password
                session.delegate = self
                keyUtil.scrub()
                session.authenticate()
            } else {
                if let certs = PKINIT.shared.returnCerts(),
                   let pubKey = self.pubkeyHash {
                    for cert in certs {
                        if cert.pubKeyHash == pubKey {
                            RunLoop.main.perform {
                                if mainMenu.authUI == nil {
                                    mainMenu.authUI = AuthUI()
                                }
                                mainMenu.authUI?.window!.forceToFrontAndFocus(nil)
                            }
                        }
                    }
                }
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
            let keyUtil = KeychainUtil()
            if keyUtil.findAndDelete(self.userName.lowercased()) {
                Logger.automaticSignIn.info("Successfully removed keychain item")
            }
        default:
            break
        }
    }
    
    func dogeADUserInformation(user: ADUserRecord) {
        print("User info: \(user)")
        prefs.setADUserInfo(user: user)
        mainMenu.buildMenu()
    }
}
