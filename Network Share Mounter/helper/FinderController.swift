//
//  FinderController.swift
//  Network Share Mounter
//
//  Created by Gregor Longariva on 06.12.24.
//  Copyright © 2024 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation
import AppKit
import OSLog

actor FinderController {
    private var isRestarting = false
    private var isGentlyRefreshing = false
    
    /// Refresh Finder view with different strategies for mount vs unmount operations
    ///
    /// Based on the operation type, different refresh strategies are used:
    /// - Unmount operations: Use killall Finder (proven reliable for disappearing shares)
    /// - Mount operations: Use native methods (usually sufficient)
    ///
    /// - Parameters:
    ///   - mountPaths: Optional array of specific mount paths to refresh. If nil, uses default mount locations.
    ///   - forceRestart: If true, skips native methods and goes straight to killall Finder
    ///   - isUnmountOperation: If true, indicates this refresh is for an unmount operation (uses killall)
    func refreshFinder(forPaths mountPaths: [String]? = nil, forceRestart: Bool = false, isUnmountOperation: Bool = false) async {
        guard !isRestarting else {
            Logger.finderController.debug("⏸️ Finder restart in progress, skipping refresh")
            return
        }
        
        if forceRestart || isUnmountOperation {
            let reason = forceRestart ? "force restart requested" : "unmount operation"
            Logger.finderController.info("🎯 Using killall Finder - reason: \(reason)")
            await nuclearFinderRestart()
            return
        }
        
        // For mount operations and local paths, use native methods
        Logger.finderController.debug("🔄 Using native refresh methods for mount operation")
        await refreshFinderView(forPaths: mountPaths)
        Logger.finderController.info("✅ Native Finder refresh completed")
    }
    
    /// Refresh Finder view using multiple robust methods
    ///
    /// This method uses several techniques to force Finder to refresh:
    /// 1. FSEvents notifications for better filesystem integration
    /// 2. Multiple distributed notifications
    /// 3. NSWorkspace notifications as fallback
    /// 4. Timing delays to handle async Finder updates
    ///
    /// - Parameter mountPaths: Optional array of specific paths to refresh. If nil, uses common mount locations.
    private func refreshFinderView(forPaths mountPaths: [String]? = nil) async {
        Logger.finderController.debug("🔄 Attempting robust Finder refresh using multiple methods")
        
        let pathsToRefresh: [String]
        
        if let providedPaths = mountPaths {
            pathsToRefresh = providedPaths
        } else {
            // Use common mount locations as fallback
            pathsToRefresh = [
                "/Volumes",
                URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop").path,
                URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents").path
            ]
        }
        
        Logger.finderController.debug("🎯 Refreshing paths: \(pathsToRefresh.joined(separator: ", "), privacy: .public)")
        
        // Method 1: FSEvents-based notifications (more reliable)
        for mountPath in pathsToRefresh {
            await triggerFSEventForPath(mountPath)
            
            // Also trigger for parent directories
            let parentPath = URL(fileURLWithPath: mountPath).deletingLastPathComponent().path
            if parentPath != mountPath && parentPath != "/" {
                await triggerFSEventForPath(parentPath)
            }
        }
        
        // Method 2: Multiple distributed notifications to Finder
        await MainActor.run {
            let notificationCenter = DistributedNotificationCenter.default()
            
            // Send various Finder refresh notifications
            let finderNotifications = [
                "com.apple.finder.refresh",
                "com.apple.finder.TFloatingWindow",
                "com.apple.finder.refreshdesktop",
                "com.apple.finder.sidebar.refresh"
            ]
            
            for notification in finderNotifications {
                notificationCenter.postNotificationName(
                    NSNotification.Name(notification),
                    object: nil,
                    userInfo: ["paths": pathsToRefresh]
                )
            }
            
            // Method 3: NSWorkspace notifications (fallback)
            for mountPath in pathsToRefresh {
                NSWorkspace.shared.noteFileSystemChanged(mountPath)
            }
        }
        
        // Method 4: Force Finder window refresh via AppleEvents
        await refreshFinderWindows()
        
        Logger.finderController.info("✅ Multi-method Finder refresh completed for \(pathsToRefresh.count) paths")
        
        // Method 5: Delayed secondary refresh (handles async Finder behavior)
        Task { [pathsToRefresh] in
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            Logger.finderController.debug("🔄 Secondary delayed Finder refresh")
            
            await MainActor.run {
                for mountPath in pathsToRefresh {
                    NSWorkspace.shared.noteFileSystemChanged(mountPath)
                }
                
                // Send final refresh notification
                DistributedNotificationCenter.default().postNotificationName(
                    NSNotification.Name("com.apple.finder.refresh"),
                    object: nil
                )
            }
        }
    }
    
    /// Trigger FSEvent for a specific path (more reliable than NSWorkspace)
    private func triggerFSEventForPath(_ path: String) async {
        // Create a temporary file and immediately remove it to trigger FSEvent
        let tempFileName = ".\(UUID().uuidString).tmp"
        let tempFilePath = URL(fileURLWithPath: path).appendingPathComponent(tempFileName).path
        
        do {
            // Try to create and immediately remove a temp file to trigger FSEvent
            try "".write(toFile: tempFilePath, atomically: true, encoding: .utf8)
            try FileManager.default.removeItem(atPath: tempFilePath)
            Logger.finderController.debug("🎯 FSEvent triggered for \(path, privacy: .public)")
        } catch {
            // If we can't write (e.g., read-only mount), just log
            Logger.finderController.debug("ℹ️ Could not trigger FSEvent for \(path, privacy: .public): \(error.localizedDescription)")
        }
    }
    
    /// Refresh Finder windows using simple activation
    private func refreshFinderWindows() async {
        await MainActor.run {
            // Simple Finder activation to trigger refresh
            if let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first {
                // Brief activation can trigger window refresh
                finder.activate(options: [])
                Logger.finderController.debug("📬 Finder activation refresh triggered")
            }
        }
    }
    
    /// Get actual mount paths from Mounter instance
    ///
    /// This method collects the real mount paths used by the application
    /// instead of relying on hard-coded common paths.
    ///
    /// - Parameter mounter: The Mounter instance to get paths from
    /// - Returns: Array of mount paths currently in use
    func getActualMountPaths(from mounter: Mounter) async -> [String] {
        var mountPaths: [String] = []
        
        // Add the default mount path
        mountPaths.append(mounter.defaultMountPath)
        
        // Add paths from currently mounted shares
        let shares = await mounter.shareManager.allShares
        for share in shares {
            if let actualMountPoint = share.actualMountPoint {
                // Add the actual mount point
                mountPaths.append(actualMountPoint)
                
                // Add the parent directory
                let parentPath = URL(fileURLWithPath: actualMountPoint).deletingLastPathComponent().path
                if !mountPaths.contains(parentPath) {
                    mountPaths.append(parentPath)
                }
            }
        }
        
        // Remove duplicates and add /Volumes if any mount uses it
        let uniquePaths = Array(Set(mountPaths))
        var finalPaths = uniquePaths
        
        if uniquePaths.contains(where: { $0.hasPrefix("/Volumes") }) && !uniquePaths.contains("/Volumes") {
            finalPaths.append("/Volumes")
        }
        
        Logger.finderController.debug("🗂️ Collected mount paths: \(finalPaths.joined(separator: ", "), privacy: .public)")
        return finalPaths
    }
    
    /// Gentle Finder refresh alternative (middle ground approach)
    ///
    /// This method tries a gentler approach than killall by:
    /// 1. Hiding and showing Finder
    /// 2. Forcing window refresh
    func gentleFinderRefresh() async {
        guard !isGentlyRefreshing else {
            Logger.finderController.debug("⏸️ Gentle Finder refresh already in progress, skipping")
            return
        }
        isGentlyRefreshing = true
        defer { isGentlyRefreshing = false }
        
        Logger.finderController.info("🔄 Attempting gentle Finder refresh")
        
        await MainActor.run {
            guard let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first else {
                Logger.finderController.debug("ℹ️ Finder not running, skipping gentle refresh")
                return
            }
            finder.hide()
        }
        
        // Keep timing predictable and avoid DispatchQueue.main.asyncAfter
        try? await Task.sleep(nanoseconds: 200_000_000) // 0.2s
        
        await MainActor.run {
            if let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first {
                finder.unhide()
                finder.activate(options: [.activateIgnoringOtherApps])
            }
        }
        
        // Small additional delay to allow windows to redraw
        try? await Task.sleep(nanoseconds: 150_000_000) // 0.15s
        
        Logger.finderController.info("✅ Gentle Finder refresh completed")
    }
    
    /// Nuclear option: Force Finder restart (the reliable approach)
    ///
    /// This is the killall Finder approach - proven to work when native methods fail
    func nuclearFinderRestart() async {
        let runningFinder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder")
        guard !runningFinder.isEmpty else {
            Logger.finderController.debug("Finder is not running, skipping nuclear restart")
            return
        }
        
        guard !isRestarting else { return }
        
        isRestarting = true
        defer { isRestarting = false }
        
        Logger.finderController.info("🔄 Using reliable Finder restart (killall)")
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["Finder"]
        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
            Logger.finderController.info("✅ Finder restart completed successfully")
        } catch {
            Logger.finderController.error("❌ Error in Finder restart: \(error, privacy: .public)")
        }
    }
}
