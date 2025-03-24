//
//  URL.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 15.12.23.
//  Copyright © 2025 RRZE. All rights reserved.
//

import Foundation

extension URL {
    /// Checks if a file exists at the URL's path
    ///
    /// This method verifies whether a file or directory exists at the location
    /// specified by this URL's path.
    ///
    /// Example:
    /// ```
    /// let fileURL = URL(fileURLWithPath: "/path/to/file.txt")
    /// if fileURL.checkFileExist() {
    ///     print("File exists")
    /// } else {
    ///     print("File does not exist")
    /// }
    /// ```
    ///
    /// - Returns: `true` if a file exists at the path, `false` otherwise
    func checkFileExist() -> Bool {
        return FileManager.default.fileExists(atPath: self.path)
    }
}
