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

enum MounterError: Error {
    case errorCreatingMountFolder
    case errorCheckingMountDir
    case errorOnEncodingShareURL
    case invalidMountURL
    case invalidHost
    case mountpointInaccessible
    case couldNotTestConnectivity
    case invalidMountOptions
    case alreadyMounted
    case targetNotReachable
    case noRouteToHost
    case doesNotExist
    case shareDoesNotExist
    case unknownReturnCode
}

protocol ShareDelegate {
    func shareWillMount(url: URL) -> Void
    func shareDidMount(url: URL, at paths: [String]?) -> Void
    func shareMountingDidFail(for url: URL, withError: Int32) -> Void
}

typealias NetFSMountCallback = (Int32, UnsafeMutableRawPointer?, CFArray?) -> Void
typealias MountCallbackHandler = (Int32, URL?, [String]?) -> Void;

class Mounter {

    var localizedFolder = Settings.translation[Locale.current.languageCode!] ?? Settings.translation["en"]!
    var mountpath: String
    let fm = FileManager.default
    let userDefaults = UserDefaults.standard
    
    //let url: URL
    fileprivate var asyncRequestId: AsyncRequestID?
    public var delegate: ShareDelegate?

    init() {
        // create subfolder in home to mount shares in
        if let userDefaultsLocation = userDefaults.string(forKey: "location") {
            self.mountpath = NSString(string: userDefaults.string(forKey: "location")!).expandingTildeInPath
        } else {
            self.mountpath = NSString(string: "~/\(self.localizedFolder)").expandingTildeInPath
        }

        do {
            //
            // try to create (if not exists) the directory where the network shares will be mounted
            if !fm.fileExists(atPath: mountpath) {
                try fm.createDirectory(atPath: mountpath, withIntermediateDirectories: false, attributes: nil)
                NSLog("\(mountpath): created")
            }
        } catch {
            NSLog("error creating folder: \(mountpath)")
            NSLog(error.localizedDescription)
            exit(2)
        }
        //
        //Start monitoring of the network connection
        Monitor().startMonitoring { [weak self] connection, reachable in
                    guard let strongSelf = self else { return }
            //strongSelf.performMount(connection, reachable: reachable, mounter: mounter)
            strongSelf.mountShares()
        }
    }
    
    public func cancelMounting() {
        NetFSMountURLCancel(self.asyncRequestId)
    }
        
    static func cancelMounting(id requestId: AsyncRequestID) {
        NetFSMountURLCancel(requestId)
    }
}

//
// extend String to create a valid path from a bunch of strings
extension String {
    func appendingPathComponent(_ string: String) -> String {
        return URL(fileURLWithPath: self).appendingPathComponent(string).path
    }
}

extension Mounter {
    //
    // check if a given directory is a mount point for a (remote) file system
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
        } catch let error as NSError {
            NSLog("Could not check directory at \(atPath): \(error.debugDescription)")
            return false
        }
        return false
    }
}

