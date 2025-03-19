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
    /// - Note: Uses bubble sort algorithm for simplicity. Consider using Swift's sort() for better performance
    func sortByWeight() -> [String]? {
        guard !SRVRecords.isEmpty else { return nil}
        
        var data_set = SRVRecords
        var swap = true
        while swap == true {
            swap = false
            for i in 0..<data_set.count - 1 {
                if data_set[i].weight > data_set[i + 1].weight {
                    let temp = data_set [i + 1]
                    data_set [i + 1] = data_set[i]
                    data_set[i] = temp
                    swap = true
                }
            }
        }
        return data_set.map({ $0.target })
    }
}

// MARK: - CustomStringConvertible Implementation
extension SRVResult: CustomStringConvertible {
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
    /// TCP/UDP port number of the service
    let port: Int
    /// Hostname of the target machine
    let target: String
    
    /// Initializes an SRV record from raw DNS response data
    /// - Parameter data: Raw DNS response bytes
    /// - Returns: nil if data is invalid or too short
    /// - Note: Current implementation has basic Unicode control character handling
    init?(data: Data) {
        guard data.count > 8 else { return nil }
        
        var workingTarget = ""
        
        priority = Int(data[0]) * 256 + Int(data[1])
        weight = Int(data[2]) * 256 + Int(data[3])
        port = Int(data[4]) * 256 + Int(data[5])
        
        // Skip byte 6 (Unicode control character)
        
        // Parse hostname from remaining bytes
        // TODO: Consider using a more robust Unicode handling approach
        for byte in data[7...(data.count - 1)] {
            if let char = String(data: Data([byte]), encoding: .utf8) {
                switch char {
                case "\u{03}", "\u{04}", "\u{05}", "\0":
                    workingTarget += "."
                default:
                    workingTarget += char
                }
            }
        }
        target = workingTarget
    }
}

// MARK: - CustomStringConvertible Implementation
extension SRVRecord: CustomStringConvertible {
    public var description: String {
        "\(target) \(priority) \(weight) \(port)"
    }
}
