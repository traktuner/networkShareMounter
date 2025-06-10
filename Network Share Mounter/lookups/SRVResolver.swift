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
    
    /// Initiates the SRV resolution process
    /// - Parameters:
    ///   - query: The DNS query string
    ///   - completion: The completion handler to call when the resolution is complete
    func resolve(query: String, completion: @escaping SRVResolverCompletion) async {
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
            
            await processResult(for: sdRef)
            
        default:
            completion(.failure(.serviceError))
        }
    }
    
    /// Processes the DNS service result using async
    /// - Parameter sdRef: The DNS service reference
    private func processResult(for sdRef: DNSServiceRef) async {
        await withCheckedContinuation { continuation in
            Task {
                let result = DNSServiceProcessResult(sdRef)
                
                if result != kDNSServiceErr_NoError {
                    self.fail()
                }
                
                self.stopQuery()
            }
            
            continuation.resume()
        }
    }
    
    /// Handles a failed SRV resolution
    private func fail() {
        stopQuery()
        completion?(.failure(.unableToComplete))
    }
    
    /// Stops the DNS query and cleans up resources
    private func stopQuery() {
        if let serviceRef = serviceRef {
            DNSServiceRefDeallocate(serviceRef)
            self.serviceRef = nil
        }
        
        if socket != -1 {
            close(socket)
            socket = -1
        }
    }
    
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
    
    /// Handles a successful SRV resolution
    private func success() {
        stopQuery()
        let result = SRVResult(SRVRecords: results, query: query ?? "Unknown Query")
        completion?(.success(result))
    }

    /// Bridges an Objective-C object to a Swift pointer
    private static func bridge<T: AnyObject>(_ obj: T) -> UnsafeMutableRawPointer {
        return Unmanaged.passUnretained(obj).toOpaque()
    }
    
    /// Bridges a Swift pointer back to an Objective-C object
    private static func bridge<T: AnyObject>(_ ptr: UnsafeMutableRawPointer) -> T {
        return Unmanaged<T>.fromOpaque(ptr).takeUnretainedValue()
    }
}
