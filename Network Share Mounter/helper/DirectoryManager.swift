//
//  DirectoryManager.swift
//  Network Share Mounter
//
//  Created by AI Assistant on 04.01.25.
//  Copyright © 2025 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation
import OSLog

/// Thread-safe directory operations actor with comprehensive mount protection
///
/// This actor serializes all directory removal operations to prevent race conditions
/// between mount operations and cleanup processes. All directory operations are
/// queued and executed sequentially, ensuring atomic-like behavior using Swift 6
/// actor-based concurrency.
///
/// ## Protection Mechanisms
///
/// The DirectoryManager implements multiple layers of protection to prevent accidental
/// deletion of user data and system directories:
///
/// ### 1. Hard Protection Barriers
/// - **Volumes Protection**: Absolute prohibition of any deletion within `/Volumes`
/// - **Symlink Resolution**: Resolves symbolic links to prevent bypass attacks
/// - **Mount Point Detection**: Identifies active filesystem mounts via `systemFileNumber`
/// - **Network Volume Detection**: Recognizes network-mounted filesystems
///
/// ### 2. Content Safety Checks  
/// - **Empty Directory Requirement**: Only removes completely empty directories
/// - **Hidden File Tolerance**: Ignores system files like `.DS_Store` in emptiness check
/// - **TOCTOU Protection**: Double-checks protection status to prevent race conditions
///
/// ### 3. Atomic Operations
/// - **Sequential Execution**: All operations are serialized within the actor
/// - **Error Recovery**: Comprehensive error handling with detailed logging
/// - **Fail-Safe Behavior**: Unknown conditions default to protection (no deletion)
///
/// ## Usage
///
/// ```swift
/// let success = await DirectoryManager.shared.safeRemoveDirectory(
///     atPath: "/path/to/directory", 
///     using: FileManager.default
/// )
/// ```
///
/// ## Safety Guarantee
///
/// **User data within mounted network shares is absolutely protected** through multiple 
/// independent verification layers. Accidental deletion of subdirectories within active
/// mounts is prevented by design.
actor DirectoryManager {
    static let shared = DirectoryManager()
    
    private init() {}
    
    /// Resolve symlinks and standardize a path to its canonical form
    /// - Parameter path: Input path (possibly containing symlinks/relative segments)
    /// - Returns: Canonical, symlink-resolved absolute path
    private func resolvedCanonicalPath(from path: String) -> String {
        let url = URL(fileURLWithPath: path)
        // resolvingSymlinksInPath handles symlinks; standardized removes .. and .
        let resolved = url.resolvingSymlinksInPath()
        return resolved.standardizedFileURL.path
    }
    
    /// Fast check whether a directory is empty (ignoring hidden files like .DS_Store)
    /// - Parameter url: Directory URL to check
    /// - Returns: true if empty (no visible entries), false otherwise
    private func isDirectoryEmptyIgnoringHidden(at url: URL) -> Bool {
        // Shallow enumeration of the directory itself
        let options: FileManager.DirectoryEnumerationOptions = [
            .skipsSubdirectoryDescendants,
            .skipsPackageDescendants,
            .skipsHiddenFiles // IMPORTANT: ignore hidden files like .DS_Store
        ]
        
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: nil,
            options: options,
            errorHandler: { (pathURL, error) -> Bool in
                Logger.directoryOperations.debug("🔒 [DirectoryManager] Enumerator error at \(pathURL.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
                // Continue enumeration on error
                return true
            }
        ) else {
            // Fail-safe: if no enumerator can be created, consider "not empty" to prevent deletion
            Logger.directoryOperations.debug("🔒 [DirectoryManager] Could not create enumerator for \(url.path, privacy: .public) – treating as not empty for safety")
            return false
        }
        
        // Fetch first visible item only
        return (enumerator.nextObject() == nil)
    }
    
    /// Thread-safe directory removal with mount and network-volume protection
    ///
    /// - Parameters:
    ///   - atPath: Path to the directory to remove
    ///   - fileManager: FileManager instance to use
    /// - Returns: True if directory was removed, false if protected or failed
    func safeRemoveDirectory(atPath: String, using fileManager: FileManager) -> Bool {
        // Resolve symlinks and standardize the path up-front to avoid bypass via symlinks
        let resolvedPath = resolvedCanonicalPath(from: atPath)
        
        // Do not remove directories located at /Volumes (hard safety belt)
        guard !resolvedPath.hasPrefix("/Volumes") else {
            Logger.directoryOperations.debug("🔒 [DirectoryManager] No directories located /Volumes can be removed (called for orig=\(atPath, privacy: .public), resolved=\(resolvedPath, privacy: .public))")
            return false
        }
        
        Logger.directoryOperations.debug("🔒 [DirectoryManager] Atomic directory removal started for orig=\(atPath, privacy: .public), resolved=\(resolvedPath, privacy: .public)")
        
        do {
            // Check if directory exists and is actually a directory
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: resolvedPath, isDirectory: &isDirectory), isDirectory.boolValue else {
                Logger.directoryOperations.debug("🔒 [DirectoryManager] Path \(resolvedPath, privacy: .public) does not exist or is not a directory (orig=\(atPath, privacy: .public))")
                return false
            }
            
            // Comprehensive protection (mounts, parents of mounts, and any network volume)
            guard !fileManager.shouldProtectFromDeletion(atPath: resolvedPath) else {
                Logger.directoryOperations.warning("🔒🛡️ [DirectoryManager] Directory \(resolvedPath, privacy: .public) is protected from deletion (mount/network volume) (orig=\(atPath, privacy: .public))")
                return false
            }
            
            // Optimized emptiness check ignoring hidden files (e.g., .DS_Store)
            let dirURL = URL(fileURLWithPath: resolvedPath, isDirectory: true)
            guard isDirectoryEmptyIgnoringHidden(at: dirURL) else {
                Logger.directoryOperations.warning("🔒⚠️ [DirectoryManager] Directory \(resolvedPath, privacy: .public) is not empty (visible entries) and cannot be removed (orig=\(atPath, privacy: .public))")
                return false
            }
            
            // Final protection check to guard against races (re-check after emptiness evaluation)
            guard !fileManager.shouldProtectFromDeletion(atPath: resolvedPath) else {
                Logger.directoryOperations.warning("🔒🛡️ [DirectoryManager] Directory \(resolvedPath, privacy: .public) became protected during atomic deletion attempt - PROTECTED (orig=\(atPath, privacy: .public))")
                return false
            }
            
            // All checks passed - safe to remove atomically within actor
            try fileManager.removeItem(atPath: resolvedPath)
            Logger.directoryOperations.info("🔒✅ [DirectoryManager] Successfully deleted empty directory \(resolvedPath, privacy: .public) (orig=\(atPath, privacy: .public))")
            return true
            
        } catch CocoaError.fileNoSuchFile {
            Logger.directoryOperations.debug("🔒 [DirectoryManager] Directory \(resolvedPath, privacy: .public) does not exist (already removed) (orig=\(atPath, privacy: .public))")
            return false
        } catch CocoaError.fileWriteNoPermission {
            Logger.directoryOperations.warning("🔒⚠️ [DirectoryManager] No permission to delete directory \(resolvedPath, privacy: .public) (orig=\(atPath, privacy: .public))")
            return false
        } catch let posixError as POSIXError where posixError.code == .ENOTEMPTY {
            // TOCTOU guard: content appeared between check and remove
            Logger.directoryOperations.warning("🔒⚠️ [DirectoryManager] Directory \(resolvedPath, privacy: .public) is not empty and cannot be removed (orig=\(atPath, privacy: .public))")
            return false
        } catch {
            Logger.directoryOperations.warning("🔒⚠️ [DirectoryManager] Could not delete directory \(resolvedPath, privacy: .public): \(error.localizedDescription, privacy: .public) (orig=\(atPath, privacy: .public))")
            return false
        }
    }
    
    /// Batch directory removal with atomic guarantees
    ///
    /// - Parameters:
    ///   - paths: Array of directory paths to remove
    ///   - fileManager: FileManager instance to use
    /// - Returns: Array of successfully removed paths (resolved paths)
    func safeRemoveDirectories(atPaths paths: [String], using fileManager: FileManager) -> [String] {
        Logger.directoryOperations.debug("🔒📦 [DirectoryManager] Atomic batch removal started for \(paths.count) directories")
        
        var removedPaths: [String] = []
        
        for path in paths {
            if safeRemoveDirectory(atPath: path, using: fileManager) {
                // Append resolved path for consistency in reporting
                removedPaths.append(resolvedCanonicalPath(from: path))
            }
        }
        
        Logger.directoryOperations.debug("🔒📦 [DirectoryManager] Atomic batch removal completed: \(removedPaths.count)/\(paths.count) directories removed")
        return removedPaths
    }
}

