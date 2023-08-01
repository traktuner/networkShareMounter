//
//  Migrate.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 31.07.23.
//  Copyright © 2023 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation

func migrateConfig() {
    if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
        print("Bundle Version is: \(appVersion)")
//        if let formerVersion: String = UserDefaults.standard.string(forKey: "networkShares") as? String ?? "2.0.0" {
//            print("Former Version: \(formerVersion)")
//        }
        if let savedDict = UserDefaults.standard.array(forKey: "networkShares") as? [[String : Int]] {
            print("Yes first")
        } else {
            if let savedDict = UserDefaults.standard.array(forKey: "networkShares") as? [String] {
                print("Yes second")
            } else {
                print("No")
            }
        }
//        if let networkShares: [String] = UserDefaults.standard.array(forKey: "networkShares") as? [String] ?? []
//        let customShares = UserDefaults.standard.array(forKey: "customNetworkShares") as? [String] ?? []
    }
}
