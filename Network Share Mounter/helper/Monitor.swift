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
/// This actor uses the Network framework's `NWPathMonitor` to observe network status changes
/// and provides multiple ways to receive updates about these changes:
/// - Traditional callback method
/// - Combine publisher for reactive programming
/// - AsyncStream for Swift Concurrency consumers
///
/// It includes a built-in delay mechanism to allow the network to settle before notifying consumers.
///
/// Semantics:
/// - "Down" (unsatisfied/requiresConnection): Events are sent immediately as (.none, .nope)
/// - "Up" (satisfied): Events are sent after a settle delay as (connType, .yes)
public actor Monitor {
    /// Shared singleton instance
    public static let shared = Monitor()
    
    /// The underlying network path monitor
    let monitor: NWPathMonitor
    
    /// Queue used for network monitoring (required by NWPathMonitor API)
    private let queue = DispatchQueue(label: "Monitor")
    
    /// Flag indicating if network is currently available (actor-protected)
    public private(set) var netOn: Bool = false
    
    /// Current network connection type (actor-protected)
    public private(set) var connType: Connection = .unknown
    
    /// Task used to implement the network settle time (replaces Timer/RunLoop)
    private var networkUpdateTask: Task<Void, Never>?
    
    /// Publisher that emits network status updates (bridged to outside world)
    /// We keep the subject private and expose only the erased publisher.
    private let networkStatusSubject: CurrentValueSubject<(Connection, Reachable), Never>
    
    /// Publisher for network status changes
    ///
    /// Subscribe to this publisher to receive updates about network changes.
    /// Each emission contains a tuple with the connection type and reachability state.
    public nonisolated var networkStatusPublisher: AnyPublisher<(Connection, Reachable), Never> {
        networkStatusSubject.eraseToAnyPublisher()
    }
    
    /// Async stream for network status changes (optional modern API)
    ///
    /// Consumers can iterate with `for await` to receive updates.
    public nonisolated var networkStatusStream: AsyncStream<(Connection, Reachable)> {
        AsyncStream { continuation in
            let cancellable = networkStatusPublisher.sink { value in
                continuation.yield(value)
            }
            continuation.onTermination = { @Sendable _ in
                cancellable.cancel()
            }
        }
    }
    
    /// Time in seconds to wait for network to settle before sending updates
    private let networkSettleTime: Double
    
    /// Initializes a new network monitor and starts monitoring
    /// - Parameter settleTime: Optional settle time in seconds (default: 4)
    public init(settleTime: Double = 4) {
        self.monitor = NWPathMonitor()
        self.networkSettleTime = settleTime
        
        // Initialize CurrentValueSubject with an initial snapshot from a “neutral” state
        self.networkStatusSubject = CurrentValueSubject<(Connection, Reachable), Never>((.unknown, .nope))
        
        // Start monitoring immediately (matches previous behavior)
        self.monitor.start(queue: queue)
    }
    
    deinit {
        // Note: deinit of actors is rarely called in typical app lifecycles for singletons,
        // but keep cleanup here for completeness.
        monitor.cancel()
    }
}

// MARK: - Public API
extension Monitor {
    /// Returns the current status snapshot in a thread-safe manner.
    public func currentStatus() -> (Connection, Reachable) {
        (connType, netOn ? .yes : .nope)
    }
    
    /// Starts monitoring network changes and provides updates through a callback
    ///
    /// This method registers a callback that will be called whenever the network status changes.
    /// A built-in delay mechanism allows the network to settle before triggering the callback.
    ///
    /// - Parameter callBack: A closure that receives the new connection type and reachability state
    public func startMonitoring(callBack: @escaping (_ connection: Connection, _ reachable: Reachable) -> Void) {
        // NWPathMonitor invokes the handler on its own queue (not actor isolated).
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            // Hop into actor isolation to process the path safely.
            Task {
                await self.handlePathUpdate(path: path, callBack: callBack)
            }
        }
    }
    
    /// Cancels the network monitor and releases resources
    ///
    /// Call this method when you no longer need network monitoring to free up resources.
    public func cancel() {
        networkUpdateTask?.cancel()
        networkUpdateTask = nil
        monitor.cancel()
    }
}

