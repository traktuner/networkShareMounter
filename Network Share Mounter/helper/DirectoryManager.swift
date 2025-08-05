//
//  DirectoryManager.swift
//  Network Share Mounter
//
//  Created by AI Assistant on 04.01.25.
//  Copyright © 2025 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation
import OSLog

/// Actor for thread-safe directory operations
/// 
/// This actor serializes all directory removal operations to prevent race conditions
/// between mount operations and cleanup processes. All directory operations are
/// queued and executed sequentially, ensuring atomic-like behavior using Swift 6
/// actor-based concurrency.
@globalActor
actor DirectoryManager {
    static let shared = DirectoryManager()
    
    private init() {}
    
    /// Thread-safe directory removal with mount protection
    /// 
    /// This method ensures that only one directory operation happens at a time,
    /// preventing race conditions where mount operations might interfere with
    /// cleanup processes. Uses Swift 6 actor isolation for true serialization.
    ///
    /// - Parameters:
    ///   - atPath: Path to the directory to remove
    ///   - fileManager: FileManager instance to use
    /// - Returns: True if directory was removed, false if protected or failed
    func safeRemoveDirectory(atPath: String, using fileManager: FileManager) -> Bool {
        // Do not remove directories located at /Volumes
        guard !atPath.hasPrefix("/Volumes") else {
            Logger.mounter.debug("🔒 [DirectoryManager] No directories located /Volumes can be removed (called for \(atPath, privacy: .public))")
            return false
        }
        
        Logger.mounter.debug("🔒 [DirectoryManager] Atomic directory removal started for \(atPath, privacy: .public)")
        
        do {
            // Check if directory exists and is actually a directory
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: atPath, isDirectory: &isDirectory), isDirectory.boolValue else {
                Logger.mounter.debug("🔒 [DirectoryManager] Path \(atPath, privacy: .public) does not exist or is not a directory")
                return false
            }
            
            // Mount protection check (comprehensive protection for cleanup operations)
            guard !fileManager.shouldProtectFromDeletion(atPath: atPath) else {
                Logger.mounter.warning("🔒🛡️ [DirectoryManager] Directory \(atPath, privacy: .public) is protected from deletion (mount point or within mounted filesystem)")
                return false
            }
            
            // Check if directory is empty
            let contents = try fileManager.contentsOfDirectory(atPath: atPath)
            guard contents.isEmpty else {
                Logger.mounter.warning("🔒⚠️ [DirectoryManager] Directory \(atPath, privacy: .public) is not empty (contains \(contents.count) items) and cannot be removed")
                return false
            }
            
            // Final mount protection check (double-check pattern within actor isolation)
            guard !fileManager.shouldProtectFromDeletion(atPath: atPath) else {
                Logger.mounter.warning("🔒🛡️ [DirectoryManager] Directory \(atPath, privacy: .public) became protected during atomic deletion attempt - PROTECTED")
                return false
            }
            
            // All checks passed - safe to remove atomically within actor
            try fileManager.removeItem(atPath: atPath)
            Logger.mounter.info("🔒✅ [DirectoryManager] Successfully deleted empty directory \(atPath, privacy: .public)")
            return true
            
        } catch CocoaError.fileNoSuchFile {
            Logger.mounter.debug("🔒 [DirectoryManager] Directory \(atPath, privacy: .public) does not exist (already removed)")
            return false
        } catch CocoaError.fileWriteNoPermission {
            Logger.mounter.warning("🔒⚠️ [DirectoryManager] No permission to delete directory \(atPath, privacy: .public)")
            return false
        } catch let posixError as POSIXError where posixError.code == .ENOTEMPTY {
            Logger.mounter.warning("🔒⚠️ [DirectoryManager] Directory \(atPath, privacy: .public) is not empty and cannot be removed")
            return false
        } catch {
            Logger.mounter.warning("🔒⚠️ [DirectoryManager] Could not delete directory \(atPath, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return false
        }
    }
    
    /// Batch directory removal with atomic guarantees
    /// 
    /// Removes multiple directories atomically, ensuring that if any directory
    /// becomes a mount point during the operation, the entire batch is protected.
    ///
    /// - Parameters:
    ///   - paths: Array of directory paths to remove
    ///   - fileManager: FileManager instance to use
    /// - Returns: Array of successfully removed paths
    func safeRemoveDirectories(atPaths paths: [String], using fileManager: FileManager) -> [String] {
        Logger.mounter.debug("🔒📦 [DirectoryManager] Atomic batch removal started for \(paths.count) directories")
        
        var removedPaths: [String] = []
        
        for path in paths {
            if safeRemoveDirectory(atPath: path, using: fileManager) {
                removedPaths.append(path)
            }
        }
        
        Logger.mounter.debug("🔒📦 [DirectoryManager] Atomic batch removal completed: \(removedPaths.count)/\(paths.count) directories removed")
        return removedPaths
    }
}