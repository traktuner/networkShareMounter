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

/// enum following the ``Error`` protocol describing various shre mount error results
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
    case mountIsQueued
    case targetNotReachable
    case otherError
    case noRouteToHost
    case doesNotExist
    case shareDoesNotExist
    case unknownReturnCode
    case invalidMountPath
    case unmountFailed
    case timedOutHost
    case authenticationError
    case hostIsDown
}

/// defines authentication type to mount a share
/// - Parameter krb: kerberos authentication
/// - Parameter pwd: username/password authentication
enum AuthType: String {
    case krb = "krb"
    case pwd = "pwd"
}

/// classe tro perform mount/unmount operations for network shares
class Mounter: ObservableObject {
    /// @Published var shares: [Share] allows publishing changes to the shares array
    @Published var shares = [Share]()
    private var shareManager = ShareManager()
    
    /// convenience variable for `FileManager.default`
    private let fm = FileManager.default
    /// convenience variable for `UserDefaults.standard`
    private let userDefaults = UserDefaults.standard
    /// logger variable to produce consistent log entries
    let logger = Logger(subsystem: "NetworkShareMounter", category: "Mounter")
    /// initalize class which will perform all the automounter tasks
    static let mounter = Mounter.init()
    /// define locks to protect `shares`-array from race conditions
    private let lock = NSLock()
    /// get home direcotry for the user running the app
    let userHomeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    
    // TODO: this code should be cleaned up for new userDefaults values
    private var localizedFolder = Settings.translation[Locale.current.languageCode!] ?? Settings.translation["en"]!
    var defaultMountPath: String = NSString(string: "~/\(Settings.translation[Locale.current.languageCode!] ?? Settings.translation["en"]!)").expandingTildeInPath
//    var defaultMountPath = UserDefaults.standard.object(forKey: "location") as? String ?? Settings.defaultMountPath
    
    init() {
        /// initialize the class with the array of shares containig the network shares
        self.shares = shareManager.allShares
        
        /// create an array from values configured in UserDefaults
        /// import configured shares from userDefaults for both mdm defined (legacy)`Settings.networkSharesKey`
        /// or `Settings.mdmNetworkSahresKey` and user defined `Settings.customSharesKey`.
        ///
        /// **Imprtant**:
        /// - read only `Settings.mdmNetworkSahresKey` *OR* `Settings.networkSharesKey`, NOT both arrays
        /// - then read user defined `Settings.customSharesKey`
        ///
        if let sharesDict = userDefaults.array(forKey: Settings.managedNetworkSharesKey) as? [[String: String]] {
            for shareElement in sharesDict {
                if let newShare = shareManager.getMDMShareConfig(forShare: shareElement) {
                    addShare(newShare)
                }
            }
        }
        /// alternatively try to get configured shares with now obsolete
        /// Network Share Mounter 2 definitions
        else if let nwShares: [String] = userDefaults.array(forKey: Settings.networkSharesKey) as? [String] {
            for share in nwShares {
                if let newShare = shareManager.getLegacyShareConfig(forShare: share) {
                    addShare(newShare)
                }
            }
        }
        /// next look if there are some user-defined shares to import
        if let privSharesDict = userDefaults.array(forKey: Settings.managedNetworkSharesKey) as? [[String: String]] {
            for share in privSharesDict {
                if let newShare = shareManager.getUserShareConfigs(forShare: share) {
                    addShare(newShare)
                }
            }
        }
        /// at last there may be legacy user defined share definitions
        else if let nwShares: [String] = userDefaults.array(forKey: Settings.customSharesKey) as? [String] {
            for share in nwShares {
                guard let shareURL = URL(string: share) else {
                    continue
                }
                addShare(Share.createShare(networkShare: shareURL, authType: AuthType.krb, mountStatus: MountStatus.unmounted))
            }
            // TODO: convert those legacy entries to new UserDefaults definition
        }

        ///
        /// try to to get SMBHomeDirectory (only possible in AD/Kerberos environments) and
        /// add the home-share to `shares`
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
                if let shareURL = URL(string: homeDirectory) {
                    let newShare = Share.createShare(networkShare: shareURL, authType: AuthType.krb, mountStatus: MountStatus.unmounted)
                    addShare(newShare)
                }
            }
            // swiftlint:enable force_cast
        } catch {
            /// Couldn't perform mount operation, but this does not have to be a fault in non-AD/krb5 environments
            logger.info("Couldn't add user's home directory to the list of shares to mount.")
        }
        // now create the directory where the shares will be mounted
        // check if there is a definition where the shares will be mounted, otherwiese use the default
        if userDefaults.object(forKey: "location") as? String != nil {
            defaultMountPath = NSString(string: userDefaults.string(forKey: "location")!).expandingTildeInPath
        } else {
            defaultMountPath = NSString(string: "~/\(Settings.translation[Locale.current.languageCode!] ?? Settings.translation["en"]!)").expandingTildeInPath
        }
        createMountFolder(atPath: defaultMountPath)
    }
    
    /// checks if there is already a share with the same network export. If not,
    /// adds the given share to the array of shares
    /// - Parameter share: share object to check and append to shares array
    func addShare(_ share: Share) {
        shareManager.addShare(share)
        shares = shareManager.allShares
    }
    
    /// deletes a share at the given Index
    /// - Parameter indexSet: array index of the element
    func removeShare(for share: Share) {
        if let index = shareManager.allShares.firstIndex(where: { $0.id == share.id }) {
            logger.info("Deleting share: \(share.networkShare, privacy: .public) at Index \(index, privacy: .public)")
            shareManager.removeShare(at: index)
            shares = shareManager.allShares
        }
    }
    
    /// Update a share object at a specific index and update the shares array
    func updateShare(for share: Share) {
        if let index = shareManager.allShares.firstIndex(where: { $0.id == share.id }) {
            shareManager.updateShare(at: index, withUpdatedShare: share)
            shares = shareManager.allShares
        }
    }
    
    /// update mountStatus for a share element
    /// - Parameter mountStatus: new MountStatus
    /// - Parameter for: share to be updated
