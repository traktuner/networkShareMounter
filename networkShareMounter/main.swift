//
//  main.swift
//  networkShareMounter
//
//  Created by Kett, Oliver on 20.03.17.
//  bugfixing by FAUmac Team
//  Copyright © 2017 RRZE. All rights reserved.
//

import Foundation
import NetFS
import SystemConfiguration
import OpenDirectory

// create subfolder in home to mount shares in
let localizedFolder = config.translation[Locale.current.languageCode!] ?? config.translation["en"]!
let mountpath = NSString(string: "~/\(localizedFolder)").expandingTildeInPath
do {
    let fm = FileManager.default
    if !fm.fileExists(atPath: mountpath) {
        try fm.createDirectory(atPath: mountpath, withIntermediateDirectories: false, attributes: nil)
        NSLog("\(mountpath): created")
    }
} catch {
    NSLog("error creating folder: \(mountpath)")
    NSLog(error.localizedDescription)
    exit(2)
}

// extend String to create a valid path from a bunch of strings
extension String {
    func appendingPathComponent(_ string: String) -> String {
        return URL(fileURLWithPath: self).appendingPathComponent(string).path
    }
}

// function to delete obstructing files in mountDir Subdirectories
func deleteUnneededFiles(path: String, filename: String?) {
    let fileManager = FileManager.default
    do {
        let filePaths = try fileManager.contentsOfDirectory(atPath: path)
        for filePath in filePaths {
            if let unwrappedFilename = filename {
                let deleteFile = path.appendingPathComponent(filePath).appendingPathComponent(unwrappedFilename)
                if fileManager.fileExists(atPath: deleteFile) {
                    NSLog("Deleting obstructing file \(deleteFile)")
                    try fileManager.removeItem(atPath: deleteFile)
                }
            } else {
                // we have a directory to remove
                let deleteFile = path.appendingPathComponent(filePath)
                let task = Process()
                task.launchPath = "/bin/rmdir"
                task.arguments = ["\(deleteFile)"]
                let pipe = Pipe()
                task.standardOutput = pipe
                // Launch the task
                task.launch()
                // Get the data
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = NSString(data: data, encoding: String.Encoding.utf8.rawValue)
                NSLog("Deleting obstructing directory \(deleteFile): \(output ?? "done")")
            }
        }
    } catch let error as NSError {
        print("Could not list directory at \(path): \(error.debugDescription)")
    }
}

// iterate through all files defined in config file (e.g. .autodiskmounted, .DS_Store)
for toDelete in config.filesToDelete {
    deleteUnneededFiles(path: mountpath, filename: toDelete)
}

// The directory with the mounts for the network-shares should be empty. All
// former directories not deleted by the mounter should be nuked to avoid
// creating new mount-points (=> directories) like projekte-1 projekte-2 and so on

deleteUnneededFiles(path: mountpath, filename: nil)

var shares: [String] = UserDefaults(suiteName: config.defaultsDomain)?.array(forKey: "networkShares") as? [String] ?? []
// every user may add its personal shares in the customNetworkShares array ...
let customshares = UserDefaults(suiteName: config.defaultsDomain)?.array(forKey: "customNetworkShares") as? [String] ?? []
for share in customshares {
    shares.append(share)
}
// replace %USERNAME with local username - must be the same as directory service username!
shares = shares.map {
    $0.replacingOccurrences(of: "%USERNAME%", with: NSUserName())
}
// append SMBHomeDirectory attribute to list of shares to mount
do {
    let node = try ODNode(session: ODSession.default(), type: ODNodeType(kODNodeTypeAuthentication))
    let query = try ODQuery(node: node, forRecordTypes: kODRecordTypeUsers, attribute: kODAttributeTypeRecordName, matchType: ODMatchType(kODMatchEqualTo), queryValues: NSUserName(), returnAttributes: kODAttributeTypeSMBHome, maximumResults: 1).resultsAllowingPartial(false) as! [ODRecord]
    if let result = query[0].value(forKey: kODAttributeTypeSMBHome) as? [String] {
        var homeDirectory = result[0]
        homeDirectory = homeDirectory.replacingOccurrences(of: "\\\\", with: "smb://")
        homeDirectory = homeDirectory.replacingOccurrences(of: "\\", with: "/")
        shares.append(homeDirectory)
    }
}
// eliminate duplicates
shares = NSOrderedSet(array: shares).array as! [String]

if shares.count == 0 {
    NSLog("no shares configured!")
} else {
    for share in shares {
        guard let encodedShare = share.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed) else { continue }
        guard let url = NSURL(string: encodedShare) else { continue }
        guard let host = url.host else { continue }
        
        // check if we have network connectivity
        var flags = SCNetworkReachabilityFlags(rawValue: 0)
        let hostReachability = SCNetworkReachabilityCreateWithName(nil, (host as NSString).utf8String!)
        guard SCNetworkReachabilityGetFlags(hostReachability!, &flags) == true else { NSLog("could not determine reachability for host \(host)"); continue }
        guard flags.contains(.reachable) == true else { NSLog("\(host): target not reachable"); continue }
        
        let rc = NetFSMountURLSync(url, NSURL(string: mountpath), nil, nil, config.open_options, config.mount_options, nil)
        
        switch rc {
        case 0:
            NSLog("\(url): successfully mounted")
        case 2:
            NSLog("\(url): does not exist")
        case 17:
            NSLog("\(url): already mounted")
        case 65:
            NSLog("\(url): no route to host")
        case -6003:
            NSLog("\(url): share does not exist")
        default:
            NSLog("\(url) unknown return code: \(rc)")
        }
    }
}

