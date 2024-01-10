//
//  AppStatistics.swift
//  Network Share Mounter
//
//  Created by Gregor Longariva on 21.06.22.
//  Copyright © 2022 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation
import Cocoa
import OSLog


/// A simple data protection compliant and data-saving way to collect statistics on the usage of the app.
/// In fact there are three data sets that are transferred:
/// - **instanceUUID** a one-time per installation generated UUID to keep individual installations apart
/// - **appVersion** the installed version of network share mounter
/// - **bundleID** network share mounter's bundle id to be able to make a distinction between our different apps
///
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
    
    /// Generate or read a UUID unique for the installation
    /// - Returns: a string containig installation's UUID
    private func getInstanceUUID() -> String {
        if let uuid = userDefaults.string(forKey: Settings.UUID) {
            return(uuid)
        } else {
            let uuid = UUID().uuidString
            userDefaults.set(uuid, forKey: Settings.UUID)
            return(uuid)
        }
    }
    
    /// read and return the bundle ID of the app
    /// - Returns: a string containing the bundle id of the app
    func getBundleID() -> String {
        if let bundleID = Bundle.main.bundleIdentifier  {
            return(bundleID)
        } else {
            return("UNKNOWN")
        }
    }
    
    /// read and return the version of the app
    /// - Returns: a string conatinig the version of the app
    private func getAppVersion() -> String {
        if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            return(appVersion)
        } else {
            return("UNKNOWN")
        }
    }
    
    /// Performs a simple `http get` operation on a defined remote server providing three variables:
    /// - **instanceUUID**
    /// - **appVersion**
    /// - **bundleID**
    func reportAppInstallation() async -> Void {
#if DEBUG
        Logger.appStatistics.debug("Debugging app, not reporting anything to statistics server ...")
#else
        let reportData = "/?bundleid=" + self.bundleID + "&uuid=" + self.instanceUUID + "&version=" + self.appVersion
        guard let reportURL = URL(string: Settings.statisticsReportURL + reportData) else {
            return()
        }
        var request = URLRequest(url: reportURL)
        request.httpMethod = "GET"
        let sessionConfiguration = URLSessionConfiguration.default
        let session = URLSession(configuration: sessionConfiguration)

        do {
            Logger.appStatistics.debug("Trying to connect to statistics server ...")
            let (_, response) = try await session.data(for: request)
            // swiftlint:disable force_cast
            if (response as! HTTPURLResponse).statusCode == 200 {
                Logger.appStatistics.debug("Reported app statistics.")
            }
            // swiftlint:enable force_cast
        } catch {
            Logger.appStatistics.debug("Connection to reporting server failed.")
        }
#endif
        return()
    }
    
}



