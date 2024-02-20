//
//  FileManager.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 20.02.24.
//  Copyright © 2024 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation

extension FileManager {
    /// Check if a given path string is a directory
    /// - Parameter atPath: A string containig the path to check
    /// - Returns: An optional boolean set to true if the given path is a directory
    func isDirectory(atPath: String) -> Bool {
        var isDir: ObjCBool = ObjCBool(false)
        if fileExists(atPath: atPath, isDirectory: &isDir) {
            return isDir.boolValue
        } else {
            return false
        }
    }
    
    /// Check if a given directory is a mount point for a (remote) file system
    /// - Parameter atPath: A string containig the path to check
    /// - Returns: An optional boolean set to true if the given directory path is a mountpoint
    func isDirectoryFilesystemMount(atPath: String) -> Bool {
        do {
            let systemAttributes = try FileManager.default.attributesOfItem(atPath: atPath)
            if let fileSystemFileNumber = systemAttributes[.systemFileNumber] as? NSNumber {
                //
                // if fileSystemFileNumber is 2 -> filesystem mount
                if fileSystemFileNumber == 2 {
                    return true
                }
            }
        } catch {
            return false
        }
        return false
    }
}
