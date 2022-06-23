//
//  AppStatistics.swift
//  Network Share Mounter
//
//  Created by Gregor Longariva on 21.06.22.
//  Copyright © 2022 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation
import Cocoa

struct AppStatistics {
    var instanceUUID = "UNKNOWN"
    var appVersion = "UNKNOWN"
    var reportURL = Settings.statisticsReportURL
    var bundleID = "UNKNOWN"
    let userDefaults = UserDefaults.standard
    
    init() {
        self.instanceUUID = getInstanceUUID()
        self.appVersion = getAppVersion()
        self.bundleID = getBundleID()
    }
    
    private func getInstanceUUID() -> String {
        if let uuid = userDefaults.string(forKey: "UUID") {
            return(uuid)
        } else {
            let uuid = UUID().uuidString
            userDefaults.set(uuid, forKey: "UUID")
            return(uuid)
        }
    }
    
    private func getBundleID() -> String {
        if let bundleID = Bundle.main.bundleIdentifier  {
            return(bundleID)
        } else {
            return("UNKNOWN")
        }
    }
    
    private func getAppVersion() -> String {
        if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return(appVersion)
        } else {
            return("UNKNOWN")
        }
    }
    
    func reportAppInstallation() -> Void {
        let reportData = "/?bundleid=" + self.bundleID + "&uuid=" + self.instanceUUID + "&version=" + self.appVersion
        guard let reportURL = URL(string: Settings.statisticsReportURL + reportData) else {
            return()
        }
        var request = URLRequest(url: reportURL)
        request.httpMethod = "GET"
        let sessionConfiguration = URLSessionConfiguration.default
        let session = URLSession(configuration: sessionConfiguration)
        let semaphore = DispatchSemaphore(value: 0)
        NSLog("Trying to connect to report server")
        session.dataTask(with: reportURL) { data, response, error in
            DispatchQueue.main.async {
                if error != nil || (response as! HTTPURLResponse).statusCode != 200 {
                    NSLog("Connection to reporting server failed.")
                } else {
                    NSLog("Reported app statistics.")
                }
                // swiftlint:enable force_cast
                semaphore.signal()
            }
        }.resume()
        _ = semaphore.wait(wallTimeout: .distantFuture)
        // remove possible \n at the end of the string
        return()
    }
    
}



