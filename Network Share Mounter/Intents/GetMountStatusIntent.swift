//
//  GetMountStatusIntent.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 04.02.26.
//  Copyright © 2026 RRZE. All rights reserved.
//

import AppIntents
import Foundation

/// Simplified share status information for App Intents.
///
/// This structure contains only the essential information needed
/// for Shortcuts queries and conditions. It avoids complex types
/// that cannot be easily serialized for inter-process communication.
struct ShareStatusInfo: Codable {
    var displayName: String
    var networkPath: String
    var status: String
    var mountPoint: String?
    var isManaged: Bool
}

/// An App Intent that retrieves the current mount status of all configured network shares.
///
/// This intent reads share information from UserDefaults and checks their
/// current mount status by examining actual mount points in the filesystem.
/// It returns structured information suitable for use in Shortcuts conditions.
///
/// Unlike other intents, this one does not open the app and directly
/// returns the status information.
struct GetMountStatusIntent: AppIntent {
    
    /// The localized display title shown in Shortcuts, Siri, and other system surfaces.
    static var title: LocalizedStringResource = LocalizedStringResource("GetMountStatus.Title", table: "Localizable")
    
    /// The localized, user-facing description explaining what this intent does.
    static var description = IntentDescription(LocalizedStringResource("GetMountStatus.Description", table: "Localizable"))
    
    /// Indicates whether the host app should open when the intent is executed.
    ///
    /// Set to `false` because this is a query intent that just returns status.
    static var openAppWhenRun: Bool = false
    
    /// Performs the intent by retrieving mount status of all shares.
    ///
    /// Reads share configurations from UserDefaults and checks their
    /// current mount status by examining the filesystem.
    ///
    /// - Returns: An intent result with share status information and a human-readable dialog.
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let shares = await getSharesStatus()
        
        let mountedCount = shares.filter { $0.status == "mounted" }.count
        let totalCount = shares.count
        
        let dialog: IntentDialog
        if totalCount == 0 {
            dialog = IntentDialog(LocalizedStringResource("GetMountStatus.NoShares", table: "Localizable"))
        } else if mountedCount == totalCount {
            dialog = IntentDialog(stringLiteral: String(
                format: String(localized: "GetMountStatus.AllMounted", table: "Localizable"),
                totalCount
            ))
        } else if mountedCount == 0 {
            dialog = IntentDialog(stringLiteral: String(
                format: String(localized: "GetMountStatus.NoneMounted", table: "Localizable"),
                totalCount
            ))
        } else {
            dialog = IntentDialog(stringLiteral: String(
                format: String(localized: "GetMountStatus.PartiallyMounted", table: "Localizable"),
                mountedCount,
                totalCount
            ))
        }
        
        let statusString = formatStatusString(shares)
        return .result(value: statusString, dialog: dialog)
    }
    
    /// Retrieves share status information from UserDefaults and filesystem.
    ///
    /// - Returns: An array of ShareStatusInfo structures with current status.
    private func getSharesStatus() async -> [ShareStatusInfo] {
        var shareInfos: [ShareStatusInfo] = []
        
        let userDefaults = UserDefaults.standard
        
        // Read user-defined shares
        if let userShares = userDefaults.array(forKey: "userNetworkShares") as? [[String: String]] {
            for shareDict in userShares {
                if let networkShare = shareDict["networkShare"] {
                    let displayName = shareDict["shareDisplayName"] ?? extractShareName(from: networkShare)
                    let mountPoint = shareDict["actualMountPoint"]
                    let status = checkMountStatus(mountPoint: mountPoint)
                    
                    shareInfos.append(ShareStatusInfo(
                        displayName: displayName,
                        networkPath: networkShare,
                        status: status,
                        mountPoint: mountPoint,
                        isManaged: false
                    ))
                }
            }
        }
        
        // Read MDM-managed shares
        if let managedShares = userDefaults.array(forKey: "networkShares") as? [[String: String]] {
            for shareDict in managedShares {
                if let networkShare = shareDict["networkShare"] {
                    let displayName = shareDict["shareDisplayName"] ?? extractShareName(from: networkShare)
                    let mountPoint = shareDict["actualMountPoint"]
                    let status = checkMountStatus(mountPoint: mountPoint)
                    
                    shareInfos.append(ShareStatusInfo(
                        displayName: displayName,
                        networkPath: networkShare,
                        status: status,
                        mountPoint: mountPoint,
                        isManaged: true
                    ))
                }
            }
        }
        
        return shareInfos
    }
    
    /// Checks if a share is currently mounted by verifying the mount point exists.
    ///
    /// - Parameter mountPoint: The actual mount point path.
    /// - Returns: "mounted" if the path exists, "unmounted" otherwise.
    private func checkMountStatus(mountPoint: String?) -> String {
        guard let mountPoint = mountPoint, !mountPoint.isEmpty else {
            return "unmounted"
        }
        
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        
        if fileManager.fileExists(atPath: mountPoint, isDirectory: &isDirectory) && isDirectory.boolValue {
            return "mounted"
        } else {
            return "unmounted"
        }
    }
    
    /// Extracts the share name from a network path.
    ///
    /// Handles paths like:
    /// - `smb://server/share` → "share"
    /// - `afp://server/share` → "share"
    ///
    /// - Parameter networkPath: The full network share URL.
    /// - Returns: The extracted share name, or the full path if extraction fails.
    private func extractShareName(from networkPath: String) -> String {
        // Remove protocol
        var path = networkPath
            .replacingOccurrences(of: "smb://", with: "")
            .replacingOccurrences(of: "afp://", with: "")
            .replacingOccurrences(of: "nfs://", with: "")
        
        // Get the last component
        let components = path.split(separator: "/")
        if let lastComponent = components.last {
            return String(lastComponent)
        }
        
        return networkPath
    }
    
    /// Formats the status array as a human-readable string.
    ///
    /// - Parameter shares: The array of share status information.
    /// - Returns: A formatted string representation.
    private func formatStatusString(_ shares: [ShareStatusInfo]) -> String {
        if shares.isEmpty {
            return String(localized: "GetMountStatus.NoSharesConfigured", table: "Localizable")
        }
        
        var result = String(
            format: String(localized: "GetMountStatus.StatusHeader", table: "Localizable"),
            shares.count
        )
        result += "\n\n"
        
        for share in shares {
            let statusIcon = share.status == "mounted" ? "✅" : "❌"
            let managedTag = share.isManaged ? " [MDM]" : ""
            result += "\(statusIcon) \(share.displayName)\(managedTag)\n"
            
            if share.status == "mounted", let mountPoint = share.mountPoint {
                result += "   \(String(localized: "GetMountStatus.MountedAt", table: "Localizable")): \(mountPoint)\n"
            }
        }
        
        return result
    }
}
