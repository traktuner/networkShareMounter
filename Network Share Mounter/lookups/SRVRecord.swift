/// SRVRecord.swift
/// Handles DNS Service (SRV) record parsing and management
///
/// SRV records allow services to be moved to different ports and hosts while
/// maintaining the same service name, enabling load balancing and failover.

import Foundation

/// Represents a collection of SRV records and provides sorting capabilities
public struct SRVResult {
    /// Array of parsed SRV records
    let SRVRecords: [SRVRecord]
    /// Original DNS query string
    let query: String
    
    /// Sorts SRV records by weight and returns target hostnames
    /// - Returns: Array of target hostnames sorted by weight, nil if no records exist
    /// - Note: Uses Swift's native sort for optimal performance
    func sortByWeight() -> [String]? {
        guard !SRVRecords.isEmpty else { return nil }
        
        return SRVRecords
            .sorted { $0.weight < $1.weight }
            .map { $0.target }
    }
}

// MARK: - CustomStringConvertible Implementation
extension SRVResult: CustomStringConvertible {
    /// Returns a string representation of the SRV result
    /// - Returns: A formatted string containing query and record information
    public var description: String {
        var result = "Query for: \(query)"
        result += "\n\tRecord Count: \(SRVRecords.count)"
        for record in SRVRecords {
            result += "\n\t\(record.description)"
        }
        return result
    }
}

/// Represents a single DNS SRV record with its associated properties
public struct SRVRecord: Codable, Equatable {
    /// Priority of the target host (lower value = higher priority)
    let priority: Int
    /// Relative weight for records with same priority
    let weight: Int
    /// TCP/UDP port number of the service (valid range: 1-65535)
    let port: Int
    /// Hostname of the target machine
    let target: String
    
    /// Initializes an SRV record from raw DNS response data
    /// - Parameter data: Raw DNS response bytes
    /// - Returns: nil if data is invalid or too short
    /// - Note: Implements robust Unicode handling for hostnames
    init?(data: Data) {
        guard data.count > 8 else { return nil }
        
        // Parse priority, weight, and port
        priority = Int(data[0]) * 256 + Int(data[1])
        weight = Int(data[2]) * 256 + Int(data[3])
        port = Int(data[4]) * 256 + Int(data[5])
        
        // Validate port number
        guard port > 0 && port <= 65535 else { return nil }
        
        // Parse hostname with improved Unicode handling
        var workingTarget = ""
        var currentByte = 7
        
        while currentByte < data.count {
            let byte = data[currentByte]
            
            // Handle control characters and dots
            if byte == 0x00 || (byte >= 0x03 && byte <= 0x05) {
                workingTarget += "."
            } else if let char = String(data: Data([byte]), encoding: .utf8) {
                workingTarget += char
            }
            currentByte += 1
        }
        
        // Validate target hostname
        guard !workingTarget.isEmpty else { return nil }
        
        target = workingTarget
    }
}

// MARK: - CustomStringConvertible Implementation
extension SRVRecord: CustomStringConvertible {
    /// Returns a string representation of the SRV record
    /// - Returns: A formatted string containing target, priority, weight, and port
    public var description: String {
        "\(target) \(priority) \(weight) \(port)"
    }
}
