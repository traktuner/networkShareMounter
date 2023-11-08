//
//  Monitor.swift
//  Network Share Mounter
//
//  Created by Gregor Longariva on 24.11.21.
//  Copyright © 2021 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation
import Network
import OSLog
import AppKit

enum Reachable: String {
    case yes, nope
}

enum Connection: String {
    case cellular, loopback, wifi, wiredEthernet, other, unknown, none
}

class Monitor {
    let logger = Logger(subsystem: "NetworkShareMounter", category: "NetworkMonitor")
    
    static public let shared = Monitor()
    let monitor: NWPathMonitor
    private let queue = DispatchQueue(label: "Monitor")
    var netOn: Bool = true
    var connType: Connection = .wifi
    
    init() {
        self.monitor = NWPathMonitor()
        self.monitor.start(queue: queue)
    }
}

extension Monitor {
    func startMonitoring( callBack: @escaping (_ connection: Connection, _ reachable: Reachable) -> Void ) {
        monitor.pathUpdateHandler = { path in

            let reachable = (path.status == .unsatisfied || path.status == .requiresConnection)  ? Reachable.nope  : Reachable.yes
            self.netOn = path.status == .satisfied
            self.connType = self.checkConnectionTypeForPath(path)
            self.logger.info("Network connection changed to \(self.connType.rawValue, privacy: .public).")

            if path.status == .satisfied {
                if path.usesInterfaceType(.wifi) {
                    return callBack(.wifi, reachable)
                } else if path.usesInterfaceType(.cellular) {
                    return callBack(.cellular, reachable)
                } else if path.usesInterfaceType(.wiredEthernet) {
                    return callBack(.wiredEthernet, reachable)
                } else {
                    return callBack(.other, reachable)
                }
            } else {
                return callBack(.none, .nope)
            }
//            if path.availableInterfaces.isEmpty {
//                return callBack(.other, .nope)
//            } else if path.usesInterfaceType(.wifi) {
//                return callBack(.wifi, reachable)
//            } else if path.usesInterfaceType(.cellular) {
//                return callBack(.cellular, reachable)
//            } else if path.usesInterfaceType(.loopback) {
//                return callBack(.loopback, reachable)
//            } else if path.usesInterfaceType(.wiredEthernet) {
//                return callBack(.wiredEthernet, reachable)
//            } else if path.usesInterfaceType(.other) {
//                return callBack(.other, .nope)
//            }
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
