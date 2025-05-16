//
//  Monitor.swift
//  Network Share Mounter
//
//  Created by Gregor Longariva on 24.11.21.
//  Copyright © 2025 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation
import Network
import OSLog
import AppKit
import Combine

/// Represents the reachability state of the network
///
/// Used to indicate if a network connection is available.
public enum Reachable: String {
    /// Network is reachable
    case yes
    /// Network is not reachable
    case nope
}

/// Represents different types of network connections
///
/// Used to classify the type of network interface being used.
public enum Connection: String {
    /// Cellular network connection (e.g., 4G, 5G)
    case cellular
    /// Loopback connection (localhost)
    case loopback
    /// WiFi network connection
    case wifi
    /// Wired Ethernet connection
    case wiredEthernet
    /// Other connection type not specifically categorized
    case other
    /// Unknown connection type
    case unknown
    /// No connection available
    case none
}

/// Monitors network connectivity and provides notifications about network changes
///
/// This class uses the Network framework's `NWPathMonitor` to observe network status changes
/// and provides multiple ways to receive updates about these changes:
/// - Traditional callback method
/// - Combine publisher for reactive programming
///
/// It includes a built-in delay mechanism to allow the network to settle before notifying consumers.
public class Monitor {
    /// Shared singleton instance
    public static let shared = Monitor()
    
    /// The underlying network path monitor
    let monitor: NWPathMonitor
    
    /// Queue used for network monitoring
    private let queue = DispatchQueue(label: "Monitor")
    
    /// Flag indicating if network is currently available
    public private(set) var netOn: Bool = true
    
    /// Current network connection type
    public private(set) var connType: Connection = .loopback
    
    /// Whether a network update is pending (waiting for the settle time)
    private var networkUpdatePending = false
    
    /// Timer used to implement the network settle time
    private var networkUpdateTimer: Timer?
    
    /// Publisher that emits network status updates
    private let networkStatusSubject = PassthroughSubject<(Connection, Reachable), Never>()
    
    /// Publisher for network status changes
    ///
    /// Subscribe to this publisher to receive updates about network changes.
    /// Each emission contains a tuple with the connection type and reachability state.
    public var networkStatusPublisher: AnyPublisher<(Connection, Reachable), Never> {
        return networkStatusSubject.eraseToAnyPublisher()
    }
    
    /// Time in seconds to wait for network to settle before sending updates
    private let networkSettleTime: Double = 4
    
    /// Initializes a new network monitor and starts monitoring
    public init() {
        self.monitor = NWPathMonitor()
        self.monitor.start(queue: queue)
    }
    
    /// Stops the network monitor and releases resources
    deinit {
        cancel()
    }
}

// MARK: - Monitoring Methods
extension Monitor {
    /// Starts monitoring network changes and provides updates through a callback
    ///
    /// This method registers a callback that will be called whenever the network status changes.
    /// A built-in delay mechanism allows the network to settle before triggering the callback.
    ///
    /// - Parameter callBack: A closure that receives the new connection type and reachability state
    public func startMonitoring(callBack: @escaping (_ connection: Connection, _ reachable: Reachable) -> Void) {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            
            let reachable = (path.status == .unsatisfied || path.status == .requiresConnection) ? Reachable.nope : Reachable.yes
            self.netOn = path.status == .satisfied
            let newConnType = self.checkConnectionTypeForPath(path)
            self.connType = newConnType
            
            Logger.networkMonitor.info("🔌 Got Network connection change trigger from \(self.connType.rawValue, privacy: .public) to \(newConnType.rawValue, privacy: .public)..")
            
            // Emit update to the Combine publisher
            let update = (newConnType, reachable)
            DispatchQueue.main.async {
                self.networkStatusSubject.send(update)
            }
            
            if path.status == .satisfied {
                // Wait for network to settle before firing callbacks
                self.handleNetworkSettlingPeriod(path: path, reachable: reachable, callBack: callBack)
            } else {
                DispatchQueue.main.async {
                    callBack(.none, .nope)
                }
            }
        }
    }
    
    /// Handles the network settling period before triggering callbacks
    ///
    /// - Parameters:
    ///   - path: The network path that triggered the update
    ///   - reachable: The current reachability state
    ///   - callBack: The callback to trigger after the settling period
    private func handleNetworkSettlingPeriod(path: NWPath, reachable: Reachable, callBack: @escaping (_ connection: Connection, _ reachable: Reachable) -> Void) {
        // Bestehenden Timer invalidieren
        self.networkUpdateTimer?.invalidate()
        self.networkUpdateTimer = nil
        
        Logger.networkMonitor.debug(" ▶︎ Waiting \(Int(self.networkSettleTime), privacy: .public) seconds to settle network...")
        
        // Timer erstellen mit starker Selbstreferenz
        let timer = Timer(timeInterval: self.networkSettleTime, repeats: false) { [self] _ in
            Logger.networkMonitor.debug(" ▶︎ Timer fired! About to execute callback...")
            
            let connectionType = self.determineConnectionType(path: path)
            
            // Auf dem Main Thread ausführen
            DispatchQueue.main.async {
                Logger.networkMonitor.debug(" ▶︎ Firing network change callbacks")
                callBack(connectionType, reachable)
            }
        }
        
        // Timer explizit zum Main RunLoop hinzufügen und Referenz halten
        RunLoop.main.add(timer, forMode: .common)
        self.networkUpdateTimer = timer
        
        Logger.networkMonitor.debug(" ▶︎ Timer successfully scheduled on main RunLoop")
    }
    
    /// Determines the specific connection type from a network path
    ///
    /// - Parameter path: The network path to analyze
    /// - Returns: The determined connection type
    private func determineConnectionType(path: NWPath) -> Connection {
        if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            return .wiredEthernet
        } else {
            return .other
        }
    }
}

// MARK: - Utility Methods
extension Monitor {
    /// Checks the connection type for a given network path
    ///
    /// - Parameter path: The network path to check
    /// - Returns: The determined connection type
    public func checkConnectionTypeForPath(_ path: NWPath) -> Connection {
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

// MARK: - Resource Management
extension Monitor {
    /// Cancels the network monitor and releases resources
    ///
    /// Call this method when you no longer need network monitoring to free up resources.
    public func cancel() {
        networkUpdateTimer?.invalidate()
        networkUpdateTimer = nil
        monitor.cancel()
    }
}
