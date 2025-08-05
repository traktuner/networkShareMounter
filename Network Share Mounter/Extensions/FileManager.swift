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
    /// This method protects against accidental deletion of subdirectories within mounted shares
    /// by checking if any parent directory is a mount point. This prevents data loss when cleanup 
    /// operations run on subdirectories of mounted SMB shares.
    ///
    /// - Parameter atPath: The directory path to check
    /// - Returns: `true` if any parent directory is a mount point, `false` if not
    func isDirectoryWithinFilesystemMount(atPath: String) -> Bool {
        var currentPath = URL(fileURLWithPath: atPath).deletingLastPathComponent().path
        
        // Iterate from parent path up to root directory (skip the target directory itself)
        while currentPath != "/" && !currentPath.isEmpty {
            do {
                let systemAttributes = try attributesOfItem(atPath: currentPath)
                if let fileSystemFileNumber = systemAttributes[.systemFileNumber] as? NSNumber {
                    // Filesystem mount points have systemFileNumber 2
                    if fileSystemFileNumber == FileManager.filesystemMountNumber {
                        Logger.mounter.debug("🛡️ Mount protection: \(atPath, privacy: .public) is within mounted filesystem at \(currentPath, privacy: .public)")
                        return true
                    }
                }
            } catch {
                Logger.mounter.debug("Error checking mount status for \(currentPath, privacy: .public): \(error.localizedDescription, privacy: .public)")
                // Continue checking parent directories even if current fails
            }
            
            // Move up one directory level
            let parentURL = URL(fileURLWithPath: currentPath).deletingLastPathComponent()
            let parentPath = parentURL.path
            
            // Prevent infinite loop if path doesn't change
            if parentPath == currentPath {
                break
            }
            currentPath = parentPath
        }
        
        Logger.mounter.debug("🔍 Mount check: \(atPath, privacy: .public) is not within any mounted filesystem")
        return false
    }
    
    /// Comprehensive mount protection check for cleanup operations
    /// 
    /// This method combines both checks: it returns true if the directory is either
    /// a mount point itself OR within a mounted filesystem. Use this for cleanup
    /// operations where you want maximum protection.
    ///
    /// - Parameter atPath: The directory path to check
    /// - Returns: `true` if directory should be protected from deletion, `false` if safe to delete
    func shouldProtectFromDeletion(atPath: String) -> Bool {
        return isDirectoryFilesystemMount(atPath: atPath) || isDirectoryWithinFilesystemMount(atPath: atPath)
    }
}
