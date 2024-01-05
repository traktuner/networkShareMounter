//
//  TicketManager.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 15.12.23.
//  Copyright © 2019 Joel Rennich. All rights reserved.
//  Copyright © 2023 RRZE. All rights reserved.
//

import Foundation
import dogeADAuth
import SystemConfiguration
import OSLog

// Class to manage Kerberos tickets

let tm = TicketManager()
let kerberosQueue = DispatchQueue(label: "de.fau.rrze.nomad.kerberos", attributes: [])
var kKerberosUpdatePending = false
var kKerberosUpdateTimer: Timer?

class TicketManager: dogeADUserSessionDelegate {

    var session: dogeADSession?
    var prefs = PreferenceManager()
    var defaults = UserDefaults.standard

    func setup() {
        // register for notifications

        NotificationCenter.default.addObserver(self, selector: #selector(networkChange), name: NSNotification.Name(rawValue: kUpdateNotificationName), object: nil)
    }

    func getTickets(blocking: Bool=false) {

        session = dogeADSession.init(domain: prefs.string(for: .kerberosRealm) ?? "NONE", user: prefs.string(for: .lastUser)?.components(separatedBy: "@").first ?? "NONE")

        if let customAttributes = prefs.array(for: .customLDAPAttributes) as? [String] {
            session?.customAttributes = customAttributes
        }

        // get the password then get the tickets

        do {
            // FIXME:
//            session?.userPass = try kcUtil.findPassword(prefs.string(for: .lastUser) ?? "NONE")
        } catch {
            return
        }

        session?.delegate = self

        if blocking {
            self.session?.authenticate()
        } else {
            kerberosQueue.async {
                self.session?.authenticate()
            }
        }
    }

    @objc func checkTickets(kinit: Bool=true, updateInfo: Bool=true, blocking: Bool=true) {

        klistUtil.klist()
        let tickets = klistUtil.returnPrincipals()

        if tickets.contains(prefs.string(for: .userPrincipal) ?? "********") {
            //ticketsItem.state = .on
            if updateInfo {
                session?.userInfo()
            }
        } else {
            //ticketsItem.state = .off
            if kinit {
                getTickets(blocking: blocking)
            }
        }
    }

    @objc fileprivate func networkChange() {
        
        if kKerberosUpdateTimer == nil {
            
            kKerberosUpdateTimer = Timer.init(timeInterval: 3, repeats: false, block: { timer in
                self.checkTickets(kinit: true, updateInfo: true, blocking: true)
                kKerberosUpdateTimer = nil
                })
            RunLoop.main.add(kKerberosUpdateTimer!, forMode: RunLoop.Mode.default)
        }
    }

    ///MARK: NoMAD AD Framework Callbacks

    func dogeADAuthenticationSucceded() {

        session?.recursiveGroupLookup = prefs.bool(for: .recursiveGroupLookup)
        session?.userInfo()
        session?.userPass = "********"
        //ticketsItem.state = .on
    }

    func dogeADAuthenticationFailed(error: dogeADSessionError, description: String) {

        session?.userPass = "********"

        switch error {
        case .AuthenticationFailure, .PasswordExpired : 
            // password is bad or expired, we should remove the password
            // FIXME:
            break
//            _ = kcUtil.deletePassword()
        default :
            break
        }
    }

    func dogeADUserInformation(user: ADUserRecord) {

            print("AD User Record")
            print("\tPrincipal: \(user.userPrincipal)")
            print("\tFirst Name: \(user.firstName)")
            print("\tLast Name: \(user.lastName)")
            print("\tFull Name: \(user.fullName)")
            print("\tShort Name: \(user.shortName)")
            print("\tUPN: \(user.upn)")
            print("\temail: \(user.email ?? "NONE")")
            print("\tGroups: \(user.groups)")
            print("\tHome Directory: \(user.homeDirectory ?? "NONE")")
            print("\tPassword Set: \(user.passwordSet)")
            print("\tPassword Expire: \(String(describing: user.passwordExpire))")
            print("\tUAC Flags: \(String(describing: user.uacFlags))")
            print("\tPassword Aging: \(String(describing: user.passwordAging))")
            print("\tComputed Expire Date: \(String(describing: user.computedExireDate))")
            print("\tDomain: \(user.domain)")
            print("\tCustom Attributes: \(String(describing: user.customAttributes))")

        // get all the user info

        defaults.set(user.cn, forKey: PreferenceKeys.userCN.rawValue)
        defaults.set(user.groups, forKey: PreferenceKeys.groups.rawValue)
        defaults.set(user.computedExireDate, forKey: PreferenceKeys.menuPasswordExpires.rawValue)
        // FIXME:
//        defaults.set(user.passwordSet, forKey: PreferenceKeys.userPasswordSetDates.rawValue)
        defaults.set(user.homeDirectory, forKey: PreferenceKeys.userHome.rawValue)
        defaults.set(user.userPrincipal, forKey: PreferenceKeys.userPrincipal.rawValue)
        defaults.set(user.customAttributes, forKey: PreferenceKeys.customLDAPAttributesResults.rawValue)
        defaults.set(user.shortName, forKey: PreferenceKeys.userShortName.rawValue)
        defaults.set(user.upn, forKey: PreferenceKeys.userUPN.rawValue)
        defaults.set(user.email, forKey: PreferenceKeys.userEmail.rawValue)
        defaults.set(user.fullName, forKey: PreferenceKeys.displayName.rawValue)
        //defaults.set(user.firstName, forKey: PrefKeys.first.rawValue)
        //defaults.set(user.lastName, forKey: PrefKeys.UserLastName.rawValue)
    }

    func onDomain() -> Bool {
        if let state = session?.state {
            switch state {
            case .success, .passwordChangeRequired :
                    print("***On Domain***")
                return true
            default :
                    print("***Not On Domain***")
                return false
            }
        } else {
            return false
        }
    }
}
