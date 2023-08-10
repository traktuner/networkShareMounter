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
        /// or `Settings.mdmNetworkSahresKey` und user defined `Settings.customSharesKey`.
        ///
        /// **Imprtant**:
        /// - read only `Settings.mdmNetworkSahresKey` *OR* `Settings.networkSharesKey`, not both arays
        /// - then read user defined `Settings.customSharesKey`
        ///
        /// first look if we have mdm share definitions
        if let sharesDict = userDefaults.array(forKey: Settings.managedNetworkSharesKey) as? [[String: String]] {
            for shareElement in sharesDict {
                guard let shareUrlString = shareElement[Settings.networkShare] else {
                    continue
                }
                //
                // check if there is a mdm defined username. If so, replace possible occurencies of %USERNAME% with that
                var userName: String = ""
                if let username = shareElement[Settings.username] {
                    userName = username.replacingOccurrences(of: "%USERNAME%", with: NSUserName())
                    userName = NSString(string: userName).expandingTildeInPath
                }
                
                //
                // replace possible %USERNAME occurencies with local username - must be the same as directory service username!
                let shareRectified = shareUrlString.replacingOccurrences(of: "%USERNAME%", with: NSUserName())
                guard let shareURL = URL(string: shareRectified) else {
                    continue
                }
                let shareAuthType = AuthType(rawValue: shareElement[Settings.authType] ?? AuthType.krb.rawValue) ?? AuthType.krb
               
                let newShare = Share.createShare(networkShare: shareURL, authType: shareAuthType, mountStatus: MountStatus.unmounted, username: userName, mountPoint: shareElement[Settings.mountPoint])
                addShareIfNotDuplicate(newShare)
            }
        } else if let nwShares: [String] = userDefaults.array(forKey: Settings.networkSharesKey) as? [String] {
            /// then look if we have some legacy mdm defined share definitions which will be read **only** if there is no `Settings.mdmNetworkSahresKey` defined!
            for share in nwShares {
                //
                // replace possible %USERNAME occurencies with local username - must be the same as directory service username!
                let shareRectified = share.replacingOccurrences(of: "%USERNAME%", with: NSUserName())
                guard let shareURL = URL(string: shareRectified) else {
                    continue
                }
                let newShare = Share.createShare(networkShare: shareURL, authType: AuthType.krb, mountStatus: MountStatus.unmounted)
                addShareIfNotDuplicate(newShare)
            }
        }
        // finally get shares defined by the user
        if let sharesDict = userDefaults.array(forKey: Settings.customSharesKey) as? [[String: String]] {
            for shareElement in sharesDict {
                guard let shareUrlString = shareElement[Settings.networkShare] else {
                    continue
                }
                guard let shareURL = URL(string: shareUrlString) else {
                    continue
                }
                let shareAuthType = AuthType(rawValue: shareElement[Settings.authType] ?? AuthType.krb.rawValue) ?? AuthType.krb
                let newShare = Share.createShare(networkShare: shareURL, authType: shareAuthType, mountStatus: MountStatus.unmounted, username: shareElement[Settings.username])
                addShareIfNotDuplicate(newShare)
            }
        }
        // maybe even here we may have legacy user defined share definitions
        if let nwShares: [String] = userDefaults.array(forKey: Settings.customSharesKey) as? [String] {
            for share in nwShares {
                guard let shareURL = URL(string: share) else {
                    continue
                }
                let newShare = Share.createShare(networkShare: shareURL, authType: AuthType.krb, mountStatus: MountStatus.unmounted)
                addShareIfNotDuplicate(newShare)
            }
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
                    addShareIfNotDuplicate(newShare)
                }
            }
            // swiftlint:enable force_cast
        } catch {
            /// Couldn't perform mount operation, but this does not have to be a fault in non-AD/krb5 environments
            logger.info("Couldn't add user's home directory to the list of shares to mount.")
        }
        // now create the directory where the shares will be mounted
        // check if there is a definition where the shares will be mounted, otherwiese use the default
        if userDefaults.object(forKey: "location") as? String != "" {
            defaultMountPath = NSString(string: userDefaults.string(forKey: "location")!).expandingTildeInPath
        } else {
            defaultMountPath = NSString(string: "~/\(Settings.translation[Locale.current.languageCode!] ?? Settings.translation["en"]!)").expandingTildeInPath
        }
        createMountFolder(atPath: defaultMountPath)
    }
    
    /// checks if there is already a share with the same network export. If not,
    /// adds the given share to the array of shares
    /// - Parameter share: share object to check and append to shares array
    func addShareIfNotDuplicate(_ share: Share) {
        if !shareManager.allShares.contains(where: { $0.networkShare == share.networkShare }) {
            shareManager.addShare(share)
            shares = shareManager.allShares
        }
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
   
    /// prepare folder where the shares will be mounted. It is basically the parent folder containing the mounts
    /// - Parameter atPath: path where the folder will be created
    func createMountFolder(atPath mountPath: String) {
        do {
            //
            // try to create (if not exists) the directory where the network shares will be mounted
            if !fm.fileExists(atPath: defaultMountPath) {
                try fm.createDirectory(atPath: defaultMountPath, withIntermediateDirectories: false, attributes: nil)
                logger.info("Base network mount directory \(self.defaultMountPath, privacy: .public): created")
            }
        } catch {
            logger.error("Error creating mount folder: \(self.defaultMountPath, privacy: .public):")
            logger.error("error.localizedDescription")
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
        } catch let error as NSError {
            // since we are checking directories that in most cases do not exists, we do net need to log that, I think
            // logger.warning("Could not check directory at \(atPath): \(error.debugDescription, privacy: .public)")
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
                                        unmountShare(atPath: path.appendingPathComponent(filePath)) { result in
                                            switch result {
                                            case .success:
                                                self.logger.info("Successfully unmounted \(path.appendingPathComponent(filePath), privacy: .public).")
                                            case .failure(let error):
                                                // error on unmount
                                                switch error {
                                                case .invalidMountPath:
                                                    self.logger.warning("Could not unmount \(path.appendingPathComponent(filePath), privacy: .public): invalid mount path")
                                                    print("Ungültiger Mount-Pfad.")
                                                case .unmountFailed:
                                                    self.logger.warning("Could not unmount \(path.appendingPathComponent(filePath), privacy: .public): unmount failed")
                                                    print("Unmount fehlgeschlagen.")
                                                default:
                                                    self.logger.info("Could not unmount \(path.appendingPathComponent(filePath), privacy: .public): unknown error")
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
    func unmountShare(atPath path: String, completion: @escaping (Result<Void, MounterError>) -> Void) {
        // check if path is really a filesystem mount
        if isDirectoryFilesystemMount(atPath: path) {
            logger.info("Trying to unmount share at path \(path, privacy: .public).")
            
            let url = URL(fileURLWithPath: path)
            fm.unmountVolume(at: url, options: [.allPartitionsAndEjectDisk, .withoutUI]) { [self] (error) in
                if let error = error {
                    completion(.failure(.unmountFailed))
                } else {
                    completion(.success(()))
                    removeDirectory(atPath: URL(string: url.absoluteString)!.relativePath)
                }
            }
        } else {
            completion(.failure(.invalidMountPath))
        }
    }
    
    ///
    /// get all mounted shares and call `unmountShare`
    func unmountAllShares() async {
        let mountpath = self.defaultMountPath
        for share in shares {
            let dir = share.networkShare
            guard let mountDir = dir.pathComponents.last else {
                continue
            }
            
            unmountShare(atPath: mountpath.appendingPathComponent(mountDir)) { result in
                switch result {
                case .success:
                    self.logger.info("Successfully unmounted \(mountpath.appendingPathComponent(mountDir), privacy: .public).")
                    // share status update
                    self.updateShare(mountStatus: .unmounted, for: share)
                case .failure(let error):
                    // error on unmount
                    switch error {
                    case .invalidMountPath:
                        self.logger.warning("Could not unmount \(mountpath.appendingPathComponent(mountDir), privacy: .public): invalid mount path")
                        self.updateShare(mountStatus: .unmounted, for: share)
                    case .unmountFailed:
                        self.logger.warning("Could not unmount \(mountpath.appendingPathComponent(mountDir), privacy: .public): unmount failed")
                        self.updateShare(mountStatus: .mounted, for: share)
                    default:
                        self.logger.info("Could not unmount \(mountpath.appendingPathComponent(mountDir), privacy: .public): unknown error")
                        self.updateShare(mountStatus: .errorOnMount, for: share)
                    }
                }
            }
        }
        prepareMountPrerequisites()
    }
    ///
    /// prepare parent directory where the shares will be mounted
    func prepareMountPrerequisites() {
        // iterate through all files defined in config file (e.g. .autodiskmounted, .DS_Store)
        for toDelete in Settings.filesToDelete {
            deleteUnneededFiles(path: self.defaultMountPath, filename: toDelete)
        }

        // The directory with the mounts for the network-shares should be empty. All
        // former directories not deleted by the mounter should be nuked to avoid
        // creating new mount-points (=> directories) like projekte-1 projekte-2 and so on
        deleteUnneededFiles(path: defaultMountPath, filename: nil)
    }
    
    /// performs mount operation for all shares
    func mountAllShares() {
        //
        // Check for network connectivity
        let netConnection = Monitor.shared
        
        if netConnection.netOn {
            if self.shares.isEmpty {
                logger.info("No shares configured.")
            } else {
                // perform cleanup routines before mounting
                prepareMountPrerequisites()
                for share in shares {
                    Task {
                        do {
                            // TODO: define mountpath (mountdir and under which name)
                            try await mountShare(forShare: share, atPath: defaultMountPath)
                        } catch {
                            logger.info("Mounting of share \(share.networkShare, privacy: .public) not done.")
                        }
                    }
                }
            }
        } else {
            logger.warning("No network connection available, connection type is \(netConnection.connType.rawValue, privacy: .public)")
        }
    }
    
    /// this function performs the mount of a given remote share on a local mountpoint
    func mountShare(forShare share: Share, atPath mountPath: String) async throws {
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
            self.updateShare(mountStatus: .errorOnMount, for: share)
            throw MounterError.errorOnEncodingShareURL
        }
        guard let url = NSURL(string: encodedShare) else {
            logger.warning("could not encode share for \(share.networkShare, privacy: .public)")
            self.updateShare(mountStatus: .errorOnMount, for: share)
            throw MounterError.invalidMountURL
        }
//        logger.warning("URL is: \(url.absoluteString, privacy: .public) - and escapedString is \(encodedShare, privacy: .public)")
//        let encodedShare = self.shares[index].networkShare.absoluteString
        guard let host = url.host else {
            logger.warning("could not determine hostname for \(share.networkShare, privacy: .public)")
            self.updateShare(mountStatus: .errorOnMount, for: share)
            throw MounterError.invalidHost
        }

        // check if we have network connectivity
        var flags = SCNetworkReachabilityFlags(rawValue: 0)
        let hostReachability = SCNetworkReachabilityCreateWithName(nil, (host as NSString).utf8String!)
        guard SCNetworkReachabilityGetFlags(hostReachability!, &flags) == true else {
            logger.warning("could not determine reachability for host \(host, privacy: .public)")
            self.updateShare(mountStatus: .toBeMounted, for: share)
            throw MounterError.couldNotTestConnectivity
        }
        guard flags.contains(.reachable) == true else {
            logger.warning("\(host, privacy: .public): target not reachable")
            self.updateShare(mountStatus: .toBeMounted, for: share)
            throw MounterError.targetNotReachable
        }

        //
        // check if there is already filesystem-mount named like the share
        let dir = URL(fileURLWithPath: encodedShare)
        guard let mountDir = dir.pathComponents.last else {
            logger.warning("could not determine mount dir component of share \(encodedShare, privacy: .public)")
            self.updateShare(mountStatus: .errorOnMount, for: share)
            throw MounterError.errorCheckingMountDir
        }
        
        
        //
        // check if there's already a directory named like the share
        if !isDirectoryFilesystemMount(atPath: defaultMountPath.appendingPathComponent(mountDir)) {
            // if mountStatus is not `mounted` and not `queued` (aka currently trying to mount) and not `errorOnMount` -> try the mount
            if share.mountStatus != MountStatus.mounted && share.mountStatus != MountStatus.queued && share.mountStatus != MountStatus.errorOnMount {
                logger.info("Mount of \(url, privacy: .public) on path \(mountPath, privacy: .public) queued...")
                self.updateShare(mountStatus: .queued, for: share)
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
                var mountDirectory = defaultMountPath
                if let mountPoint = share.mountPoint {
                    mountDirectory += "/" + mountPoint
                } else {
                    mountDirectory += "/" + (url.lastPathComponent ?? "")
                }
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
                    self.updateShare(mountStatus: .mounted, for: share)
                    logger.info("\(url, privacy: .public): successfully mounted")
                case 2:
                    self.updateShare(mountStatus: .errorOnMount, for: share)
                    logger.info("\(url, privacy: .public): does not exist")
                    throw MounterError.doesNotExist
                case 17:
                    self.updateShare(mountStatus: .mounted, for: share)
                    logger.info("\(url, privacy: .public): already mounted")
                    throw MounterError.alreadyMounted
                case 65:
                    self.updateShare(mountStatus: .toBeMounted, for: share)
                    logger.info("\(url, privacy: .public): no route to host")
                    throw MounterError.noRouteToHost
                case -6003:
                    self.updateShare(mountStatus: .errorOnMount, for: share)
                    logger.info("\(url, privacy: .public): share does not exist")
                    throw MounterError.shareDoesNotExist
                default:
                    self.updateShare(mountStatus: .errorOnMount, for: share)
                    logger.warning("\(url, privacy: .public) unknown return code: \(rc)")
                    throw MounterError.unknownReturnCode
                }
            } else if share.mountStatus == MountStatus.mounted {
                logger.info("Share \(url, privacy: .public) is apparently already mounted.")
                throw MounterError.alreadyMounted
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
            self.updateShare(mountStatus: .mounted, for: share)
            logger.info("\(url, privacy: .public): already mounted")
            throw MounterError.alreadyMounted
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
