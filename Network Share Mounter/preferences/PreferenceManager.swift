//
//  PreferenceManager.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 15.12.23.
//  Copyright © 2020 Orchard & Grove, Inc. All rights reserved.
//  Copyright © 2024 RRZE. All rights reserved.
//

import Foundation
import dogeADAuth

let kStateDomain = "de.fau.rrze.NetworkShareMounter.doge.state"
let kSharedDefaultsName = "de.fau.rrze.NetworkShareMounter"

extension UserDefaults {
    @objc dynamic var Accounts: Data? {
        return data(forKey: Defaults.Accounts)
    }
}

struct PreferenceManager {
    
    let defaults = UserDefaults.standard
    let stateDefaults = UserDefaults.init(suiteName: kStateDomain)
    
    init() {
        if let defaultValues = readPropertyList() {
            defaults.register(defaults: defaultValues)
        }
    }
    
    func array(for prefKey: PreferenceKeys) -> [Any]? {
        defaults.array(forKey: prefKey.rawValue)
    }
    
    func string(for prefKey: PreferenceKeys) -> String? {
        defaults.string(forKey: prefKey.rawValue)
    }
    
    func object(for prefKey: PreferenceKeys) -> Any? {
        defaults.object(forKey: prefKey.rawValue)
    }
    
    func dictionary(for prefKey: PreferenceKeys) -> [String:Any]? {
        defaults.dictionary(forKey: prefKey.rawValue)
    }
    
    func bool(for prefKey: PreferenceKeys) -> Bool {
        defaults.bool(forKey: prefKey.rawValue)
    }
    
    func set(for prefKey: PreferenceKeys, value: Any) {
        defaults.set(value as AnyObject, forKey: prefKey.rawValue)
    }
    
    func int(for prefKey: PreferenceKeys) -> Int {
        defaults.integer(forKey: prefKey.rawValue)
    }
    
    func date(for prefKey: PreferenceKeys) -> Date? {
        defaults.object(forKey: prefKey.rawValue) as? Date
    }
    
    func clear(for prefKey: PreferenceKeys) {
        defaults.set(nil, forKey: prefKey.rawValue)
    }
    
    func data(for prefKey: PreferenceKeys) -> Data? {
        defaults.data(forKey: prefKey.rawValue)
    }
    
    func setADUserInfo(user: ADUserRecord) {
        defaults.set(user.userPrincipal.lowercased(), forKey: PreferenceKeys.lastUser.rawValue)
        
        if let passwordAging = user.passwordAging, passwordAging {
            if let expireDate = user.computedExireDate {
                self.set(for: .userPasswordExpireDate, value: expireDate)
            }
        } else {
            self.clear(for: .userPasswordExpireDate)
        }
        
        guard let stateDefaults = stateDefaults else { return }
        
        stateDefaults.set(user.cn, forKey: PreferenceKeys.userCN.rawValue)
        stateDefaults.set(user.groups, forKey: PreferenceKeys.userGroups.rawValue)
        stateDefaults.set(user.computedExireDate, forKey: PreferenceKeys.userPasswordExpireDate.rawValue)
        stateDefaults.set(user.passwordSet, forKey: PreferenceKeys.userPasswordSetDate.rawValue)
        stateDefaults.set(user.homeDirectory, forKey: PreferenceKeys.userHome.rawValue)
        stateDefaults.set(user.userPrincipal, forKey: PreferenceKeys.userPrincipal.rawValue)
        stateDefaults.set(user.customAttributes, forKey: PreferenceKeys.customLDAPAttributesResults.rawValue)
        stateDefaults.set(user.shortName, forKey: PreferenceKeys.userShortName.rawValue)
        stateDefaults.set(user.upn, forKey: PreferenceKeys.userUPN.rawValue)
        stateDefaults.set(user.email, forKey: PreferenceKeys.userEmail.rawValue)
        stateDefaults.set(user.fullName, forKey: PreferenceKeys.userFullName.rawValue)
        stateDefaults.set(user.firstName, forKey: PreferenceKeys.userFirstName.rawValue)
        stateDefaults.set(user.lastName, forKey: PreferenceKeys.userLastName.rawValue)
        stateDefaults.set(Date(), forKey: PreferenceKeys.userLastChecked.rawValue)
        
        var allUsers = stateDefaults.dictionary(forKey: PreferenceKeys.allUserInformation.rawValue) ?? [String: [String: AnyObject]]()
        allUsers[user.userPrincipal] = [
            "CN": user.cn,
            "groups": user.groups,
            "UserPasswordExpireDate": user.computedExireDate?.description ?? "",
            "UserHome": user.homeDirectory ?? "",
            "UserPrincipal": user.userPrincipal,
            "CustomLDAPAttributesResults": user.customAttributes?.description ?? "",
            "UserShortName": user.shortName,
            "UserUPN": user.upn,
            "UserEmail": user.email ?? "",
            "UserFullName": user.fullName,
            "UserFirstName": user.firstName,
            "UserLastName": user.lastName,
            "UserLastChecked": Date()
        ]
        stateDefaults.setValue(allUsers, forKey: PreferenceKeys.allUserInformation.rawValue)
    }
        
    private func readPropertyList() -> [String: Any]? {
        guard let plistPath = Bundle.main.path(forResource: "DefaultValues", ofType: "plist"),
              let plistData = FileManager.default.contents(atPath: plistPath) else {
            return nil
        }
        return try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
    }
}
