//
//  Logger.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 26.12.23.
//  Copyright © 2024 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import OSLog

/// extension to Unified logging
extension Logger {
    /// Using bundle identifier
    private static var subsystem = Bundle.main.bundleIdentifier!
    /// Define different states and tasks of the app
    static let app = Logger(subsystem: subsystem, category: "app")
    static let mounter = Logger(subsystem: subsystem, category: "mounter")
    static let shareManager = Logger(subsystem: subsystem, category: "shareManager")
    static let accountsManager = Logger(subsystem: subsystem, category: "accountsManager")
    static let appStatistics = Logger(subsystem: subsystem, category: "appStatistics")
    static let networkMonitor = Logger(subsystem: subsystem, category: "networkMonitor")
    static let activityController = Logger(subsystem: subsystem, category: "activityController")
    static let networkShareViewController = Logger(subsystem: subsystem, category: "networkShareViewController")
    static let KrbAuthViewController = Logger(subsystem: subsystem, category: "KrbAuthViewController")
    static let shareViewController = Logger(subsystem: subsystem, category: "shareViewController")
    static let kerberos = Logger(subsystem: subsystem, category: "kerberos")
    static let automaticSignIn = Logger(subsystem: subsystem, category: "automaticSignIn")
    static let tasks = Logger(subsystem: subsystem, category: "tasks")
    static let directoryOperations = Logger(subsystem: subsystem, category: "directoryOperations")
    static let authUI = Logger(subsystem: subsystem, category: "authUI")
    static let FAU = Logger(subsystem: subsystem, category: "FAU")
    static let preferences = Logger(subsystem: subsystem, category: "preferences")
    static let login = Logger(subsystem: subsystem, category: "login")
    static let finderController = Logger(subsystem: subsystem, category: "finderController")
    static let keychain = Logger(subsystem: subsystem, category: "keychain")
}
