//
//  Mounter.swift
//  Network Share Mounter
//
//  Created by Gregor Longariva on 24.11.21.
//  Copyright © 2021 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation
import NetFS
import SystemConfiguration
import OpenDirectory
import AppKit

class Mounter {

    var localizedFolder: String
    var mountpath: String

    init() {
        // create subfolder in home to mount shares in
        self.localizedFolder = Settings.translation[Locale.current.languageCode!] ?? Settings.translation["en"]!
        self.mountpath = NSString(string: "~/\(localizedFolder)").expandingTildeInPath

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
    }
}

// extend String to create a valid path from a bunch of strings
extension String {
    func appendingPathComponent(_ string: String) -> String {
        return URL(fileURLWithPath: self).appendingPathComponent(string).path
    }
}

extension Mounter {
    // check if a given directory is a mount point for a (remote) file system
    func isDirectoryFilesystemMount(atPath: String) -> Bool {
        do {
            let systemAttributes = try FileManager.default.attributesOfItem(atPath: atPath)
            if let fileSystemFileNumber = systemAttributes[.systemFileNumber] as? NSNumber {
                // if fileSystemFileNumber is 2 -> filesystem mount
                if fileSystemFileNumber == 2 {
                    return true
                }
            }
        } catch let error as NSError {
            NSLog("Could not check directory at \(atPath): \(error.debugDescription)")
            return false
        }
        return false
    }
}

extension Mounter {
    // function to delete obstructing files in mountDir Subdirectories
    func deleteUnneededFiles(path: String, filename: String?) {
        let fileManager = FileManager.default
        do {
            let filePaths = try fileManager.contentsOfDirectory(atPath: path)
            for filePath in filePaths {
                // check if directory is a (remote) filesystem mount
                // if directory is a regular directory go on
                if !isDirectoryFilesystemMount(atPath: path.appendingPathComponent(filePath)) {
                    // if the function has a parameter we want ot hanlde files
                    if let unwrappedFilename = filename {
                        if !isDirectoryFilesystemMount(atPath: path.appendingPathComponent(filePath)) {
                            let deleteFile = path.appendingPathComponent(filePath).appendingPathComponent(unwrappedFilename)
                            if fileManager.fileExists(atPath: deleteFile) {
                                NSLog("Deleting obstructing file \(deleteFile)")
                                try fileManager.removeItem(atPath: deleteFile)
                            }
                        }
                    } else {
                        // else we have a directory to remove
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
            }
        } catch let error as NSError {
            NSLog("Could not list directory at \(path): \(error.debugDescription)")
        }
    }
}

extension Mounter {
    func mountShares() {
        // iterate through all files defined in config file (e.g. .autodiskmounted, .DS_Store)
        for toDelete in Settings.filesToDelete {
            deleteUnneededFiles(path: self.mountpath, filename: toDelete)
        }

        // The directory with the mounts for the network-shares should be empty. All
        // former directories not deleted by the mounter should be nuked to avoid
        // creating new mount-points (=> directories) like projekte-1 projekte-2 and so on

        deleteUnneededFiles(path: mountpath, filename: nil)

        //var shares: [String] = UserDefaults(suiteName: Settings.defaultsDomain)?.array(forKey: "networkShares") as? [String] ?? []
        var shares: [String] = UserDefaults.standard.array(forKey: "networkShares") as? [String] ?? []
        // shares.append("smb://home.rrze.uni-erlangen.de/%USERNAME%")
        // every user may add its personal shares in the customNetworkShares array ...
        //let customshares = UserDefaults(suiteName: Settings.defaultsDomain)?.array(forKey: "customNetworkShares") as? [String] ?? []
        let customshares = UserDefaults.standard.array(forKey: "customNetworkShares") as? [String] ?? []
        for share in customshares {
            shares.append(share)
        }
        // replace %USERNAME with local username - must be the same as directory service username!
        shares = shares.map {
            $0.replacingOccurrences(of: "%USERNAME%", with: NSUserName())
        }
        // append SMBHomeDirectory attribute to list of shares to mount
        do {
            // swiftlint:disable force_cast
            let node = try ODNode(session: ODSession.default(), type: ODNodeType(kODNodeTypeAuthentication))
            let query = try ODQuery(node: node, forRecordTypes: kODRecordTypeUsers, attribute: kODAttributeTypeRecordName,
                                    matchType: ODMatchType(kODMatchEqualTo), queryValues: NSUserName(), returnAttributes: kODAttributeTypeSMBHome,
                                    maximumResults: 1).resultsAllowingPartial(false) as! [ODRecord]
            if let result = query[0].value(forKey: kODAttributeTypeSMBHome) as? [String] {
                var homeDirectory = result[0]
                homeDirectory = homeDirectory.replacingOccurrences(of: "\\\\", with: "smb://")
                homeDirectory = homeDirectory.replacingOccurrences(of: "\\", with: "/")
                shares.append(homeDirectory)
            }
            // swiftlint:enable force_cast
        } catch {
            // Couldn't perform mount operation
            NSLog("Couldn't mount shares")
        }

        // eliminate duplicates
        // swiftlint:disable force_cast
        shares = NSOrderedSet(array: shares).array as! [String]
        // swiftlint:enable force_cast

        if shares.isEmpty {
            NSLog("no shares configured!")
        } else {
            for share in shares {
                _ = doTheMount(forShare: share)
            }
        }
    }
}

extension Mounter {
    func doTheMount(forShare share: String) -> Bool {
        // oddly there is some undocumented magic done by addingPercentEncoding when the CharacterSet
        // used as reference is an underlying NSCharacterSet class. It appears, it encodes even the ":"
        // at the very beginning of the URL ( smb:// vs. smb0X0P+0// ). As a result, the host() function
        // of NSURL does not return a valid hostname.
        // So to workaround this magic, you need to make your CharacterSet a pure Swift object.
        // To do so, create a copy so that the evil magic is gone.
        // see https://stackoverflow.com/questions/44754996/is-addingpercentencoding-broken-in-xcode-9
        //
        // normally the following should work:
        // guard let encodedShare = share.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlPathAllowed) else { continue }
        let csCopy = CharacterSet(bitmapRepresentation: CharacterSet.urlPathAllowed.bitmapRepresentation)
        guard let encodedShare = share.addingPercentEncoding(withAllowedCharacters: csCopy) else { return(false) }
        guard let url = NSURL(string: encodedShare) else { return(false) }
        guard let host = url.host else { return(false) }

        // check if we have network connectivity
        var flags = SCNetworkReachabilityFlags(rawValue: 0)
        let hostReachability = SCNetworkReachabilityCreateWithName(nil, (host as NSString).utf8String!)
        guard SCNetworkReachabilityGetFlags(hostReachability!, &flags) == true else { NSLog("could not determine reachability for host \(host)"); return(false) }
        guard flags.contains(.reachable) == true else { NSLog("\(host): target not reachable"); return(false) }

        let rc = NetFSMountURLSync(url, NSURL(string: mountpath), nil, nil, Settings.openOptions, Settings.mountOptions, nil)

        switch rc {
        case 0:
            NSLog("\(url): successfully mounted")
            return(true)
        case 2:
            NSLog("\(url): does not exist")
        case 17:
            NSLog("\(url): already mounted")
            return(true)
        case 65:
            NSLog("\(url): no route to host")
        case -6003:
            NSLog("\(url): share does not exist")
        default:
            NSLog("\(url) unknown return code: \(rc)")
        }
        return(false)
    }
}