//    func updateShare(mountStatus: MountStatus, for share: Share) {
//        if let index = shares.firstIndex(where: { $0.id == share.id }) {
//            shares[index].mountStatus = mountStatus
//        }
//    }
    func updateShare(mountStatus: MountStatus, for share: Share) {
        if let index = shareManager.allShares.firstIndex(where: { $0.id == share.id }) {
            shareManager.updateMountStatus(at: index, to: mountStatus)
            shares = shareManager.allShares
        }
    }
    
    /// update the actualMountPoint for a share element
    /// - Parameter actualMountPoint: an optional `String` definig where the share is mounted (or not, if not defined)
    /// - Parameter for: share to be updated
    func updateShare(actualMountPoint: String?, for share: Share) {
        if let index = shareManager.allShares.firstIndex(where: { $0.id == share.id }) {
            shareManager.updateActualMountPoint(at: index, to: actualMountPoint)
            shares = shareManager.allShares
        }
    }
   
    /// prepare folder where the shares will be mounted. It is basically the parent folder containing the mounts
    /// - Parameter atPath: path where the folder will be created
    func createMountFolder(atPath mountPath: String) {
        do {
            //
            // try to create (if not exists) the directory where the network shares will be mounted
            if !fm.fileExists(atPath: mountPath) {
                try fm.createDirectory(atPath: mountPath, withIntermediateDirectories: false, attributes: nil)
                logger.info("Base network mount directory \(mountPath, privacy: .public): created")
            }
        } catch {
            logger.error("Error creating mount folder: \(mountPath, privacy: .public):")
            logger.error("\(error.localizedDescription)")
            exit(2)
        }
    }
    
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
        } catch {
            return false
        }
        return false
    }
    
    /// function to delete a directory via system shell `rmdir`
    /// - Paramater atPath: full path of the directory
    func removeDirectory(atPath: String) {
        let task = Process()
        task.launchPath = "/bin/rmdir"
        task.arguments = ["\(atPath)"]
        let pipe = Pipe()
        task.standardOutput = pipe
        //
        // Launch the task
        task.launch()
        //
        // Get the data
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = NSString(data: data, encoding: String.Encoding.utf8.rawValue)
        logger.info("Deleting directory \(atPath, privacy: .public): \(output ?? "done", privacy: .public)")
    }
    
    /// function to delete obstructing files in mountDir Subdirectories
    /// - Parameter path: A string containing the path of the directory containing the mountpoints (`mountpath`)
    /// - Parameter filename: A string containing the name of an obstructing file which should be deleted if it is found
    func deleteUnneededFiles(path: String, filename: String?) async {
    // TODO: doing a cleanup only for the default mount dir cleans obstructing files and directories but not SHARE-1 SHARE-2 direcotries on other locations
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
                                    logger.info("Deleting obstructing file \(deleteFile, privacy: .public)")
                                    try fm.removeItem(atPath: deleteFile)
                                }
                            } else {
                                logger.info("Found file system mount at \(path.appendingPathComponent(filePath), privacy: .public). Not deleting it")
                            }
                        } else {
                            //
                            // else we have a directory to remove
                            // do not remove the top level directory containing the mountpoints
                            if filePath != "/" {
                                let deleteFile = path.appendingPathComponent(filePath)
                                removeDirectory(atPath: URL(string: deleteFile)!.relativePath)
                            }
                        }
                    }
                } else {
                    //
                    // directory is file-system mount.
                    // Now let's check if there is some SHARE-1, SHARE-2, ... mount and unmount it
                    //
                    // compare list of shares with mount
                    for share in self.shares {
                        let shareDirName = share.networkShare
                        //
                        // get the last component of the share, since this is the name of the mount-directory
                        if let shareMountDir = shareDirName.pathComponents.last {
                            //
                            // ignore if the mount is correct (both shareDir and mountedDir have the same name)
                            if filePath != shareMountDir {
                                //
                                // rudimentary check for XXX-1, XXX-2, ... mountdirs
                                // sure, this could be done better (e.g. regex mathcing), but I don't think it's worth thinking about
                                for count in 1...30 {
                                    if filePath.contains(shareMountDir + "-\(count)") {
                                        logger.info("Duplicate mount of \(share.networkShare, privacy: .public): it is already mounted as \(path.appendingPathComponent(filePath), privacy: .public). Trying to unmount...")
                                        await unmountShare(atPath: path.appendingPathComponent(filePath)) { [self] result in
                                            switch result {
                                            case .success:
                                                logger.info("Successfully unmounted \(path.appendingPathComponent(filePath), privacy: .public).")
                                            case .failure(let error):
                                                // error on unmount
                                                switch error {
                                                case .invalidMountPath:
                                                    logger.warning("Could not unmount \(path.appendingPathComponent(filePath), privacy: .public): invalid mount path")
                                                    print("Ungültiger Mount-Pfad.")
                                                case .unmountFailed:
                                                    logger.warning("Could not unmount \(path.appendingPathComponent(filePath), privacy: .public): unmount failed")
                                                    print("Unmount fehlgeschlagen.")
                                                default:
                                                    logger.info("Could not unmount \(path.appendingPathComponent(filePath), privacy: .public): unknown error")
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
            logger.error("Could not list directory at \(path, privacy: .public): \(error.debugDescription, privacy: .public)")
        }
    }
    
    ///
    /// function to unmount share at a given path
    /// - Parameter atPath: path where the share is mounted
    func unmountShare(atPath path: String, completion: @escaping (Result<Void, MounterError>) -> Void) async {
        // check if path is really a filesystem mount
        if isDirectoryFilesystemMount(atPath: path) {
            logger.info("Trying to unmount share at path \(path, privacy: .public).")
            
            let url = URL(fileURLWithPath: path)
            do {
                try await fm.unmountVolume(at: url, options: [.allPartitionsAndEjectDisk, .withoutUI])
                completion(.success(()))
                removeDirectory(atPath: URL(string: url.absoluteString)!.relativePath)
            } catch {
                completion(.failure(.unmountFailed))
            }
        } else {
            completion(.failure(.invalidMountPath))
        }
    }
    
    ///
    /// get all mounted shares (those with the property `actualMountPoint` set) and call `unmountShares`
    /// Since we do only log if an unmount call fails (and nothing else), this function does not need to throw
    func unmountAllMountedShares() async {
        for share in shares {
            if let mountpoint = share.actualMountPoint {
                await unmountShare(atPath: mountpoint) { [self] result in
                    switch result {
                    case .success:
                        logger.info("Successfully unmounted \(mountpoint, privacy: .public).")
                        // share status update
                        updateShare(mountStatus: .unmounted, for: share)
                        // remove/undefine share mountpoint
                        updateShare(actualMountPoint: nil, for: share)
                    case .failure(let error):
                        // error on unmount
                        switch error {
                        case .invalidMountPath:
                            logger.warning("Could not unmount \(mountpoint), privacy: .public): invalid mount path")
                            updateShare(mountStatus: .unmounted, for: share)
                            updateShare(actualMountPoint: nil, for: share)
                        case .unmountFailed:
                            logger.warning("Could not unmount \(mountpoint), privacy: .public): unmount failed")
                            updateShare(mountStatus: .undefined, for: share)
                            updateShare(actualMountPoint: nil, for: share)
                        default:
                            logger.info("Could not unmount \(mountpoint), privacy: .public): unknown error")
                            updateShare(mountStatus: .undefined, for: share)
                            updateShare(actualMountPoint: nil, for: share)
                        }
                    }
                }
            }
        }
        await prepareMountPrerequisites()
    }
    
    /// prepare parent directory where the shares will be mounted
    func prepareMountPrerequisites() async {
        // iterate through all files defined in config file (e.g. .autodiskmounted, .DS_Store)
        for toDelete in Settings.filesToDelete {
            await deleteUnneededFiles(path: self.defaultMountPath, filename: toDelete)
        }

        // The directory with the mounts for the network-shares should be empty. All
        // former directories not deleted by the mounter should be nuked to avoid
        // creating new mount-points (=> directories) like projekte-1 projekte-2 and so on
        
        // TODO: look if here "defaultMountPath" ist the right way to clean up share mounts. Maybe it's better to go through all defined shares, since some of them could use other mount paths
        await deleteUnneededFiles(path: defaultMountPath, filename: nil)
    }
    
    /// performs mount operation for all shares
    func mountAllShares() async {
        //
        // Check for network connectivity
        let netConnection = Monitor.shared
        
        if netConnection.netOn {
            if self.shares.isEmpty {
                logger.info("No shares configured.")
            } else {
                // perform cleanup routines before mounting
//                await prepareMountPrerequisites()
                for share in self.shares {
                    do {
                        // TODO: define mountpath (mountdir and under which name)
//                        self.updateShare(mountStatus: .queued, for: share)
                        let actualMountpoint = try await mountShare(forShare: share, atPath: defaultMountPath)
                        updateShare(actualMountPoint: actualMountpoint, for: share)
                    } catch MounterError.doesNotExist {
                        updateShare(mountStatus: .errorOnMount, for: share)
                    } catch MounterError.timedOutHost {
                        updateShare(mountStatus: .unrechable, for: share)
                    } catch MounterError.hostIsDown {
                        updateShare(mountStatus: .unrechable, for: share)
                    } catch MounterError.noRouteToHost {
                        updateShare(mountStatus: .unrechable, for: share)
                    } catch MounterError.authenticationError {
                        updateShare(mountStatus: .toBeMounted, for: share)
                    } catch MounterError.shareDoesNotExist {
                        updateShare(mountStatus: .errorOnMount, for: share)
                    } catch MounterError.mountIsQueued {
                        updateShare(mountStatus: .queued, for: share)
                    } catch {
                        updateShare(mountStatus: .errorOnMount, for: share)
                    }
                }
            }
        } else {
            logger.warning("No network connection available, connection type is \(netConnection.connType.rawValue, privacy: .public)")
        }
    }
    
    /// set mountStatus for all shares
    /// - Parameter to status: mount status of type MountStatus
    func setAllMountStatus(to status: MountStatus) async {
        for share in shares {
            updateShare(mountStatus: status, for: share)
        }
    }
    
    /// this function performs the mount of a given remote share on a local mountpoint
    func mountShare(forShare share: Share, atPath mountPath: String) async throws -> String {
        // oddly there is some undocumented magic done by addingPercentEncoding when the CharacterSet
        // used as reference is an underlying NSCharacterSet class. It appears, it encodes even the ":"
        // at the very beginning of the URL ( smb:// vs. smb0X0P+0// ). As a result, the host() function
        // of NSURL does not return a valid hostname.
        // So to workaround this magic, you need to make your CharacterSet a pure Swift object.
        // To do so, create a copy so that the evil magic is gone.
        // see https://stackoverflow.com/questions/44754996/is-addingpercentencoding-broken-in-xcode-9
        //
        let url = share.networkShare
        let csCopy = CharacterSet(bitmapRepresentation: CharacterSet.urlPathAllowed.bitmapRepresentation)
        guard let encodedShare = url.absoluteString.addingPercentEncoding(withAllowedCharacters: csCopy) else {
            logger.warning("could not encode share for \(share.networkShare, privacy: .public)")
            updateShare(mountStatus: .errorOnMount, for: share)
            throw MounterError.errorOnEncodingShareURL
        }
        guard let url = NSURL(string: encodedShare) else {
            logger.warning("could not encode share for \(share.networkShare, privacy: .public)")
            updateShare(mountStatus: .errorOnMount, for: share)
            throw MounterError.invalidMountURL
        }
        //        logger.warning("URL is: \(url.absoluteString, privacy: .public) - and escapedString is \(encodedShare, privacy: .public)")
        //        let encodedShare = self.shares[index].networkShare.absoluteString
        guard let host = url.host else {
            logger.warning("could not determine hostname for \(share.networkShare, privacy: .public)")
            updateShare(mountStatus: .errorOnMount, for: share)
            throw MounterError.invalidHost
        }
        
        // check if we have network connectivity
        var flags = SCNetworkReachabilityFlags(rawValue: 0)
        let hostReachability = SCNetworkReachabilityCreateWithName(nil, (host as NSString).utf8String!)
        guard SCNetworkReachabilityGetFlags(hostReachability!, &flags) == true else {
            logger.warning("could not determine reachability for host \(host, privacy: .public)")
            updateShare(mountStatus: .toBeMounted, for: share)
            throw MounterError.couldNotTestConnectivity
        }
        guard flags.contains(.reachable) == true else {
            logger.warning("\(host, privacy: .public): target not reachable")
            updateShare(mountStatus: .toBeMounted, for: share)
            throw MounterError.targetNotReachable
        }
        
        //
        // check if there is already filesystem-mount named like the share
        let dir = URL(fileURLWithPath: encodedShare)
        guard let mountDir = dir.pathComponents.last else {
            logger.warning("could not determine mount dir component of share \(encodedShare, privacy: .public)")
            updateShare(mountStatus: .errorOnMount, for: share)
            throw MounterError.errorCheckingMountDir
        }
        
        var mountDirectory = mountPath
        if let mountPoint = share.mountPoint {
            mountDirectory += "/" + mountPoint
        } else {
            mountDirectory += "/" + (url.lastPathComponent ?? "")
        }
        
        //        //
        //        // check if there's already a directory named like the share
        //        if !isDirectoryFilesystemMount(atPath: defaultMountPath.appendingPathComponent(mountDir)) {
        if !isDirectoryFilesystemMount(atPath: mountDirectory) {
            // if mountStatus is not `mounted` and not `queued` (aka currently trying to mount) and not `errorOnMount` -> try the mount
            //            if share.mountStatus != MountStatus.mounted && share.mountStatus != MountStatus.queued && share.mountStatus != MountStatus.errorOnMount {
            if share.mountStatus != MountStatus.queued && share.mountStatus != MountStatus.errorOnMount {
                logger.debug("Called mount of \(url, privacy: .public) on path \(mountPath, privacy: .public)")
                updateShare(mountStatus: .queued, for: share)
                var mountOptions = Settings.mountOptions
                //            var mountOptions = [
                //                kNetFSAllowSubMountsKey: true,
                //                kNetFSSoftMountKey: true
                //                ] as! CFMutableDictionary
                //
                // check if a specific mountpoint is defined. If yes, the mountpoint will be
                // added to the mountpath and kNetFSMountAtMountDirKey will be set to true.
                // this means, that the mount will be done on the specified mountpath instead
                // of below it
                // (https://github.com/phracker/MacOSX-SDKs/blob/master/MacOSX10.8.sdk/System/Library/Frameworks/NetFS.framework/Versions/A/Headers/NetFS.h
                // swiftlint:disable force_cast
                
                // new idea: mount at specific mountpoint instead of letting the OS do it
                //                var mountDirectory = defaultMountPath
                //                var mountDirectory = mountPath
                //                if let mountPoint = share.mountPoint {
                //                    mountDirectory += "/" + mountPoint
                //                } else {
                //                    mountDirectory += "/" + (url.lastPathComponent ?? "")
                //                }
                //                    mountOptions = [
                //                        kNetFSAllowSubMountsKey: true,
                //                        kNetFSSoftMountKey: true,
                //                        kNetFSMountAtMountDirKey: true
                //                    ] as! CFMutableDictionary
                //                }
                try fm.createDirectory(atPath: mountDirectory, withIntermediateDirectories: true)
                // swiftlint:enable force_cast
                let rc = NetFSMountURLSync(url as CFURL,
                                           NSURL(string: mountDirectory),
                                           share.username as CFString?,
                                           share.password as CFString?,
                                           Settings.openOptions,
                                           mountOptions,
                                           nil)
                switch rc {
                case 0:
                    logger.info("✅ \(url, privacy: .public): successfully mounted on \(mountDirectory, privacy: .public)")
                    return mountDirectory
                case 2:
                    logger.info("❌ \(url, privacy: .public): does not exist")
                    removeDirectory(atPath: URL(string: mountDirectory)!.relativePath)
                    throw MounterError.doesNotExist
                case 17:
                    logger.info("✅ \(url, privacy: .public): already mounted on \(mountDirectory, privacy: .public)")
                    return mountDirectory
                case 60:
                    logger.info("❌ \(url, privacy: .public): timeout reaching host")
                    removeDirectory(atPath: URL(string: mountDirectory)!.relativePath)
                    throw MounterError.timedOutHost
                case 64:
                    logger.info("❌ \(url, privacy: .public): host is down")
                    removeDirectory(atPath: URL(string: mountDirectory)!.relativePath)
                    throw MounterError.hostIsDown
                case 65:
                    logger.info("❌ \(url, privacy: .public): no route to host")
                    removeDirectory(atPath: URL(string: mountDirectory)!.relativePath)
                    throw MounterError.noRouteToHost
                case 80:
                    logger.info("❌ \(url, privacy: .public): authentication error")
                    removeDirectory(atPath: URL(string: mountDirectory)!.relativePath)
                    throw MounterError.authenticationError
                case -6003:
                    logger.info("❌ \(url, privacy: .public): share does not exist")
                    removeDirectory(atPath: URL(string: mountDirectory)!.relativePath)
                    throw MounterError.shareDoesNotExist
                default:
                    logger.warning("❌ \(url, privacy: .public) unknown return code: \(rc)")
                    removeDirectory(atPath: URL(string: mountDirectory)!.relativePath)
                    throw MounterError.unknownReturnCode
                }
            } else if share.mountStatus == MountStatus.queued {
                logger.info("Share \(url, privacy: .public) is already queued for mounting.")
                throw MounterError.mountIsQueued
            } else if share.mountStatus == MountStatus.errorOnMount {
                logger.info("Share \(url, privacy: .public) not mounted, last time I tried I got a mount error.")
                throw MounterError.otherError
            } else {
                logger.info("Share \(url, privacy: .public) not mounted, I do not know why. It just happened.")
                throw MounterError.otherError
            }
        } else {
            logger.info("✅ \(url, privacy: .public): already mounted on \(mountDirectory, privacy: .public)")
            return mountDirectory
        }
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