//
// extension with a bunch of funtcions handling all the stuff around mounting shares
// such as creating a list of shares to be mounted, cleaning up mountdirectory,
// checking connectivity and so on
extension Mounter {
    //
    // function to delete obstructing files in mountDir Subdirectories
    func deleteUnneededFiles(path: String, filename: String?) {
        do {
            let filePaths = try fm.contentsOfDirectory(atPath: path)
            for filePath in filePaths {
                //
                // check if directory is a (remote) filesystem mount
                // if directory is a regular directory go on
                if !isDirectoryFilesystemMount(atPath: path.appendingPathComponent(filePath)) {
                    //
                    // Clean up directories only if defined in userdefaults
                    if userDefaults.bool(forKey: "cleanupLocationDirectory") == true {
                        //
                        // if the function has a parameter we want ot handle files
                        if let unwrappedFilename = filename {
                            if !isDirectoryFilesystemMount(atPath: path.appendingPathComponent(filePath)) {
                                let deleteFile = path.appendingPathComponent(filePath).appendingPathComponent(unwrappedFilename)
                                if fm.fileExists(atPath: deleteFile) {
                                    NSLog("Deleting obstructing file \(deleteFile)")
                                    try fm.removeItem(atPath: deleteFile)
                                }
                            }
                        } else {
                            //
                            // else we have a directory to remove
                            // delete directories only if the direcotry/location of the mountpoints
                            let deleteFile = path.appendingPathComponent(filePath)
                            let task = Process()
                            task.launchPath = "/bin/rmdir"
                            task.arguments = ["\(deleteFile)"]
                            let pipe = Pipe()
                            task.standardOutput = pipe
                            //
                            // Launch the task
                            task.launch()
                            //
                            // Get the data
                            let data = pipe.fileHandleForReading.readDataToEndOfFile()
                            let output = NSString(data: data, encoding: String.Encoding.utf8.rawValue)
                            NSLog("Deleting obstructing directory \(deleteFile): \(output ?? "done")")
                        }
                    }
                } else {
                    //
                    // directory is file-system mount.
                    // Now let's check if there is some SHARE-1, SHARE-2, ... mount and unmount it
                    //
                    // at first, let's get a list of all shares to match on
                    let shares = createShareArray()
                    //
                    // compare list of shares with mount
                    for share in shares {
                        let shareDirName = URL(fileURLWithPath: share)
                        //
                        // get the last component of the share, since this is the name of the mount-directory
                        if let shareMountDir = shareDirName.pathComponents.last {
                            //
                            // ignore if the mount is correct (both shareDir and mountedDir have the same name)
                            if filePath != shareMountDir {
                                //
                                // rudimentary check for XXX-1, XXX-2, ... mountdirs
                                // sure, this could be done better (e.g. regex mathcing), but I don't think it's worth thinking about
                                for count in 1...20 {
                                    if filePath.contains(shareMountDir + "-\(count)") {
                                        NSLog("Duplicatre mount of \(share): it is already mounted as \(path.appendingPathComponent(filePath)). Trying to unmount...")
                                        unmountShare(atPath: path.appendingPathComponent(filePath))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } catch let error as NSError {
            NSLog("Could not list directory at \(path): \(error.debugDescription)")
        }
    }

    func createShareArray() -> [String] {
        //
        // create array from values configured in UserDefaults
        var shares: [String] = UserDefaults.standard.array(forKey: "networkShares") as? [String] ?? []
        let customshares = UserDefaults.standard.array(forKey: "customNetworkShares") as? [String] ?? []
        for share in customshares {
            shares.append(share)
        }
        //
        // replace %USERNAME with local username - must be the same as directory service username!
        shares = shares.map {
            $0.replacingOccurrences(of: "%USERNAME%", with: NSUserName())
        }
        
        //
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
            NSLog("Couldn't add user's home directory to the list of shares ro mount.")
        }
        
        //
        // eliminate duplicates
        // swiftlint:disable force_cast
        shares = NSOrderedSet(array: shares).array as! [String]
        // swiftlint:enable force_cast
        return(shares)
    }

    func prepareMountPrerequisites() {
        // iterate through all files defined in config file (e.g. .autodiskmounted, .DS_Store)
        for toDelete in Settings.filesToDelete {
            deleteUnneededFiles(path: self.mountpath, filename: toDelete)
        }

        // The directory with the mounts for the network-shares should be empty. All
        // former directories not deleted by the mounter should be nuked to avoid
        // creating new mount-points (=> directories) like projekte-1 projekte-2 and so on

        deleteUnneededFiles(path: mountpath, filename: nil)
    }

    func mountShares() {
        //
        // Check for network connectivity
        let netConnection = Monitor.shared
        if netConnection.netOn {
            //let shares = prepareMountPrerequisites()
            let shares = createShareArray()
            
            if shares.isEmpty {
                NSLog("no shares configured!")
            } else {
                let shareMounterQueue = DispatchQueue(label: "ShareMounter Queue", qos: .background, attributes: .concurrent)
                
                for share in shares {
                    //
                    // Switched back to synchronous mount instead of NetFSMountURLAsync
                    // Letting NetFSMountURLAsync doing the threading could result in multiple mounts of one
                    // single share every time the network connectivity changes before the share was mounted.
                    // Doing the mount asynchronously is important to prevent blockign of the app. But doing
                    // the queueing by hand gives more control over the mount process
                    shareMounterQueue.async(flags: .barrier) {
                        do {
                            self.prepareMountPrerequisites()
                            try self.doTheMount(forShare: share)
                        } catch {
                            NSLog("Mounting of share \(share) failed.")
                        }
                    }
                }
            }
        } else {
            NSLog("No network connection available, connection type is \(netConnection.connType)")
            return
        }
    }

    func doTheMount(forShare share: String) throws {
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
        guard let encodedShare = share.addingPercentEncoding(withAllowedCharacters: csCopy) else {
            throw MounterError.errorOnEncodingShareURL
        }
        guard let url = NSURL(string: encodedShare) else {
            throw MounterError.invalidMountURL
        }
        guard let host = url.host else {
            throw MounterError.invalidHost
        }

        // check if we have network connectivity
        var flags = SCNetworkReachabilityFlags(rawValue: 0)
        let hostReachability = SCNetworkReachabilityCreateWithName(nil, (host as NSString).utf8String!)
        guard SCNetworkReachabilityGetFlags(hostReachability!, &flags) == true else {
            NSLog("could not determine reachability for host \(host)")
            throw MounterError.couldNotTestConnectivity
        }
        guard flags.contains(.reachable) == true else {
            NSLog("\(host): target not reachable")
            throw MounterError.targetNotReachable
        }

        //
        // check if there is already filesystem-mount named like the share
        let dir = URL(fileURLWithPath: share)
        guard let mountDir = dir.pathComponents.last else {
            NSLog("could not determine mount dir component of share \(share)")
            throw MounterError.errorCheckingMountDir
        }
        //
        // check if there's already a directory named like the share
        if !isDirectoryFilesystemMount(atPath: mountpath.appendingPathComponent(mountDir)) {
            NSLog("Mount of \(url): queued...")
            let rc = NetFSMountURLSync(url,
                                       NSURL(string: self.mountpath),
                                       nil,
                                       nil,
                                       Settings.openOptions,
                                       Settings.mountOptions,
                                       nil)
            switch rc {
                case 0:
                    NSLog("\(url): successfully mounted")
                    //return(true)
                case 2:
                    NSLog("\(url): does not exist")
                case 17:
                    NSLog("\(url): already mounted")
                    //return(true)
                case 65:
                    NSLog("\(url): no route to host")
                case -6003:
                    NSLog("\(url): share does not exist")
                default:
                    NSLog("\(url) unknown return code: \(rc)")
            }

        } else {
            NSLog("\(url): already mounted")
        }
    }
}


//
// stuff to unmount shares
extension Mounter {
    //
    // prepares list of shares to unmount
    func unmountAllShares() {
        let mountpath = self.mountpath
        let shares = createShareArray()
        for share in shares {
            let dir = URL(fileURLWithPath: share)
            guard let mountDir = dir.pathComponents.last else {
                return
            }
            unmountShare(atPath: mountpath.appendingPathComponent(mountDir))
        }
    }

    
    //
    // function to unmount share at a given path
    func unmountShare(atPath path: String) {
        //
        // check if path is really a filesystem mount
        if isDirectoryFilesystemMount(atPath: path) {
            NSLog("Trying to unmount share at path \(path).")
            //fileManager.unmountVolume(at: url, options: FileManager.UnmountOptions.init(), completionHandler: {(_) in})
            fm.unmountVolume(at: URL(fileURLWithPath:path), options: [FileManager.UnmountOptions.allPartitionsAndEjectDisk, FileManager.UnmountOptions.withoutUI], completionHandler: {(_) in})
        }
    }
}
