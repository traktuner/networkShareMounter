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
import OSLog

/// enum followinf the ``Error`` protocol describing various error results
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

/// describes the different properties and states of a share
/// - Parameter mountUrl: ``URL`` containing the exporting server and share
/// - Parameter mountStatus: Optional ``MountStatus`` describing the actual mount status
/// - Parameter username: optional ``String`` containing the username needed to mount a share
/// - Parameter password: optional ``String`` containing the password to mount the share. Both username and password are retrieved from user's keychain
///
/// *The following variables could be useful in future versions:*
/// - options: array of parameters for the mount command
/// - autoMount: for future use, the possibility to not mount shares automatically
/// - localMountPoint: for future use, define a mount point for the share
struct Shares {
    var mountUrl: URL
    var mountStatus: MountStatus?
    var username: String?
    var password: String?
//    var options: [String]
//    var autoMount: Bool
//    var localMountPoint: String?
}

/// defines mount states of a share
/// - Parameter unmounted: share is not mounted
/// - Parameter mounted: mounted share
/// - Parameter queued: queued for mounting
/// - Parameter toBeMounted: share should be mounted
/// - Parameter errorOnMount: failed to mount a shared
enum MountStatus {
    case unmounted,
         mounted,
         queued,
         toBeMounted,
         errorOnMount
}

//class MounterNew: ObservableObject {
//    @Published var shares: Shares
//    
//    init() {
//        let networkShares: [String] = UserDefaults.standard.array(forKey: "networkShares") as? [String] ?? []
//        let customShares = UserDefaults.standard.array(forKey: "customNetworkShares") as? [String] ?? []
//    }
//}

class Mounter {

    var localizedFolder = Settings.translation[Locale.current.languageCode!] ?? Settings.translation["en"]!
    var mountpath: String
    let fm = FileManager.default
    let userDefaults = UserDefaults.standard
    
    let logger = Logger(subsystem: "NetworkShareMounter", category: "Mounter")
    
    //let url: URL
    fileprivate var asyncRequestId: AsyncRequestID?

    init() {
        // create subfolder in home to mount shares in
        if userDefaults.string(forKey: "location") != nil {
            self.mountpath = NSString(string: userDefaults.string(forKey: "location")!).expandingTildeInPath
        } else {
            self.mountpath = NSString(string: "~/\(self.localizedFolder)").expandingTildeInPath
        }

        do {
            //
            // try to create (if not exists) the directory where the network shares will be mounted
            if !fm.fileExists(atPath: mountpath) {
                try fm.createDirectory(atPath: mountpath, withIntermediateDirectories: false, attributes: nil)
                logger.info("Base network mount directory \(self.mountpath): created")
            }
        } catch {
            logger.error("Error creating mount folder: \(self.mountpath):")
            logger.error("error.localizedDescription")
            exit(2)
        }
        //
        //Start monitoring network connection
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

/// Extension for ``String`` to create a valid path from a bunch of strings
extension String {
    /// Returns a URL by appending the specified path component to self
    /// - Parameter _: A string containing the part of the path to be appended
    /// - Returns: A string containing a path URL
    func appendingPathComponent(_ string: String) -> String {
        return URL(fileURLWithPath: self).appendingPathComponent(string).path
    }
}


/// Extension for ``Mounter`` to check if a given file system path is a mountpoint of a remote filesystem
extension Mounter {
    /// Check if a given directory is a mount point for a (remote) file system
    /// - Parameter atPath: A string containig the path to check
    /// - Returns: A boolean set to true if the given directory path is a mountpoint
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
            logger.warning("Could not check directory at \(atPath): \(error.debugDescription)")
            return false
        }
        return false
    }
}