// MARK: - Internal Processing
extension Monitor {
    /// Central handler for NWPath updates inside actor isolation
    private func handlePathUpdate(path: NWPath, callBack: @escaping (_ connection: Connection, _ reachable: Reachable) -> Void) {
        let reachable: Reachable = (path.status == .unsatisfied || path.status == .requiresConnection) ? .nope : .yes
        let newConnType = connectionType(for: path, reachable: reachable)
        
        // Update actor state
        self.netOn = (reachable == .yes)
        self.connType = newConnType
        
        Logger.networkMonitor.info("🔌 Network path update: status=\(String(describing: path.status), privacy: .public), connType=\(self.connType.rawValue, privacy: .public), reachable=\(reachable.rawValue, privacy: .public)")
        
        switch reachable {
        case .nope:
            // Cancel any pending settle task and notify immediately
            networkUpdateTask?.cancel()
            networkUpdateTask = nil
            
            // Send unified Down event to publisher and callback
            networkStatusSubject.send((.none, .nope))
            // UI/Notifications should be triggered on the MainActor
            Task { @MainActor in
                callBack(.none, .nope)
            }
            
        case .yes:
            // Wait for settle before notifying Up
            handleNetworkSettlingPeriod(path: path, callBack: callBack)
        }
    }
    
    /// Handles the network settling period before triggering callbacks
    ///
    /// - Parameters:
    ///   - path: The network path that triggered the update
    ///   - callBack: The callback to trigger after the settling period
    private func handleNetworkSettlingPeriod(path: NWPath, callBack: @escaping (_ connection: Connection, _ reachable: Reachable) -> Void) {
        // Cancel any previous settling task
        networkUpdateTask?.cancel()
        networkUpdateTask = nil
        
        Logger.networkMonitor.debug(" ▶︎ Waiting \(Int(self.networkSettleTime), privacy: .public) seconds to settle network...")
        
        // Schedule a new settling task using Swift Concurrency
        networkUpdateTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: UInt64(self.networkSettleTime * 1_000_000_000))
            } catch {
                // Task was cancelled due to a newer path update
                Logger.networkMonitor.debug(" ▶︎ Settle task cancelled before firing callback")
                return
            }
            
            // After settle, compute connection type again from the last path we saw
            let connectionType = await self.connectionType(for: path, reachable: .yes)
            Logger.networkMonitor.debug(" ▶︎ Settle delay passed! Firing Up event as (\(connectionType.rawValue, privacy: .public), yes)")
            
            // Update actor state (keeps invariants)
            await self.setStateAfterSettle(connectionType: connectionType)
            
            // Notify publisher and callback on MainActor
            await MainActor.run {
                self.networkStatusSubject.send((connectionType, .yes))
                callBack(connectionType, .yes)
            }
        }
        
        Logger.networkMonitor.debug(" ▶︎ Settle task scheduled")
    }
    
    /// Applies state after the settle period inside actor isolation
    private func setStateAfterSettle(connectionType: Connection) {
        self.netOn = true
        self.connType = connectionType
    }
    
    /// Determines the specific connection type from a network path
    ///
    /// - Parameters:
    ///   - path: The network path to analyze
    ///   - reachable: Reachability derived from path.status
    /// - Returns: The determined connection type
    private func connectionType(for path: NWPath, reachable: Reachable) -> Connection {
        // If not reachable, normalize to .none
        guard reachable == .yes else { return .none }
        
        if path.usesInterfaceType(.wiredEthernet) {
            return .wiredEthernet
        } else if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.loopback) {
            return .loopback
        } else {
            return .other
        }
    }
    
    /// Public helper retained for callers that might use it (kept for API compatibility)
    ///
    /// - Parameter path: The network path to check
    /// - Returns: The determined connection type
    public func checkConnectionTypeForPath(_ path: NWPath) -> Connection {
        if path.status != .satisfied { return .none }
        if path.usesInterfaceType(.wiredEthernet) {
            return .wiredEthernet
        } else if path.usesInterfaceType(.wifi) {
            return .wifi
        } else if path.usesInterfaceType(.cellular) {
            return .cellular
        } else if path.usesInterfaceType(.loopback) {
            return .loopback
        }
        return .other
    }
}
