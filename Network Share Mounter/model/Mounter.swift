//
//  Mounter.swift
//  Network Share Mounter
//
//  Created by Gregor Longariva on 24.11.21.
//  Copyright © 2024 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation
import NetFS
import SystemConfiguration
import OpenDirectory
import AppKit
import OSLog

// swiftlint:disable type_body_length
/// Class responsible for performing mount/unmount operations for network shares.
/// This class manages the entire lifecycle of network shares, including:
/// - Mounting and unmounting network shares
/// - Managing share status and properties
/// - Handling connection errors and authentication issues
/// - Creating and cleaning up mount points
///
/// The implementation uses Swift actors for thread safety in asynchronous contexts,
/// making it compatible with Swift's concurrency model and Swift 6.
class Mounter: ObservableObject {
    var prefs = PreferenceManager()
    @Published var shareManager = ShareManager()
    
    /// Published error status that automatically notifies observers
    @Published private var _errorStatus: MounterError = .noError
    
    /// Current error status with automatic SwiftUI updates
    var errorStatus: MounterError {
        _errorStatus
    }
    
    /// Convenience reference to the default FileManager
    private let fm = FileManager.default
    
    /// Actor for thread-safe management of mount tasks
    /// This ensures that task collection operations are atomic and thread-safe
    /// in asynchronous contexts, preventing race conditions.
    private actor TaskController {
        /// Collection of active mount tasks
        var mountTasks = Set<Task<Void, Never>>()
        
        /// Adds a single task to the collection
        /// - Parameter task: The task to add
        func addTask(_ task: Task<Void, Never>) {
            mountTasks.insert(task)
        }
        
        /// Replaces the entire task collection with a new set
        /// - Parameter tasks: Array of tasks to set
        func setTasks(_ tasks: [Task<Void, Never>]) {
            mountTasks = Set(tasks)
        }
        
        /// Returns the current set of tasks
        /// - Returns: The current set of active mount tasks
        func getTasks() -> Set<Task<Void, Never>> {
            return mountTasks
        }
        
        /// Cancels all active tasks and clears the collection
        func cancelAndClearTasks() {
            mountTasks.forEach { $0.cancel() }
            mountTasks.removeAll()
        }
    }
    
    /// Thread-safe controller for mount tasks
    private let taskController = TaskController()
    
    /// Home directory path for the current user
    let userHomeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    
    /// Thread-safety lock for error status access
    private let _errorStatusLock = NSRecursiveLock()
    
    /// Sets the error status and handles notifications
    /// - Parameter newValue: The new error status to set
    @MainActor
    func setErrorStatus(_ newValue: MounterError) {
        let oldValue = _errorStatus
        
        // Check if there is a switch to an authentication error (from a non-authentication error)
        let isNewAuthError = (newValue == .authenticationError || newValue == .krbAuthenticationError)
        let wasNotAuthError = (oldValue != .authenticationError && oldValue != .krbAuthenticationError)
        let shouldPostAuthError = isNewAuthError && wasNotAuthError
        
        _errorStatus = newValue
        
        if shouldPostAuthError {
            Logger.mounter.debug("🔔 First auth error occurred: changed from \(oldValue, privacy: .public) to \(newValue, privacy: .public)")
            
            // Send the appropriate notification based on the type of error
            if newValue == .authenticationError {
                NotificationCenter.default.post(
                    name: .nsmNotification,
                    object: nil,
                    userInfo: ["AuthError": MounterError.authenticationError]
                )
            } else if newValue == .krbAuthenticationError {
                NotificationCenter.default.post(
                    name: .nsmNotification,
                    object: nil,
                    userInfo: ["KrbAuthError": MounterError.krbAuthenticationError]
                )
            }
        }
    }
    
    /// Localized folder name based on user's language settings
    private var localizedFolder = Defaults.translation["en"]!
    
    /// Default path where network shares will be mounted
    var defaultMountPath: String = Defaults.defaultMountPath
    
    /// Standard initializer
    init() {
    }
        
    /// Performs asynchronous initialization of the Mounter
    ///
    /// This method:
    /// - Configures the localized directory names based on preferences
    /// - Sets up the default mount path
    /// - Creates the necessary mount folders
    /// - Initializes the share array with MDM and user-defined shares
    /// - Attempts to add the user's home directory (if in AD/Kerberos environment)
    func asyncInit() async {
        // Determine whether to use localized folder names based on preference
        if prefs.bool(for: .useLocalizedMountDirectories, defaultValue: false) {
            // Use language-specific folder name if preference is enabled
            self.localizedFolder = Defaults.translation[Locale.current.languageCode!] ?? Defaults.translation["en"]!
            Logger.mounter.debug("Using localized folder name: \(self.localizedFolder, privacy: .public)")
        } else {
            // Always use English name for backward compatibility
            self.localizedFolder = Defaults.translation["en"]!
            Logger.mounter.debug("Using default English folder name for compatibility: \(self.localizedFolder, privacy: .public)")
        }
        
        // Define and create the directory where shares will be mounted
        // For future release: use Defaults.defaultMountPath (aka /Volumes) as default location
        if prefs.bool(for: .useNewDefaultLocation) {
            self.defaultMountPath = Defaults.defaultMountPath
        } else {
            // Use actual/legacy default location
            self.defaultMountPath = NSString(string: "~/\(localizedFolder)").expandingTildeInPath
        }
        // Set default mount location to profile-defined value if available
        if let location = prefs.string(for: .location), !location.isEmpty {
            self.defaultMountPath = NSString(string: prefs.string(for: .location)!).expandingTildeInPath
        }
        Logger.mounter.debug("defaultMountPath is \(self.defaultMountPath, privacy: .public)")
        createMountFolder(atPath: self.defaultMountPath)
        
        // Initialize the shareArray containing MDM and user defined shares
        await shareManager.createShareArray()
    }
    
