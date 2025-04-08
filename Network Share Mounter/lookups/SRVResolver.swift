//
//  SRVResolver.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 15.12.23.
//  Copyright © 2019 Jamf. All rights reserved.
//  Copyright © 2024 RRZE. All rights reserved.
//

import Foundation
import dnssd
import Combine

/// Enum representing possible errors during SRV resolution.
public enum SRVResolverError: String, Error, Codable {
    case unableToComplete = "Unable to complete lookup"
    case invalidQuery = "Invalid query string"
    case socketError = "Failed to create socket"
    case timeout = "DNS lookup timed out"
    case serviceError = "DNS service error"
}

/// Type alias for the result of an SRV resolution.
public typealias SRVResolverResult = Result<SRVResult, SRVResolverError>

/// Type alias for the completion handler used in SRV resolution.
public typealias SRVResolverCompletion = (SRVResolverResult) -> Void

/// Class responsible for resolving SRV records.
/// 
/// This class handles DNS-SRV record resolution using the dnssd framework.
/// It provides asynchronous resolution with timeout handling and proper resource cleanup.
class SRVResolver {
    /// Dispatch queue for handling DNS operations
    private let queue = DispatchQueue(label: "SRVResolution")
    
    /// Source for reading from the DNS socket
    private var dispatchSourceRead: DispatchSourceRead?
    
    /// Timer for handling timeouts
    private var timeoutTimer: DispatchSourceTimer?
    
    /// Reference to the DNS service
    private var serviceRef: DNSServiceRef?
    
    /// Socket file descriptor
    private var socket: dnssd_sock_t = -1
    
    /// The current DNS query string
    private var query: String?
    
    /// Default timeout for DNS lookups in seconds
    private let timeout: TimeInterval = 5
    
    /// Array to store resolved SRV records
    var results = [SRVRecord]()
    
    /// Completion handler for the resolution process
    var completion: SRVResolverCompletion?
    
    /// Callback function for processing DNS results
    private let queryCallback: DNSServiceQueryRecordReply = { (sdRef, flags, interfaceIndex, errorCode, fullname, rrtype, rrclass, rdlen, rdata, ttl, context) -> Void in
        guard let context = context else { return }
        
        let resolver: SRVResolver = SRVResolver.bridge(context)
        
        if let data = rdata?.assumingMemoryBound(to: UInt8.self),
           let record = SRVRecord(data: Data(bytes: data, count: Int(rdlen))) {
            resolver.results.append(record)
        }
        
        if (flags & kDNSServiceFlagsMoreComing) == 0 {
            resolver.success()
        }
    }
    
    /// Bridges an Objective-C object to a Swift pointer
    /// - Parameter obj: The object to bridge
    /// - Returns: An UnsafeMutableRawPointer containing the bridged object
    private static func bridge<T: AnyObject>(_ obj: T) -> UnsafeMutableRawPointer {
        return Unmanaged.passUnretained(obj).toOpaque()
    }
    
    /// Bridges a Swift pointer back to an Objective-C object
    /// - Parameter ptr: The pointer to bridge
    /// - Returns: The bridged object
    private static func bridge<T: AnyObject>(_ ptr: UnsafeMutableRawPointer) -> T {
        return Unmanaged<T>.fromOpaque(ptr).takeUnretainedValue()
    }
    
    /// Handles a failed SRV resolution
    private func fail() {
        stopQuery()
        completion?(.failure(.unableToComplete))
    }
    
    /// Handles a successful SRV resolution
    private func success() {
        stopQuery()
        let result = SRVResult(SRVRecords: results, query: query ?? "Unknown Query")
        completion?(.success(result))
    }
    
    /// Stops the DNS query and cleans up resources
    private func stopQuery() {
        timeoutTimer?.cancel()
        timeoutTimer = nil
        
        dispatchSourceRead?.cancel()
        dispatchSourceRead = nil
        
        if let serviceRef = serviceRef {
            DNSServiceRefDeallocate(serviceRef)
            self.serviceRef = nil
        }
        
        if socket != -1 {
            close(socket)
            socket = -1
        }
    }
    
    /// Initiates the SRV resolution process
    /// - Parameters:
    ///   - query: The DNS query string
    ///   - completion: The completion handler to call when the resolution is complete
    func resolve(query: String, completion: @escaping SRVResolverCompletion) {
        self.completion = completion
        self.query = query
        
        guard let namec = query.cString(using: .utf8) else {
            completion(.failure(.invalidQuery))
            return
        }
        
        let result = DNSServiceQueryRecord(
            &serviceRef,
            kDNSServiceFlagsReturnIntermediates,
            0, // query on all interfaces
            namec,
            UInt16(kDNSServiceType_SRV),
            UInt16(kDNSServiceClass_IN),
            queryCallback,
            SRVResolver.bridge(self)
        )
        
        switch result {
        case DNSServiceErrorType(kDNSServiceErr_NoError):
            guard let sdRef = serviceRef else {
                completion(.failure(.serviceError))
                return
            }
            
            socket = DNSServiceRefSockFD(sdRef)
            
            guard socket != -1 else {
                completion(.failure(.socketError))
                return
            }
            
            setupDispatchSource(for: sdRef)
            setupTimeoutTimer()
            
        default:
            completion(.failure(.serviceError))
        }
    }
    
    /// Sets up the dispatch source for reading from the socket
    /// - Parameter sdRef: The DNS service reference
    private func setupDispatchSource(for sdRef: DNSServiceRef) {
        dispatchSourceRead = DispatchSource.makeReadSource(fileDescriptor: socket, queue: queue)
        
        dispatchSourceRead?.setEventHandler { [weak self] in
            guard let self = self else { return }
            let res = DNSServiceProcessResult(sdRef)
            if res != kDNSServiceErr_NoError {
                self.fail()
            }
        }
        
        dispatchSourceRead?.setCancelHandler { [weak self] in
            guard let self = self else { return }
            if let serviceRef = self.serviceRef {
                DNSServiceRefDeallocate(serviceRef)
            }
        }
        
        dispatchSourceRead?.resume()
    }
    
    /// Sets up the timeout timer
    private func setupTimeoutTimer() {
        timeoutTimer = DispatchSource.makeTimerSource(flags: [], queue: queue)
        
        timeoutTimer?.setEventHandler { [weak self] in
            guard let self = self else { return }
            self.completion?(.failure(.timeout))
            self.stopQuery()
        }
        
        let deadline = DispatchTime.now() + timeout
        timeoutTimer?.schedule(deadline: deadline, repeating: .infinity, leeway: .never)
        timeoutTimer?.resume()
    }
}
