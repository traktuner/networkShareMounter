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
}

/// Type alias for the result of an SRV resolution.
public typealias SRVResolverResult = Result<SRVResult, SRVResolverError>

/// Type alias for the completion handler used in SRV resolution.
public typealias SRVResolverCompletion = (SRVResolverResult) -> Void

/// Class responsible for resolving SRV records.
class SRVResolver {
    private let queue = DispatchQueue(label: "SRVResolution")
    private var dispatchSourceRead: DispatchSourceRead?
    private var timeoutTimer: DispatchSourceTimer?
    private var serviceRef: DNSServiceRef?
    private var socket: dnssd_sock_t = -1
    private var query: String?
    
    /// Default timeout for DNS lookups.
    private let timeout = TimeInterval(5)
    
    var results = [SRVRecord]()
    var completion: SRVResolverCompletion?
    
    /// Callback function for processing DNS results.
    let queryCallback: DNSServiceQueryRecordReply = { (sdRef, flags, interfaceIndex, errorCode, fullname, rrtype, rrclass, rdlen, rdata, ttl, context) -> Void in
        
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
    
    /// Bridges an Objective-C object to a Swift pointer.
    static func bridge<T: AnyObject>(_ obj: T) -> UnsafeMutableRawPointer {
        return Unmanaged.passUnretained(obj).toOpaque()
    }
    
    /// Bridges a Swift pointer back to an Objective-C object.
    static func bridge<T: AnyObject>(_ ptr: UnsafeMutableRawPointer) -> T {
        return Unmanaged<T>.fromOpaque(ptr).takeUnretainedValue()
    }
    
    /// Handles a failed SRV resolution.
    func fail() {
        stopQuery()
        completion?(.failure(.unableToComplete))
    }
    
    /// Handles a successful SRV resolution.
    func success() {
        stopQuery()
        let result = SRVResult(SRVRecords: results, query: query ?? "Unknown Query")
        completion?(.success(result))
    }
    
    /// Stops the DNS query and cleans up resources.
    private func stopQuery() {
        timeoutTimer?.cancel()
        dispatchSourceRead?.cancel()
        if let serviceRef = serviceRef {
            DNSServiceRefDeallocate(serviceRef)
            self.serviceRef = nil
        }
    }
    
    /// Initiates the SRV resolution process.
    /// - Parameters:
    ///   - query: The DNS query string.
    ///   - completion: The completion handler to call when the resolution is complete.
    func resolve(query: String, completion: @escaping SRVResolverCompletion) {
        self.completion = completion
        self.query = query
        guard let namec = query.cString(using: .utf8) else {
            fail()
            return
        }
        
        let result = DNSServiceQueryRecord(
            &serviceRef,
            kDNSServiceFlagsReturnIntermediates,
            0, // query on all interfaces.
            namec,
            UInt16(kDNSServiceType_SRV),
            UInt16(kDNSServiceClass_IN),
            queryCallback,
            SRVResolver.bridge(self)
        )
        
        switch result {
        case DNSServiceErrorType(kDNSServiceErr_NoError):
            guard let sdRef = serviceRef else {
                fail()
                return
            }
            
            socket = DNSServiceRefSockFD(sdRef)
            
            guard socket != -1 else {
                fail()
                return
            }
            
            dispatchSourceRead = DispatchSource.makeReadSource(fileDescriptor: socket, queue: queue)
            
            dispatchSourceRead?.setEventHandler(handler: {
                let res = DNSServiceProcessResult(sdRef)
                if res != kDNSServiceErr_NoError {
                    self.fail()
                }
            })
            
            dispatchSourceRead?.setCancelHandler(handler: {
                if let serviceRef = self.serviceRef {
                    DNSServiceRefDeallocate(serviceRef)
                }
            })
            
            dispatchSourceRead?.resume()
            
            timeoutTimer = DispatchSource.makeTimerSource(flags: [], queue: queue)
            
            timeoutTimer?.setEventHandler(handler: {
                self.fail()
            })
            
            let deadline = DispatchTime.now() + timeout
            timeoutTimer?.schedule(deadline: deadline, repeating: .infinity, leeway: .never)
            timeoutTimer?.resume()
            
        default:
            fail()
        }
    }
}
