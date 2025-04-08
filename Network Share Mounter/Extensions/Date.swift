//
//  Date.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 15.12.23.
//  Copyright © 2020 Orchard & Grove, Inc. All rights reserved.
//  Copyright © 2025 RRZE. All rights reserved.
//

import Foundation

extension Date {
    /// Calculates the number of days from now until this date
    ///
    /// This property returns the number of full days remaining until this date.
    /// If the date is in the past, it returns nil.
    ///
    /// Example:
    /// ```
    /// let futureDate = Date().addingTimeInterval(3 * 24 * 60 * 60) // 3 days in the future
    /// print(futureDate.daysToGo) // Prints "3"
    /// ```
    ///
    /// - Returns: The number of days until this date, or nil if the date is in the past
    var daysToGo: Int? {
        get {
            if self.timeIntervalSinceNow > 0 {
                return Int(self.timeIntervalSinceNow / 86400) // 86400 seconds in a day
            } else {
                return nil
            }
        }
    }
}
