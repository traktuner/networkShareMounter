//
//  Data.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 15.12.23.
//  Copyright © 2025 RRZE. All rights reserved.
//

import Foundation

extension Data {
    /// Creates a new Data instance from a hexadecimal encoded string
    /// 
    /// This initializer converts a string with hexadecimal characters (0-9, a-f, A-F)
    /// into a Data object. The string must contain an even number of characters, as
    /// each byte requires two hexadecimal digits.
    ///
    /// - Parameter string: A string containing hexadecimal characters
    /// - Returns: A new Data instance, or nil if the string contains invalid characters
    ///           or has an odd number of characters
    init?(fromHexEncodedString string: String) {
        
        // Convert 0 ... 9, a ... f, A ...F to their decimal value,
        // return nil for all other input characters
        func decodeNibble(u: UInt16) -> UInt8? {
            switch(u) {
            case 0x30 ... 0x39:
                return UInt8(u - 0x30)
            case 0x41 ... 0x46:
                return UInt8(u - 0x41 + 10)
            case 0x61 ... 0x66:
                return UInt8(u - 0x61 + 10)
            default:
                return nil
            }
        }
        
        self.init(capacity: string.utf16.count/2)
        var even = true
        var byte: UInt8 = 0
        for c in string.utf16 {
            guard let val = decodeNibble(u: c) else { return nil }
            if even {
                byte = val << 4
            } else {
                byte += val
                self.append(byte)
            }
            even = !even
        }
        guard even else { return nil }
    }
    
    /// Converts the Data instance to a hexadecimal encoded string
    ///
    /// This method transforms each byte in the Data instance into a two-character
    /// hexadecimal representation (00-ff) and joins them into a single string.
    ///
    /// - Returns: A string with the hexadecimal representation of the data
    func hexEncodedString() -> String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
}
