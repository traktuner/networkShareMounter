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
    
    /// Checks if a given directory is within a mounted filesystem (but not necessarily a mount point itself)
    ///
    /// - Parameter atPath: The directory path to check
    /// - Returns: `true` if any parent directory is a mount point, `false` if not
    func isDirectoryWithinFilesystemMount(atPath: String) -> Bool {
        var currentPath = URL(fileURLWithPath: atPath).deletingLastPathComponent().path
        
        while currentPath != "/" && !currentPath.isEmpty {
            do {
                let systemAttributes = try attributesOfItem(atPath: currentPath)
                if let fileSystemFileNumber = systemAttributes[.systemFileNumber] as? NSNumber {
                    if fileSystemFileNumber == FileManager.filesystemMountNumber {
                        Logger.mounter.debug("🛡️ Mount protection: \(atPath, privacy: .public) is within mounted filesystem at \(currentPath, privacy: .public)")
                        return true
                    }
                }
            } catch {
                Logger.mounter.debug("Error checking mount status for \(currentPath, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
            
            let parentURL = URL(fileURLWithPath: currentPath).deletingLastPathComponent()
            let parentPath = parentURL.path
            if parentPath == currentPath { break }
            currentPath = parentPath
        }
        
        Logger.mounter.debug("🔍 Mount check: \(atPath, privacy: .public) is not within any mounted filesystem")
        return false
    }
    
    /// Checks if a path resides on a network volume (e.g., SMB, AFP, NFS)
    ///
    /// Uses URLResourceValues.volumeIsNetwork for robust detection.
    /// - Parameter atPath: Path to check
    /// - Returns: true if the path is on a network volume, false otherwise
    func isOnNetworkVolume(atPath: String) -> Bool {
        let url = URL(fileURLWithPath: atPath, isDirectory: true)
        do {
            let resourceValues = try url.resourceValues(forKeys: [.volumeIsNetworkKey])
            if let isNetwork = resourceValues.volumeIsNetwork, isNetwork == true {
                Logger.mounter.debug("🛡️ Network volume protection: \(atPath, privacy: .public) is on a network volume")
                return true
            }
        } catch {
            Logger.mounter.debug("Error checking volume type for \(atPath, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
        return false
    }
    
    /// Comprehensive mount protection check for cleanup operations
    ///
    /// Returns true if the directory is a mount point itself OR within a mounted filesystem
    /// OR if it resides on a network volume. Use this for cleanup operations where you want
    /// maximum protection.
    ///
    /// - Parameter atPath: The directory path to check
    /// - Returns: `true` if directory should be protected from deletion, `false` if safe to delete
    func shouldProtectFromDeletion(atPath: String) -> Bool {
        return isDirectoryFilesystemMount(atPath: atPath)
            || isDirectoryWithinFilesystemMount(atPath: atPath)
            || isOnNetworkVolume(atPath: atPath)
    }
}