/// Extension for ``Mounter`` with a bunch of funtcions handling all the stuff around mounting shares
/// such as creating a list of shares to be mounted, cleaning up mountdirectory,
/// checking connectivity and so on
extension Mounter {
    /// function to delete obstructing files in mountDir Subdirectories
    /// - Parameter path: A string containing the path of the directory containing the mountpoints (`mountpath`)
    /// - Parameter filename: A string containing the name of an obstructing file which should be deleted if it is found
    func deleteUnneededFiles(path: String, filename: String?) {
        do {
            var filePaths = try fm.contentsOfDirectory(atPath: path)
            filePaths.append("/")
            for filePath in filePaths {
                //
                // check if directory is a (remote) filesystem mount
                // if directory is a regular directory go on
                if !isDirectoryFilesystemMount(atPath: path.appendingPathComponent(filePath)) {
                    //
                    // Clean up the directory containing the mounts only if defined in userdefaults
                    if userDefaults.bool(forKey: "cleanupLocationDirectory") == true {
                        //
                        // if the function has a parameter we want to handle files, not directories
                        if let unwrappedFilename = filename {
                            if !isDirectoryFilesystemMount(atPath: path.appendingPathComponent(filePath)) {
                                let deleteFile = path.appendingPathComponent(filePath).appendingPathComponent(unwrappedFilename)
                                if fm.fileExists(atPath: deleteFile) {
                                    logger.info("Deleting obstructing file \(deleteFile)")
                                    try fm.removeItem(atPath: deleteFile)
                                }
                            } else {
                                logger.info("Found file system mount at \(path.appendingPathComponent(filePath)). Not deleting it")
                            }
                        } else {
                            //
                            // else we have a directory to remove
                            // do not remove the top level directory containing the mountpoints
                            if filePath != "/" {
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
                                logger.info("Deleting obstructing directory \(deleteFile): \(output ?? "done")")
                            }
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
                                        logger.info("Duplicatre mount of \(share): it is already mounted as \(path.appendingPathComponent(filePath)). Trying to unmount...")
                                        unmountShare(atPath: path.appendingPathComponent(filePath))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } catch let error as NSError {
            logger.error("Could not list directory at \(path): \(error.debugDescription)")
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
            logger.warning("Couldn't add user's home directory to the list of shares ro mount.")
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
                logger.info("No shares configured.")
            } else {
                let shareMounterQueue = DispatchQueue(label: "ShareMounter Queue", qos: .background, attributes: .concurrent)
                
                for share in shares {
                    //
                    // Switched back to synchronous mount instead of NetFSMountURLAsync
                    // Letting NetFSMountURLAsync doing the threading could result in multiple mounts of one
                    // single share every time the network connectivity changes before the share was mounted.
                    // Doing the mount asynchronously is important to prevent blockign of the app. But doing
                    // the queueing by hand gives more control over the mount process
                    shareMounterQueue.async(flags: .barrier) { [self] in
                        do {
                            self.prepareMountPrerequisites()
                            try self.doTheMount(forShare: share)
                        } catch {
                            logger.warning("Mounting of share \(share) failed.")
                        }
                    }
                }
            }
        } else {
            logger.warning("No network connection available, connection type is \(netConnection.connType.rawValue)")
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
            logger.warning("could not determine reachability for host \(host)")
            throw MounterError.couldNotTestConnectivity
        }
        guard flags.contains(.reachable) == true else {
            logger.warning("\(host): target not reachable")
            throw MounterError.targetNotReachable
        }

        //
        // check if there is already filesystem-mount named like the share
        let dir = URL(fileURLWithPath: share)
        guard let mountDir = dir.pathComponents.last else {
            logger.warning("could not determine mount dir component of share \(share)")
            throw MounterError.errorCheckingMountDir
        }
        //
        // check if there's already a directory named like the share
        if !isDirectoryFilesystemMount(atPath: mountpath.appendingPathComponent(mountDir)) {
            logger.info("Mount of \(url): queued...")
            let rc = NetFSMountURLSync(url,
                                       NSURL(string: self.mountpath),
                                       nil,
                                       nil,
                                       Settings.openOptions,
                                       Settings.mountOptions,
                                       nil)
            switch rc {
                case 0:
                    logger.info("\(url): successfully mounted")
                    //return(true)
                case 2:
                    logger.info("\(url): does not exist")
                case 17:
                    logger.info("\(url): already mounted")
                    //return(true)
                case 65:
                    logger.info("\(url): no route to host")
                case -6003:
                    logger.info("\(url): share does not exist")
                default:
                    logger.warning("\(url) unknown return code: \(rc)")
            }

        } else {
            logger.info("\(url): already mounted")
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
            logger.info("Trying to unmount share at path \(path).")
            //fileManager.unmountVolume(at: url, options: FileManager.UnmountOptions.init(), completionHandler: {(_) in})
            fm.unmountVolume(at: URL(fileURLWithPath:path), options: [FileManager.UnmountOptions.allPartitionsAndEjectDisk, FileManager.UnmountOptions.withoutUI], completionHandler: {(_) in})
        }
    }
}
