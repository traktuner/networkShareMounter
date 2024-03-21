//
//  Monitor.swift
//  Network Share Mounter
//
//  Created by Gregor Longariva on 24.11.21.
//  Copyright © 2024 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation
import Network
import OSLog
import AppKit

// variable is used to wait a few seconds to settle network connectivity
var networkUpdatePending = false
var networkUpdateTimer: Timer?

enum Reachable: String {
    case yes, nope
}

enum Connection: String {
    case cellular, loopback, wifi, wiredEthernet, other, unknown, none
}

class Monitor {
    static public let shared = Monitor()
    let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "Monitor")
    var netOn: Bool = true
    var connType: Connection = .loopback
    
    init() {
        self.monitor = NWPathMonitor()
        self.monitor.start(queue: queue)
    }
}

extension Monitor {
    func startMonitoring( callBack: @escaping (_ connection: Connection, _ reachable: Reachable) -> Void ) {
        let networkSettleTime: Double = 4
        monitor.pathUpdateHandler = { path in

            let reachable = (path.status == .unsatisfied || path.status == .requiresConnection)  ? Reachable.nope  : Reachable.yes
            self.netOn = path.status == .satisfied
            self.connType = self.checkConnectionTypeForPath(path)
            Logger.networkMonitor.info("🔌 Got Network connection change trigger from \(self.connType.rawValue, privacy: .public) to \(self.checkConnectionTypeForPath(path).rawValue, privacy: .public)..")
            
            if path.status == .satisfied {
                // wait a few seconds to settle network before firing callbacks
                if !networkUpdatePending {
                    Logger.networkMonitor.debug(" ▶︎ Waiting \(Int(networkSettleTime), privacy: .public) seconds to settle network...")
                    kNetworkUpdateTimer = Timer.init(timeInterval: networkSettleTime, repeats: false, block: {_ in
                        kNetworkUpdatePending = false
                        Logger.networkMonitor.debug(" ▶︎ Firing network change callbacks")
                        if path.usesInterfaceType(.wifi) {
                            return callBack(.wifi, reachable)
                        } else if path.usesInterfaceType(.cellular) {
                            return callBack(.cellular, reachable)
                        } else if path.usesInterfaceType(.wiredEthernet) {
                            return callBack(.wiredEthernet, reachable)
                        } else {
                            return callBack(.other, reachable)
                        }
                    })
                    RunLoop.main.add(kNetworkUpdateTimer!, forMode: RunLoop.Mode.default)
                    kNetworkUpdatePending = true
                }
            } else {
                return callBack(.none, .nope)
            }
        }
    }
}

extension Monitor {
    func checkConnectionTypeForPath(_ path: NWPath) -> Connection {
        if path.usesInterfaceType(.wiredEthernet) {
            return .wiredEthernet
        } else if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.loopback) {
            return .loopback
        } 
        return .unknown
    }
}

extension Monitor {
    func cancel() {
        monitor.cancel()
    }
}