    /// Adds a share to the list of managed shares
    ///
    /// This method checks if there is already a share with the same network export path.
    /// If not, it adds the given share to the array of shares.
    ///
    /// - Parameter share: The share object to check and append to shares array
    func addShare(_ share: Share) async {
        await shareManager.addShare(share)
        NotificationCenter.default.post(name: Defaults.nsmReconstructMenuTriggerNotification, object: nil)
    }
    
    /// Removes a share from the managed shares list
    ///
    /// - Parameter share: The share to remove
    func removeShare(for share: Share) async {
        if let index = await shareManager.allShares.firstIndex(where: { $0.id == share.id }) {
            Logger.mounter.info("Deleting share: \(share.networkShare, privacy: .public) at Index \(index, privacy: .public)")
            await shareManager.removeShare(at: index)
        }
    }
    
    /// Updates a share object at a specific index and updates the shares array
    ///
    /// - Parameter share: The share with updated properties
    func updateShare(for share: Share) async {
        if let index = await shareManager.allShares.firstIndex(where: { $0.networkShare == share.networkShare }) {
            do {
                try await shareManager.updateShare(at: index, withUpdatedShare: share)
            } catch ShareError.invalidIndex(let index) {
                Logger.shareManager.error("❌ Could not update share \(share.networkShare, privacy: .public), index \(index, privacy: .public) is not valid.")
            } catch {
                Logger.shareManager.error("❌ Could not update share \(share.networkShare, privacy: .public), unknown error.")
            }
        }
    }
    
    /// Retrieves a share by its network path
    ///
    /// - Parameter networkShare: The network path to search for
    /// - Returns: The matching share, or nil if not found
    func getShare(forNetworkShare networkShare: String) async -> Share? {
        for share in await self.shareManager.allShares {
            if share.networkShare == networkShare {
                return share
            }
        }
        return nil
    }
    
    /// Updates the mount status for a share
    ///
    /// - Parameters:
    ///   - mountStatus: The new mount status to set
    ///   - share: The share to update
    func updateShare(mountStatus: MountStatus, for share: Share) async {
        // No lock needed as shareManager is already an actor
        if let index = await shareManager.allShares.firstIndex(where: { $0.networkShare == share.networkShare }) {
            do {
                try await shareManager.updateMountStatus(at: index, to: mountStatus)
                NotificationCenter.default.post(name: Defaults.nsmReconstructMenuTriggerNotification, object: nil)
            } catch ShareError.invalidIndex(let index) {
                Logger.shareManager.error("❌ Could not update mount status for share \(share.networkShare, privacy: .public), index \(index, privacy: .public) is not valid.")
                NotificationCenter.default.post(name: Defaults.nsmReconstructMenuTriggerNotification, object: nil)
            } catch {
                Logger.shareManager.error("❌ Could not update mount status for share \(share.networkShare, privacy: .public), unknown error.")
                NotificationCenter.default.post(name: Defaults.nsmReconstructMenuTriggerNotification, object: nil)
            }
        }
    }
    
    /// Updates the actual mount point for a share
    ///
    /// - Parameters:
    ///   - actualMountPoint: An optional string defining where the share is mounted (or nil if not mounted)
    ///   - share: The share to update
    func updateShare(actualMountPoint: String?, for share: Share) async {
        // No lock needed as shareManager is already an actor
        if let index = await shareManager.allShares.firstIndex(where: { $0.networkShare == share.networkShare }) {
            do {
                try await shareManager.updateActualMountPoint(at: index, to: actualMountPoint)
            } catch ShareError.invalidIndex(let index) {
                Logger.shareManager.error("❌ Could not update actual mount point for share \(share.networkShare, privacy: .public), index \(index, privacy: .public) is not valid.")
            } catch {
                Logger.shareManager.error("❌ Could not update actual mount point for share \(share.networkShare, privacy: .public), unknown error.")
            }
        }
    }
   
