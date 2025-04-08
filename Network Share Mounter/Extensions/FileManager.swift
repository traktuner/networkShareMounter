//
//  FileManager.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 20.02.24.
//  Copyright © 2025 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation
import OSLog

extension FileManager {
    /// The filesystem file number for a mount point
    private static let filesystemMountNumber: NSNumber = 2
    
    /// Checks if a given path is a directory
    /// - Parameter atPath: The path to check
    /// - Returns: `true` if the path is a directory, `false` if not or if the path doesn't exist
    func isDirectory(atPath: String) -> Bool {
        var isDir: ObjCBool = ObjCBool(false)
        if fileExists(atPath: atPath, isDirectory: &isDir) {
            return isDir.boolValue
        } else {
            return false
        }
    }
    
    /// Checks if a given directory is a mount point for a (remote) filesystem
    /// - Parameter atPath: The directory path to check
    /// - Returns: `true` if the directory is a mount point, `false` if not
    func isDirectoryFilesystemMount(atPath: String) -> Bool {
        do {
            let systemAttributes = try attributesOfItem(atPath: atPath)
            if let fileSystemFileNumber = systemAttributes[.systemFileNumber] as? NSNumber {
                // Filesystem mount points have systemFileNumber 2
                return fileSystemFileNumber == FileManager.filesystemMountNumber
            }
        } catch {
            Logger.mounter.debug("Error checking mount status for \(atPath, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
        return false
    }
}
