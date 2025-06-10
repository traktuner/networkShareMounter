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

/// Simplified class for SRV record resolution
///
/// Provides basic DNS-SRV lookup functionality with callback-based completion
class SRVResolver {

    /// Reference to the DNS service
    private var serviceRef: DNSServiceRef?
    
    /// Array to store resolved SRV records
    private var results = [SRVRecord]()
    
    /// Completion handler for the resolution process
    private var completion: SRVResolverCompletion?
    
    /// The current DNS query string (for result reporting)
    private var currentQuery: String?
    
    /// Initiates the SRV resolution process
    /// - Parameters:
    ///   - query: The DNS query string
    ///   - completion: The completion handler to call when the resolution is complete
    func resolve(query: String, completion: @escaping SRVResolverCompletion) {
        self.completion = completion
        self.currentQuery = query
        self.results.removeAll()
        
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
        
        guard result == kDNSServiceErr_NoError else {
            completion(.failure(.serviceError))
            return
        }
        
        guard let sdRef = serviceRef else {
            completion(.failure(.serviceError))
            return
        }
        
        // Process the result
        let processResult = DNSServiceProcessResult(sdRef)
        if processResult != kDNSServiceErr_NoError {
            cleanup()
            completion(.failure(.serviceError))
        }
    }
    
    /// Cleans up DNS service resources
    private func cleanup() {
        if let serviceRef = serviceRef {
            DNSServiceRefDeallocate(serviceRef)
            self.serviceRef = nil
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
        cleanup()
        let result = SRVResult(SRVRecords: results, query: currentQuery ?? "Unknown Query")
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