    /// Creates the parent folder where network shares will be mounted
    ///
    /// This method checks if the specified directory exists and creates it if necessary.
    /// It will exit the application with code 2 if it fails to create the directory.
    ///
    /// - Parameter mountPath: The path where the folder will be created
    func createMountFolder(atPath mountPath: String) {
        do {
            // Try to create (if not exists) the directory where the network shares will be mounted
            if !fm.fileExists(atPath: mountPath) {
                try fm.createDirectory(atPath: mountPath, withIntermediateDirectories: false, attributes: nil)
                Logger.mounter.info("Base network mount directory \(mountPath, privacy: .public): created")
            }
        } catch {
            Logger.mounter.error("❌ Error creating mount folder: \(mountPath, privacy: .public):")
            Logger.mounter.error("\(error.localizedDescription, privacy: .public)")
            exit(2)
        }
    }
    

    
    /// Safely escapes a path for use in shell commands
    ///
    /// This method properly escapes paths that contain special characters
    /// to prevent shell injection attacks when the path is used in shell commands.
    ///
    /// - Parameter path: The path to escape
    /// - Returns: A properly escaped path string safe for use in shell commands
    private func escapePath(_ path: String) -> String {
        // Use single quotes which handle most special characters
        // But escape single quotes within the path by replacing ' with '\''
        return "'\(path.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
    
    /// Removes a directory using Swift 6 Actor-based atomic operations
    ///
    /// This method uses the DirectoryManager actor to ensure true serialization
    /// of directory removal operations, preventing race conditions with mount
    /// operations through Swift 6's actor-based concurrency model.
    ///
    /// - Parameter atPath: Full path of the directory to remove
    func removeDirectory(atPath: String) {
        Task {
            let success = await DirectoryManager.shared.safeRemoveDirectory(atPath: atPath, using: fm)
            if !success {
                Logger.mounter.debug("Directory removal failed or was protected: \(atPath, privacy: .public)")
            }
        }
    }
    
    /// Synchronous version of removeDirectory for cases where async is not suitable
    ///
    /// This method blocks the current thread until the directory removal is complete.
    /// Use only when you need synchronous behavior and cannot use async/await.
    ///
    /// - Parameter atPath: Full path of the directory to remove
    /// - Returns: True if directory was removed, false if protected or failed
    func removeDirectorySync(atPath: String) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var result = false
        
        Task {
            result = await DirectoryManager.shared.safeRemoveDirectory(atPath: atPath, using: fm)
            semaphore.signal()
        }
        
        semaphore.wait()
        return result
    }

    
    /// Deletes unwanted files and empty directories in mount locations
    ///
    /// This function cleans up:
    /// - Unwanted files (like .DS_Store) if filename parameter is provided
    /// - Empty directories if filename parameter is nil
    ///
    /// - Parameters:
    ///   - path: The path of the directory containing the mountpoints
    ///   - filename: Optional name of file to delete if found (if nil, directories are processed)
    func deleteUnneededFiles(path: String, filename: String?) async {
        do {
            var filePaths = try fm.contentsOfDirectory(atPath: path)
            filePaths.append("/")
            for filePath in filePaths {
                // Check if directory should be protected from deletion
                // If directory is safe to clean up, proceed
                if !fm.shouldProtectFromDeletion(atPath: path.appendingPathComponent(filePath)) {
                    // Clean up the directory containing the mounts only if defined in userdefaults
                    if prefs.bool(for: .cleanupLocationDirectory) == true {
                        // If the function has a parameter we want to handle files, not directories
                        if let unwrappedFilename = filename {
                            if !fm.shouldProtectFromDeletion(atPath: path.appendingPathComponent(filePath)) {
                                let deleteFile = path.appendingPathComponent(filePath).appendingPathComponent(unwrappedFilename)
                                if fm.fileExists(atPath: deleteFile) {
                                    Logger.mounter.info("⌫  Deleting obstructing file \(deleteFile, privacy: .public)")
                                    try fm.removeItem(atPath: deleteFile)
                                }
                            } else {
                                Logger.mounter.info("🔍 Directory \(path.appendingPathComponent(filePath), privacy: .public) is protected from deletion")
                            }
                        } else {
                            // Else we have a directory to remove
                            // Do not remove the top level directory containing the mountpoints
                            if filePath != "/" {
                                let deleteFile = path.appendingPathComponent(filePath)
                                removeDirectory(atPath: URL(string: deleteFile)!.relativePath)
                            }
                        }
                    }
                } else {
                    // Directory is protected (mount point or within mounted filesystem).
                    // Now let's check if there is some SHARE-1, SHARE-2, ... mount and unmount it
                    //
                    // Compare list of shares with mount
                    for share in await self.shareManager.allShares {
                        if let shareDirName = URL(string: share.networkShare) {
                            // Get the last component of the share, since this is the name of the mount-directory
                            if let shareMountDir = shareDirName.pathComponents.last {
                                // Ignore if the mount is correct (both shareDir and mountedDir have the same name)
                                if filePath != shareMountDir {
                                    // Rudimentary check for XXX-1, XXX-2, ... mountdirs
                                    // This could be done better (e.g. regex matching), but it's sufficient
                                    for count in 1...30 {
                                        if filePath.contains(shareMountDir + "-\(count)") {
                                            Logger.mounter.info("👯 Duplicate mount of \(share.networkShare, privacy: .public): it is already mounted as \(path.appendingPathComponent(filePath), privacy: .public). Trying to unmount...")
                                            let result = await unmountShare(atPath: path.appendingPathComponent(filePath))
                                            switch result {
                                            case .success:
                                                Logger.mounter.info("💪 Successfully unmounted \(path.appendingPathComponent(filePath), privacy: .public).")
                                            case .failure(let error):
                                                // Error on unmount
                                                switch error {
                                                case .invalidMountPath:
                                                    Logger.mounter.warning("⚠️ Could not unmount \(path.appendingPathComponent(filePath), privacy: .public): invalid mount path")
                                                case .unmountFailed:
                                                    Logger.mounter.warning("⚠️ Could not unmount \(path.appendingPathComponent(filePath), privacy: .public): unmount failed")
                                                default:
                                                    Logger.mounter.info("⚠️ Could not unmount \(path.appendingPathComponent(filePath), privacy: .public): unknown error")
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } catch let error as NSError {
            Logger.mounter.error("⚠️ Could not list directory at \(path, privacy: .public): \(error.debugDescription, privacy: .public)")
        }
    }
    
    /// Unmounts a share at a given path
    ///
    /// - Parameter path: Path where the share is mounted
    /// - Returns: Result indicating success or failure with error details
    func unmountShare(atPath path: String, skipFinderRefresh: Bool = false) async -> Result<Void, MounterError> {
        // Check if path is really a filesystem mount
        if fm.isDirectoryFilesystemMount(atPath: path) || path.hasPrefix("/Volumes") {
            Logger.mounter.info("Trying to unmount share at path \(path, privacy: .public)")
            
            let url = URL(fileURLWithPath: path)
            do {
                try await fm.unmountVolume(at: url, options: [.allPartitionsAndEjectDisk, .withoutUI])
                removeDirectory(atPath: URL(string: url.absoluteString)!.relativePath)
                
                // Refresh Finder for specific unmounted path (use killall for unmount)
                if !skipFinderRefresh {
                    let finderController = FinderController()
                    await finderController.refreshFinder(forPaths: [path], isUnmountOperation: true)
                }
                
                return .success(())
            } catch {
                return .failure(.unmountFailed)
            }
        } else {
            return .failure(.invalidMountPath)
        }
    }
    
    /// Unmounts a specific share if it is currently mounted
    ///
    /// - Parameters:
    ///   - share: The share to unmount
    ///   - userTriggered: Whether the unmount was triggered by user action (defaults to false)
    func unmountShare(for share: Share, userTriggered: Bool = false) async {
        if let mountpoint = share.actualMountPoint {
            let result = await unmountShare(atPath: mountpoint)
            switch result {
            case .success:
                Logger.mounter.info("💪 Successfully unmounted \(mountpoint, privacy: .public).")
                // Share status update
                if userTriggered {
                    // If unmount was triggered by the user, set mountStatus in share to userUnmounted
                    await updateShare(mountStatus: .userUnmounted, for: share)
                } else {
                    // Else set share mountStatus to unmounted
                    await updateShare(mountStatus: .unmounted, for: share)
                }
                // Remove/undefine share mountpoint
                await updateShare(actualMountPoint: nil, for: share)
            case .failure(let error):
                // Error on unmount
                switch error {
                case .invalidMountPath:
                    Logger.mounter.warning("⚠️ Could not unmount \(mountpoint, privacy: .public): invalid mount path")
                    await updateShare(mountStatus: .undefined, for: share)
                    await updateShare(actualMountPoint: nil, for: share)
                case .unmountFailed:
                    Logger.mounter.warning("⚠️ Could not unmount \(mountpoint, privacy: .public): unmount failed")
                    await updateShare(mountStatus: .undefined, for: share)
                    await updateShare(actualMountPoint: nil, for: share)
                default:
                    Logger.mounter.info("⚠️ Could not unmount \(mountpoint, privacy: .public): unknown error")
                    await updateShare(mountStatus: .undefined, for: share)
                    await updateShare(actualMountPoint: nil, for: share)
                }
            }
        }
    }
    
    /// Unmounts all currently mounted shares
    ///
    /// This method iterates through all shares that have an actual mount point
    /// and attempts to unmount each one. After unmounting, it restarts the Finder
    /// and prepares mount prerequisites.
    ///
    /// - Parameter userTriggered: Whether the unmount was triggered by user action (defaults to false)
    func unmountAllMountedShares(userTriggered: Bool = false) async {
        for share in await shareManager.allShares {
            if let mountpoint = share.actualMountPoint {
                let result = await unmountShare(atPath: mountpoint, skipFinderRefresh: true)
                switch result {
                case .success:
                    Logger.mounter.info("💪 Successfully unmounted \(mountpoint, privacy: .public).")
                    // Share status update
                    if userTriggered {
                        // If unmount was triggered by the user, set mountStatus in share to userUnmounted
                        await updateShare(mountStatus: .userUnmounted, for: share)
                    } else {
                        // Else set share mountStatus to unmounted
                        await updateShare(mountStatus: .unmounted, for: share)
                    }
                    // Remove/undefine share mountpoint
                    await updateShare(actualMountPoint: nil, for: share)
                case .failure(let error):
                    // Error on unmount
                    switch error {
                    case .invalidMountPath:
                        Logger.mounter.warning("⚠️ Could not unmount \(mountpoint, privacy: .public): invalid mount path")
                        await updateShare(mountStatus: .undefined, for: share)
                        await updateShare(actualMountPoint: nil, for: share)
                    case .unmountFailed:
                        Logger.mounter.warning("⚠️ Could not unmount \(mountpoint, privacy: .public): unmount failed")
                        await updateShare(mountStatus: .undefined, for: share)
                        await updateShare(actualMountPoint: nil, for: share)
                    default:
                        Logger.mounter.info("⚠️ Could not unmount \(mountpoint, privacy: .public): unknown error")
                        await updateShare(mountStatus: .undefined, for: share)
                        await updateShare(actualMountPoint: nil, for: share)
                    }
                }
            }
        }
         // Refresh Finder view to reflect unmount changes (use killall for unmount)
         let finderController = FinderController()
         let mountPaths = await finderController.getActualMountPaths(from: self)
         await finderController.refreshFinder(forPaths: mountPaths, isUnmountOperation: true)
        await prepareMountPrerequisites()
    }
    
    /// Prepares the parent directory where shares will be mounted
    ///
    /// This method:
    /// - Deletes unwanted files defined in Defaults.filesToDelete
    /// - Cleans up parent directories of share mount points to avoid
    ///   creating new mount-points like projekte-1, projekte-2, etc.
    func prepareMountPrerequisites() async {
        // Iterate through all files defined in config file (e.g. .autodiskmounted, .DS_Store)
        for toDelete in Defaults.filesToDelete {
            await deleteUnneededFiles(path: self.defaultMountPath, filename: toDelete)
        }

        // The directory with the mounts for the network-shares should be empty. All
        // former directories not deleted by the mounter should be removed to avoid
        // creating new mount-points (=> directories) like projekte-1 projekte-2 and so on
        
        // TODO: check if this is not too dangerous
        for share in await shareManager.allShares {
            // Check if there is a specific mountpoint for the share. If yes, get the
            // parent directory. This is the path where the mountpoint itself is located
            if let path = share.mountPoint {
                let url = URL(fileURLWithPath: path)
                // Remove the last component (aka mountpoint) to get the containing
                // parent directory
                let parentDirectory = url.deletingLastPathComponent().path
                await deleteUnneededFiles(path: parentDirectory, filename: nil)
            }
        }
        // Look for unneeded files at the defaultMountPath
        // await deleteUnneededFiles(path: self.defaultMountPath, filename: nil)
    }
    
    /// Mounts network shares either individually or in batch
    ///
    /// This method:
    /// - Checks for active network connection
    /// - Can mount a specific share (by ID) or all configured shares
    /// - Creates concurrent tasks for mounting multiple shares simultaneously
    /// - Handles mount failures and updates share status accordingly
    /// - Implements timeout protection for mount operations
    ///
    /// - Parameters:
    ///   - userTriggered: Whether the mount operation was initiated by user
    ///   - shareID: Optional ID of specific share to mount. If nil, mounts all configured shares
    func mountGivenShares(userTriggered: Bool = false, forShare shareID: String? = nil) async {
        // Thread-safe task management via actor
        await taskController.cancelAndClearTasks()
        
        // Verify network connectivity before attempting mount operations
        let netConnection = Monitor.shared
        
        guard netConnection.netOn else {
            Logger.mounter.warning("⚠️ No network connection available, connection type is \(netConnection.connType.rawValue, privacy: .public). Skipping mount operation.")
            return
        }
        
        Logger.mounter.debug("🌐 Network is available, preparing to mount shares")
        let allShares = await self.shareManager.allShares
        if allShares.isEmpty {
            Logger.mounter.info("ℹ️ No shares configured. Nothing to mount.")
            return
        }
        
        var sharesToMount: [Share]
        
        // Filter shares based on provided shareID
        if let shareID = shareID {
            Logger.mounter.debug("🎯 Mounting single share with ID: \(shareID, privacy: .public)")
            if let specificShare = allShares.first(where: { $0.id == shareID }) {
                sharesToMount = [specificShare]
                Logger.mounter.debug("Found share to mount: \(specificShare.networkShare, privacy: .public)")
            } else {
                Logger.mounter.error("❌ Share with ID \(shareID, privacy: .public) not found.")
                return
            }
        } else {
            sharesToMount = allShares
            Logger.mounter.debug("🔄 Preparing to mount \(sharesToMount.count, privacy: .public) shares in parallel")
        }
        
        Logger.mounter.debug("📋 Shares to mount: \(sharesToMount.map { $0.networkShare }.joined(separator: ", "), privacy: .public)")
        
        // Create concurrent mount tasks for each share
        var localMountTasks: [Task<Void, Never>] = []
        
        for share in sharesToMount {
            let mountTask = Task {
                Logger.mounter.debug("--- [Task Start] Processing share: \(share.networkShare, privacy: .public) ---")
                
                do {
                    // Reset mount status for user-triggered mounts or if specifically mounting this share
                    if userTriggered || shareID == share.id {
                        Logger.mounter.debug("🔄 Resetting mount status for \(share.networkShare, privacy: .public)")
                        await updateShare(mountStatus: .undefined, for: share)
                    }
                    
                    // Attempt to mount the share with timeout protection
                    let mountResult = try await withThrowingTaskGroup(of: String.self) { group -> String in
                        group.addTask {
                            // The actual mount operation
                            return try await self.mountShare(forShare: share,
                                                           atPath: self.defaultMountPath,
                                                           userTriggered: userTriggered)
                        }
                        
                        // Wait for the first result or timeout
                        guard let result = try await group.next() else {
                            throw MounterError.timedOutHost
                        }
                        
                        // Cancel any remaining tasks
                        group.cancelAll()
                        return result
                    }
                    
                    // Success Case - Mount successful
                    Logger.mounter.debug("✅ Mount call finished successfully for \(share.networkShare, privacy: .public)")
                    await updateShare(actualMountPoint: mountResult, for: share)
                    await updateShare(mountStatus: .mounted, for: share)
                    Logger.mounter.info("📊 Share mount complete: \(share.networkShare, privacy: .public) -> \(mountResult, privacy: .public)")
                    
                } catch {
                    // Failure Case - Mount failed
                    Logger.mounter.error("❌ Mount failed for \(share.networkShare, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    await handleMountError(error, for: share)
                }
                
                Logger.mounter.debug("--- [Task End] Finished processing share: \(share.networkShare, privacy: .public) ---")
            }
            
            localMountTasks.append(mountTask)
        }
        
        // Thread-safe task collection update
        await taskController.setTasks(localMountTasks)
        
        // Wait for all mount tasks to complete
        Logger.mounter.info("⏳ Waiting for all mount operations to complete...")
        
        await withTaskGroup(of: Void.self) { group in
            for task in localMountTasks {
                group.addTask {
                    await task.value
                }
            }
        }
        
        // Log final mount status for all shares
        Logger.mounter.info("📊 Parallel mount process finished. Final mount status summary:")
        for share in await shareManager.allShares {
            if let mountPoint = share.actualMountPoint {
                Logger.mounter.info("  ✅ \(share.networkShare, privacy: .public) → mounted at: \(mountPoint, privacy: .public)")
            } else {
                Logger.mounter.info("  ❌ \(share.networkShare, privacy: .public) → not mounted (status: \(share.mountStatus.rawValue, privacy: .public))")
            }
        }
        
        Logger.mounter.debug("🏁 mountGivenShares operation completed")
    }
    
    /// Helper function to handle errors during the mount process and update share status.
    /// - Parameters:
    ///   - error: The error encountered during mounting.
    ///   - share: The share that failed to mount.
    private func handleMountError(_ error: Error, for share: Share) async {
        switch error {
        case MounterError.doesNotExist:
            Logger.mounter.debug("❌ Share does not exist: \(share.networkShare, privacy: .public)")
            await updateShare(mountStatus: .errorOnMount, for: share)
        case MounterError.timedOutHost, MounterError.hostIsDown, MounterError.noRouteToHost:
            Logger.mounter.debug("❌ Host unreachable: \(share.networkShare, privacy: .public)")
            await updateShare(mountStatus: .unreachable, for: share)
        case MounterError.authenticationError:
            Logger.mounter.debug("❌ Authentication error: \(share.networkShare, privacy: .public)")
            // Distinguish between Kerberos SSO errors and username/password errors
            if share.authType == .krb {
                Logger.mounter.debug("🔑 Kerberos authentication error for: \(share.networkShare, privacy: .public)")
                await setErrorStatus(.krbAuthenticationError)
            } else {
                Logger.mounter.debug("👤 Username/Password authentication error for: \(share.networkShare, privacy: .public)")
                await setErrorStatus(.authenticationError)
            }
            await updateShare(mountStatus: .invalidCredentials, for: share)
        case MounterError.shareDoesNotExist:
            Logger.mounter.debug("❌ Share does not exist on server: \(share.networkShare, privacy: .public)")
            await updateShare(mountStatus: .errorOnMount, for: share)
        case MounterError.mountIsQueued:
            // This state should ideally not be reached in sequential processing, but handle defensively
            Logger.mounter.debug("⏳ Mount was previously queued (unexpected in sequential): \(share.networkShare, privacy: .public)")
            await updateShare(mountStatus: .queued, for: share)
        case MounterError.userUnmounted:
            Logger.mounter.debug("👤 Share was previously user unmounted: \(share.networkShare, privacy: .public)")
            await updateShare(mountStatus: .userUnmounted, for: share)
        case MounterError.obstructingDirectory:
            Logger.mounter.debug("🚫 Obstructing directory prevented mount: \(share.networkShare, privacy: .public)")
            await updateShare(mountStatus: .obstructingDirectory, for: share)
        case MounterError.permissionDenied:
             Logger.mounter.debug("🚫 Permission denied for mount: \(share.networkShare, privacy: .public)")
             await updateShare(mountStatus: .errorOnMount, for: share)
        case MounterError.targetNotReachable:
             Logger.mounter.debug("🚫 Target not reachable (pre-mount check): \(share.networkShare, privacy: .public)")
             await updateShare(mountStatus: .unreachable, for: share)
         case MounterError.otherError:
             Logger.mounter.debug("❓ Other pre-mount check error: \(share.networkShare, privacy: .public)")
             await updateShare(mountStatus: .errorOnMount, for: share) // Or a more specific error status
        default:
            Logger.mounter.debug("❓ Unknown error mounting \(share.networkShare, privacy: .public): \(error, privacy: .public)")
            await updateShare(mountStatus: .unreachable, for: share) // Default to unreachable for unknown errors
        }
    }
    
    /// Sets the mount status for all shares to the specified value
    ///
    /// - Parameter status: The mount status to set for all shares
    func setAllMountStatus(to status: MountStatus) async {
        for share in await shareManager.allShares {
            await updateShare(mountStatus: status, for: share)
        }
    }
    
    // MARK: - Share Mounting Private Helpers
    
    /// Validates the network share URL and extracts the host
    ///
    /// - Parameter share: The share to validate
    /// - Returns: A tuple containing the URL and host
    /// - Throws: MounterError if URL is invalid or host cannot be determined
    private func validateShareURL(_ share: Share) async throws -> (url: URL, host: String) {
        guard let url = URL(string: share.networkShare) else {
            Logger.mounter.error("❌ Could not find share for \(share.networkShare, privacy: .public)")
            throw MounterError.errorOnEncodingShareURL
        }
        guard let host = url.host else {
            Logger.mounter.error("❌ Could not determine hostname for \(share.networkShare, privacy: .public)")
            await updateShare(mountStatus: .errorOnMount, for: share)
            throw MounterError.invalidHost
        }
        return (url, host)
    }
    
    /// Checks the network connectivity to a host
    ///
    /// - Parameter host: The hostname to check
    /// - Parameter share: The share being checked (for status updates)
    /// - Throws: MounterError if host is unreachable
    private func checkNetworkConnectivity(toHost host: String, forShare share: Share) async throws {
        var flags = SCNetworkReachabilityFlags(rawValue: 0)
        let hostReachability = SCNetworkReachabilityCreateWithName(nil, (host as NSString).utf8String!)
        guard SCNetworkReachabilityGetFlags(hostReachability!, &flags) == true else {
            Logger.mounter.warning("⚠️ Could not determine reachability for host \(host, privacy: .public)")
            await updateShare(mountStatus: .unreachable, for: share)
            throw MounterError.couldNotTestConnectivity
        }
        guard flags.contains(.reachable) == true else {
            Logger.mounter.warning("⚠️ \(host, privacy: .public): target not reachable")
            await updateShare(mountStatus: .unreachable, for: share)
            throw MounterError.targetNotReachable
        }
    }
    
    /// Validates that the share path has a valid mount component
    ///
    /// - Parameter share: The share to validate
    /// - Throws: MounterError if the mount component cannot be determined
    private func validateMountComponent(forShare share: Share) async throws {
        let dir = URL(fileURLWithPath: share.networkShare)
        guard dir.pathComponents.last != nil else {
            Logger.mounter.warning("❌ Could not determine mount dir component of share \(share.networkShare, privacy: .public)")
            await updateShare(mountStatus: .errorOnMount, for: share)
            throw MounterError.errorCheckingMountDir
        }
    }
    
    /// Determines the mount directory path for a share
    ///
    /// - Parameters:
    ///   - share: The share to mount
    ///   - url: The validated URL of the share
    ///   - basePath: The base path where the share will be mounted
    /// - Returns: The full path where the share will be mounted
    private func determineMountDirectory(forShare share: Share, url: URL, basePath: String) -> String {
        Logger.mounter.debug("🤔 Determining mount directory: Input ShareMP=\(share.mountPoint ?? "(using share dir)", privacy: .public)', URL=\(url, privacy: .public), BasePath=\(basePath, privacy: .public)")
        var mountDirectory = basePath
        
        if basePath != "/Volumes" {
            // Check if there is a share-specific mountpoint
            if let mountPoint = share.mountPoint, !mountPoint.isEmpty {
                mountDirectory += "/" + mountPoint
            } else if !url.lastPathComponent.isEmpty {
                // Use the export path of the share as mount directory
                mountDirectory += "/" + url.lastPathComponent
            } else if let host = url.host {
                // Use share's server name as mount directory
                mountDirectory += "/" + host
            }
        } else if !url.lastPathComponent.isEmpty {
            // Use the export path of the share as mount directory
            mountDirectory += "/" + url.lastPathComponent
        } else if let host = url.host {
            // Use share's server name as mount directory
            mountDirectory += "/" + host
        }
        
        Logger.mounter.debug("🗺️ Determined mount directory: '\(mountDirectory, privacy: .public)'")
        return mountDirectory
    }
    
    /// Checks if a directory can be used as a mount point
    ///
    /// - Parameters:
    ///   - directory: The directory path to check
    ///   - url: The share URL (for logging)
    /// - Returns: True if directory is already a mount point with the same share
    /// - Throws: MounterError if directory cannot be used
    private func checkMountDirectory(_ directory: String, forURL url: URL) throws -> Bool {
        if fm.isDirectory(atPath: directory) {
            // Check if the directory is already a mount point
            if fm.isDirectoryFilesystemMount(atPath: directory) {
                Logger.mounter.info("ℹ️  \(url, privacy: .public): seems to be already mounted on \(directory, privacy: .public)")
                return true
            } else {
                if self.defaultMountPath == "/Volumes" {
                    Logger.mounter.info("❗ Obstructing directory at \(directory, privacy: .public): can not mount share \(url, privacy: .public)")
                    throw MounterError.obstructingDirectory
                } else {
                    removeDirectory(atPath: URL(string: directory)!.relativePath)
                }
            }
        }
        return false
    }
    
    /// Determines if mounting should be attempted based on share status
    ///
    /// - Parameters:
    ///   - share: The share to check
    ///   - url: The validated URL of the share
    ///   - userTriggered: Whether the mount was triggered by user action
    /// - Throws: MounterError with appropriate status if mounting should not proceed
    private func checkMountingCondition(forShare share: Share, url: URL, userTriggered: Bool) throws {
        if !userTriggered && (
            share.mountStatus == MountStatus.queued ||
            share.mountStatus == MountStatus.errorOnMount ||
            share.mountStatus == MountStatus.userUnmounted ||
            share.mountStatus == MountStatus.unreachable) {
            
            if share.mountStatus == MountStatus.queued {
                Logger.mounter.info("⌛ Share \(url, privacy: .public) is already queued for mounting.")
                throw MounterError.mountIsQueued
            } else if share.mountStatus == MountStatus.errorOnMount {
                Logger.mounter.info("⚠️ Share \(url, privacy: .public): not mounted, last time I tried I got a mount error.")
                throw MounterError.otherError
            } else if share.mountStatus == MountStatus.userUnmounted {
                Logger.mounter.info("🖐️ Share \(url, privacy: .public): user decided to unmount all shares, not mounting them.")
                throw MounterError.userUnmounted
            } else if share.mountStatus == MountStatus.unreachable {
                Logger.mounter.info("⚠️ Share \(url, privacy: .public): ignored by mount, last time I tried server was not reachable.")
                throw MounterError.targetNotReachable
            } else {
                Logger.mounter.info("🤷 Share \(url, privacy: .public): not mounted, I do not know why. It just happened.")
                throw MounterError.otherError
            }
        }
    }
    
    /// Prepares the mount point directory and options
    ///
    /// - Parameters:
    ///   - mountDirectory: The directory where the share will be mounted
    ///   - basePath: The base mounting path
    ///   - share: The share being mounted
    /// - Returns: A tuple containing the mount options, open options, and real mount point
    /// - Throws: Any error that occurs during directory creation
    private func prepareMountOperation(mountDirectory: String, basePath: String, share: Share) async throws -> (mountOptions: CFDictionary, openOptions: CFDictionary, realMountPoint: String) {
        var mountOptions = Defaults.mountOptions
        var openOptions = Defaults.openOptions
        var realMountPoint = mountDirectory
        
        if basePath == "/Volumes" {
            mountOptions = Defaults.mountOptionsForSystemMountDir
            realMountPoint = basePath // For /Volumes, NetFS handles the final path component
            Logger.mounter.debug("📂 Using /Volumes base path, realMountPoint set to base: \(realMountPoint, privacy: .public)")
        } else {
            // Create the directory as mount point only if it doesn't exist
            if !fm.fileExists(atPath: mountDirectory) {
                Logger.mounter.debug("📂 Creating mount directory: \(mountDirectory, privacy: .public)")
                try fm.createDirectory(atPath: mountDirectory, withIntermediateDirectories: true)
                
                // Verify directory was actually created
                guard fm.fileExists(atPath: mountDirectory) else {
                    Logger.mounter.error("❌ Failed to create directory at \(mountDirectory, privacy: .public) - directory does not exist after creation")
                    throw MounterError.errorCheckingMountDir
                }
                
                // Directory exists, now try to hide it
                var url = URL(fileURLWithPath: mountDirectory)
                var resourceValues = URLResourceValues()
                resourceValues.isHidden = true
                do {
                    try url.setResourceValues(resourceValues)
                    Logger.mounter.debug("👁️ Successfully hidden mount directory: \(mountDirectory, privacy: .public)")
                } catch {
                    Logger.mounter.warning("⚠️ Could not hide mount directory \(mountDirectory, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            } else {
                Logger.mounter.debug("📂 Mount directory already exists: \(mountDirectory, privacy: .public)")
            }
        }
        
        // Use guest authentication options if specified
        if share.authType == .guest {
            openOptions = Defaults.openOptionsGuest
            Logger.mounter.debug("👤 Using guest authentication options for \(share.networkShare, privacy: .public)")
        }
        
        return (mountOptions, openOptions, realMountPoint)
    }
    
    /// Processes the result of a mount operation
    ///
    /// - Parameters:
    ///   - returnCode: The return code from NetFSMountURLSync
    ///   - mountDirectory: The directory where the share was mounted
    ///   - url: The share URL
    /// - Returns: The mount directory if mount was successful
    /// - Throws: MounterError with appropriate status based on return code
    private func processMountResult(returnCode rc: Int32, mountDirectory: String, url: URL) async throws -> String {
        switch rc {
        case 0:
            Logger.mounter.info("✅ \(url, privacy: .public): successfully mounted on \(mountDirectory, privacy: .public)")
            
            // Make the directory visible after successful mount
            if mountDirectory != "/Volumes" {
                var url = URL(fileURLWithPath: mountDirectory)
                var resourceValues = URLResourceValues()
                resourceValues.isHidden = false
                do {
                    try url.setResourceValues(resourceValues)
                    Logger.mounter.debug("👁️ Successfully unhidden mount directory: \(mountDirectory, privacy: .public)")
                } catch {
                    Logger.mounter.warning("⚠️ Could not unhide mount directory \(mountDirectory, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }
            
            // Refresh Finder for newly mounted path
            let finderController = FinderController()
            await finderController.refreshFinder(forPaths: [mountDirectory])
            
            return mountDirectory
            
        case 2:
            Logger.mounter.info("❌ \(url, privacy: .public): does not exist (rc=\(rc))")
            removeDirectory(atPath: mountDirectory)
            throw MounterError.doesNotExist
            
        case 13:
            Logger.mounter.info("❌ \(url, privacy: .public): permission denied (rc=\(rc))")
            removeDirectory(atPath: mountDirectory)
            throw MounterError.permissionDenied
            
        case 17:
            Logger.mounter.info("❇️  \(url, privacy: .public): already mounted on \(mountDirectory, privacy: .public) (rc=\(rc))")
            
            // Refresh Finder even for already mounted shares (ensures visibility)
            let finderController = FinderController()
            await finderController.refreshFinder(forPaths: [mountDirectory])
            
            return mountDirectory
            
        case 60:
            Logger.mounter.info("🚫 \(url, privacy: .public): timeout reaching host (rc=\(rc))")
            removeDirectory(atPath: mountDirectory)
            throw MounterError.timedOutHost
            
        case 64:
            Logger.mounter.info("🚫 \(url, privacy: .public): host is down (rc=\(rc))")
            removeDirectory(atPath: mountDirectory)
            throw MounterError.hostIsDown
            
        case 65:
            Logger.mounter.info("🚫 \(url, privacy: .public): no route to host (rc=\(rc))")
            removeDirectory(atPath: mountDirectory)
            throw MounterError.noRouteToHost
            
        case 80:
            Logger.mounter.info("❌ \(url, privacy: .public): authentication error (rc=\(rc))")
            removeDirectory(atPath: mountDirectory)
            throw MounterError.authenticationError
            
        case -6003, -1073741275:
            Logger.mounter.info("❌ \(url, privacy: .public): share does not exist \(rc == -1073741275 ? "(" + rc.description + ")" : "", privacy: .public) (rc=\(rc))")
            removeDirectory(atPath: mountDirectory)
            throw MounterError.shareDoesNotExist
            
        default:
            Logger.mounter.warning("❌ \(url, privacy: .public) unknown return code: \(rc.description, privacy: .public) (rc=\(rc))")
            removeDirectory(atPath: mountDirectory)
            throw MounterError.unknownReturnCode
        }
    }

    /// Mounts a given remote share on a local mount point
    ///
    /// This method:
    /// - Validates the network share URL and host
    /// - Checks network connectivity to the host
    /// - Creates the mount directory if needed
    /// - Performs the actual mount operation using NetFS
    /// - Handles various mount error conditions
    ///
    /// - Parameters:
    ///   - share: The share to mount
    ///   - mountPath: The base path where the share will be mounted
    ///   - userTriggered: Whether the mount was triggered by user action
    /// - Returns: The actual mount point path where the share was mounted
    /// - Throws: MounterError if the mount operation fails
    func mountShare(forShare share: Share, atPath mountPath: String, userTriggered: Bool = false) async throws -> String {
        Logger.mounter.debug("--- Starting mountShare for: \(share.networkShare, privacy: .public) --- ")
        // Validate the share URL and get host
        let (url, host) = try await validateShareURL(share)
        Logger.mounter.debug("  Validated URL: \(url, privacy: .public), Host: \(host, privacy: .public)")
        
        // Check network connectivity
        try await checkNetworkConnectivity(toHost: host, forShare: share)
        Logger.mounter.debug("  Network connectivity OK for host: \(host, privacy: .public)")
        
        // Validate the mount component
        try await validateMountComponent(forShare: share)
        Logger.mounter.debug("  Mount component validated")
        
        // Determine the mount directory path
        let mountDirectory = determineMountDirectory(forShare: share, url: url, basePath: mountPath)
        Logger.mounter.debug("  Determined mount directory: \(mountDirectory, privacy: .public)")
        
        // Check if directory can be used as mount point
        if try checkMountDirectory(mountDirectory, forURL: url) {
            Logger.mounter.info("  ℹ️ Share \(url) seems already mounted at \(mountDirectory, privacy: .public). Returning existing path.")
            return mountDirectory
        }
        Logger.mounter.debug("  Mount directory check passed (not already mounted here)")
        
        // Check if mounting should be attempted based on current status (unless user triggered)
        try checkMountingCondition(forShare: share, url: url, userTriggered: userTriggered)
        Logger.mounter.debug("  Mounting condition check passed")
        
        // Prepare for mount
        Logger.mounter.debug("🤙 Preparing mount operation for \(url, privacy: .public) on path \(mountDirectory, privacy: .public)")
        await updateShare(mountStatus: .queued, for: share)
        
        // Set up mount options
        let (mountOptions, openOptions, realMountPoint) = try await prepareMountOperation(
            mountDirectory: mountDirectory,
            basePath: mountPath,
            share: share
        )
        Logger.mounter.debug("  Prepared mount options. Real mount point target: \(realMountPoint, privacy: .public)")
        
        // Perform the mount operation
        Logger.mounter.info("""
            🚀 Calling NetFSMountURLSync: URL=\(url, privacy: .public),
                            Path=\(realMountPoint, privacy: .public),
                            User=\(share.username ?? "(nil)", privacy: .public),
                            Pwd=\(share.password == nil ? "(nil)" : "(set)", privacy: .public)
        """)
        
        
        // swiftlint:disable force_cast
        let rc = NetFSMountURLSync(url as CFURL,
                                   // Use fileURLWithPath for the mount point path
                                   URL(fileURLWithPath: realMountPoint) as CFURL,
                                   share.username as CFString?,
                                   share.password as CFString?,
                                   openOptions as! CFMutableDictionary,
                                   mountOptions as! CFMutableDictionary,
                                   nil) // Resulting mount path (we don't use this directly)
        
        // Record end time and calculate duration
        Logger.mounter.info("🏁 NetFSMountURLSync finished for \(url, privacy: .public) with return code: \(rc, privacy: .public))")
        // swiftlint:enable force_cast
        
        // Process the mount result
        let finalMountPoint = try await processMountResult(returnCode: rc, mountDirectory: mountDirectory, url: url)
        Logger.mounter.debug("--- Finished mountShare successfully for: \(share.networkShare, privacy: .public) at \(finalMountPoint, privacy: .public) --- ")
        return finalMountPoint
    }
}

