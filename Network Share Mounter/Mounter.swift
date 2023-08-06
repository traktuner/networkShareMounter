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
    case invalidMountPath
    case unmountFailed
}


/// describes the different properties and states of a share
/// - Parameter networkShare: ``URL`` containing the exporting server and share
/// - Parameter authType: ``authTyoe`` defines if the mount uses kerberos or username/password for authentication
/// - Parameter username: optional ``String`` containing the username needed to mount a share
/// - Parameter mountStatus: Optional ``MountStatus`` describing the actual mount status
/// - Parameter password: optional ``String`` containing the password to mount the share. Both username and password are retrieved from user's keychain
///
/// *The following variables could be useful in future versions:*
/// - options: array of parameters for the mount command
/// - autoMount: for future use, the possibility to not mount shares automatically
/// - localMountPoint: for future use, define a mount point for the share
struct Share: Identifiable {
    var networkShare: URL
    var authType: AuthType
    var username: String?
    var mountStatus: MountStatus
    var password: String?
    var mountPoint: String?
    var id = UUID()
//    var options: [String]
//    var autoMount: Bool
    
    func updated() -> Share {
        var updatedShare = self
        return updatedShare
    }
    
    func updated(withStatus status: MountStatus) -> Share {
        var updatedShare = self
        updatedShare.mountStatus = status
        return updatedShare
    }
}

/// defines mount states of a share
/// - Parameter unmounted: share is not mounted
/// - Parameter mounted: mounted share
/// - Parameter queued: queued for mounting
/// - Parameter toBeMounted: share should be mounted
/// - Parameter errorOnMount: failed to mount a shared
enum MountStatus: String {
    case unmounted = "unmounted"
    case mounted = "mounted"
    case queued = "queued"
    case toBeMounted = "toBeMounted"
    case errorOnMount = "errorOnMount"
}

/// defines authentication type to mount a share
/// - Parameter krb: kerberos authentication
/// - Parameter pwd: username/password authentication
enum AuthType: String {
    case krb = "krb"
    case pwd = "pwd"
}

class Mounter: ObservableObject {
    @Published var _shares = [Share]()
    
    private var localizedFolder = Settings.translation[Locale.current.languageCode!] ?? Settings.translation["en"]!
    var mountpath: String = NSString(string: "~/\(Settings.translation[Locale.current.languageCode!] ?? Settings.translation["en"]!)").expandingTildeInPath
    let userDefaults = UserDefaults.standard
    private let fm = FileManager.default
    let logger = Logger(subsystem: "NetworkShareMounter", category: "Mounter")
    
    //
    // initalize class which will perform all the automounter tasks
    static let mounter = Mounter.init()
    
    /// Locking to protect shares-array from race conditions
    private let lock = NSLock()
    
    var shares: [Share] {
        get {
            lock.lock()
            defer { lock.unlock() }
            return _shares
        }
        set {
            lock.lock()
            _shares = newValue
            lock.unlock()
        }
    }
    
    init() {
        //
        /// create an array from values configured in UserDefaults
        /// import configured shares from userDefaults for both mdm defined (legacy)`Settings.networkSharesKey`
        /// or `Settings.mdmNetworkSahresKey` und user defined `Settings.customSharesKey`
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
                }
                
                //
                // replace possible %USERNAME occurencies with local username - must be the same as directory service username!
                let shareRectified = shareUrlString.replacingOccurrences(of: "%USERNAME%", with: NSUserName())
                guard let shareURL = URL(string: shareRectified) else {
                    continue
                }
                let shareAuthType = AuthType(rawValue: shareElement[Settings.authType] ?? AuthType.krb.rawValue) ?? AuthType.krb
               
                let newShare = Share(networkShare: shareURL, authType: shareAuthType, username: userName, mountStatus: MountStatus.unmounted, mountPoint: shareElement[Settings.mountPoint])
                addShareIfNotDuplicate(newShare)
            }
        }
        // then look if we have some legacy mdm defined share definitions
        if let nwShares: [String] = userDefaults.array(forKey: Settings.networkSharesKey) as? [String] {
            for share in nwShares {
                //
                // replace possible %USERNAME occurencies with local username - must be the same as directory service username!
                let shareRectified = share.replacingOccurrences(of: "%USERNAME%", with: NSUserName())
                guard let shareURL = URL(string: shareRectified) else {
                    continue
                }
                let newShare = Share(networkShare: shareURL, authType: AuthType.krb, mountStatus: MountStatus.unmounted)
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
                let newShare = Share(networkShare: shareURL, authType: shareAuthType, username: shareElement[Settings.username], mountStatus: MountStatus.unmounted)
                addShareIfNotDuplicate(newShare)
            }
        }
        // maybe even here we may have legacy user defined share definitions
        if let nwShares: [String] = userDefaults.array(forKey: Settings.customSharesKey) as? [String] {
            for share in nwShares {
                guard let shareURL = URL(string: share) else {
                    continue
                }
                let newShare = Share(networkShare: shareURL, authType: AuthType.krb, mountStatus: MountStatus.unmounted)
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
                    let newShare = Share(networkShare: shareURL, authType: AuthType.krb, mountStatus: MountStatus.unmounted)
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
            mountpath = NSString(string: userDefaults.string(forKey: "location")!).expandingTildeInPath
        } else {
            mountpath = NSString(string: "~/\(Settings.translation[Locale.current.languageCode!] ?? Settings.translation["en"]!)").expandingTildeInPath
        }
        createMountFolder(atPath: mountpath)
    }
    
    /// checks if there is already a share with the same network export. If not,
    /// adds the given share to the array of shares
    /// - Parameter share: share object to check and append to shares array
    func addShareIfNotDuplicate(_ share: Share) {
        lock.lock()
        defer { lock.unlock() }
        if !_shares.contains(where: { $0.networkShare == share.networkShare }) {
            _shares.append(share)
        }
    }
    
    /// deletes a share at the given Index
    /// - Parameter indexSet: array index of the element
    func removeShare(for share: Share) {
        lock.lock()
        defer { lock.unlock() }
        if let index = _shares.firstIndex(where: { $0.id == share.id }) {
            logger.info("Deleting share: \(share.networkShare) at Index \(index)")
            _shares.remove(at: index)
        }
    }
    
    /// update a share element to new values.
    func updateShare(for share: Share) {
        lock.lock()
        defer { lock.unlock() }
        if let index = _shares.firstIndex(where: { $0.id == share.id }) {
            let updatedShare = share.updated()
            _shares[index] = updatedShare
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
        lock.lock()
        defer { lock.unlock() }
        if let index = _shares.firstIndex(where: { $0.id == share.id }) {
            let updatedShare = share.updated(withStatus: mountStatus) // Oder ein anderer neuer Status
            _shares[index] = updatedShare
        }
    }
   
    /// prepare folder where the shares will be mounted. It is basically the parent folder containing the mounts
    /// - Parameter atPath: path where the folder will be created
    func createMountFolder(atPath mountPath: String) {
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
            // logger.warning("Could not check directory at \(atPath): \(error.debugDescription)")
            return false
        }
        return false
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
                                        logger.info("Duplicate mount of \(share.networkShare): it is already mounted as \(path.appendingPathComponent(filePath)). Trying to unmount...")
                                        unmountShare(atPath: path.appendingPathComponent(filePath)) { result in
                                            switch result {
                                            case .success:
                                                self.logger.info("Successfully unmounted \(path.appendingPathComponent(filePath)).")
                                            case .failure(let error):
                                                // error on unmount
                                                switch error {
                                                case .invalidMountPath:
                                                    self.logger.warning("Could not unmount \(path.appendingPathComponent(filePath)): invalid mount path")
                                                    print("Ungültiger Mount-Pfad.")
                                                case .unmountFailed:
                                                    self.logger.warning("Could not unmount \(path.appendingPathComponent(filePath)): unmount failed")
                                                    print("Unmount fehlgeschlagen.")
                                                default:
                                                    self.logger.info("Could not unmount \(path.appendingPathComponent(filePath)): unknown error")
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
            logger.error("Could not list directory at \(path): \(error.debugDescription)")
        }
    }
    
    ///
    /// function to unmount share at a given path
    /// - Parameter atPath: path where the share is mounted
    func unmountShare(atPath path: String, completion: @escaping (Result<Void, MounterError>) -> Void) {
        // check if path is really a filesystem mount
        if isDirectoryFilesystemMount(atPath: path) {
            logger.info("Trying to unmount share at path \(path).")
            
            let url = URL(fileURLWithPath: path)
            fm.unmountVolume(at: url, options: [.allPartitionsAndEjectDisk, .withoutUI]) { (error) in
                if let error = error {
                    completion(.failure(.unmountFailed))
                } else {
                    completion(.success(()))
                }
            }
        } else {
            completion(.failure(.invalidMountPath))
        }
    }
    
    ///
    /// get all mounted shares and call `unmountShare`
    func unmountAllShares() async {
        let mountpath = self.mountpath
        for share in shares {
            let dir = share.networkShare
            guard let mountDir = dir.pathComponents.last else {
                continue
            }
            
            unmountShare(atPath: mountpath.appendingPathComponent(mountDir)) { result in
                switch result {
                case .success:
                    self.logger.info("Successfully unmounted \(mountpath.appendingPathComponent(mountDir)).")
                    // share status update
                    self.updateShare(mountStatus: .unmounted, for: share)
                case .failure(let error):
                    // error on unmount
                    switch error {
                    case .invalidMountPath:
                        self.logger.warning("Could not unmount \(mountpath.appendingPathComponent(mountDir)): invalid mount path")
                        self.updateShare(mountStatus: .unmounted, for: share)
                    case .unmountFailed:
                        self.logger.warning("Could not unmount \(mountpath.appendingPathComponent(mountDir)): unmount failed")
                        self.updateShare(mountStatus: .mounted, for: share)
                    default:
                        self.logger.info("Could not unmount \(mountpath.appendingPathComponent(mountDir)): unknown error")
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
            deleteUnneededFiles(path: self.mountpath, filename: toDelete)
        }

        // The directory with the mounts for the network-shares should be empty. All
        // former directories not deleted by the mounter should be nuked to avoid
        // creating new mount-points (=> directories) like projekte-1 projekte-2 and so on
        deleteUnneededFiles(path: mountpath, filename: nil)
    }
    
    /// performs mount operation for all shares
    func mountShares() {
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
                    // if mountStatus is not `mounted` and not `queued` (aka currently trying to mount) and not `errorOnMount` -> try the mount
                    if share.mountStatus != MountStatus.mounted && share.mountStatus != MountStatus.queued && share.mountStatus != MountStatus.errorOnMount {
                        Task {
                            do {
                                // TODO: define mountpath (mountdir and under which name)
                                try await mountShare(forShare: share, atPath: mountpath)
                            } catch {
                                logger.info("Mounting of share \(share.networkShare) not done.")
                            }
                        }
                    }
                }
            }
        } else {
            logger.warning("No network connection available, connection type is \(netConnection.connType.rawValue)")
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
            logger.warning("could not encode share for \(share.networkShare)")
            self.updateShare(mountStatus: .errorOnMount, for: share)
            throw MounterError.errorOnEncodingShareURL
        }
        guard let url = NSURL(string: encodedShare) else {
            logger.warning("could not encode share for \(share.networkShare)")
            self.updateShare(mountStatus: .errorOnMount, for: share)
            throw MounterError.invalidMountURL
        }
//        logger.warning("URL is: \(url.absoluteString) - and escapedString is \(encodedShare)")
//        let encodedShare = self.shares[index].networkShare.absoluteString
        guard let host = url.host else {
            logger.warning("could not determine hostname for \(share.networkShare)")
            self.updateShare(mountStatus: .errorOnMount, for: share)
            throw MounterError.invalidHost
        }

        // check if we have network connectivity
        var flags = SCNetworkReachabilityFlags(rawValue: 0)
        let hostReachability = SCNetworkReachabilityCreateWithName(nil, (host as NSString).utf8String!)
        guard SCNetworkReachabilityGetFlags(hostReachability!, &flags) == true else {
            logger.warning("could not determine reachability for host \(host)")
            self.updateShare(mountStatus: .toBeMounted, for: share)
            throw MounterError.couldNotTestConnectivity
        }
        guard flags.contains(.reachable) == true else {
            logger.warning("\(host): target not reachable")
            self.updateShare(mountStatus: .toBeMounted, for: share)
            throw MounterError.targetNotReachable
        }

        //
        // check if there is already filesystem-mount named like the share
        let dir = URL(fileURLWithPath: encodedShare)
        guard let mountDir = dir.pathComponents.last else {
            logger.warning("could not determine mount dir component of share \(encodedShare)")
            self.updateShare(mountStatus: .errorOnMount, for: share)
            throw MounterError.errorCheckingMountDir
        }
        
        
        //
        // check if there's already a directory named like the share
        if !isDirectoryFilesystemMount(atPath: mountpath.appendingPathComponent(mountDir)) {
            logger.info("Mount of \(url) on path \(mountPath) queued...")
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
            if let mountPoint = share.mountPoint {
                    mountpath += "/" + mountPoint
                    mountOptions = [
                        kNetFSAllowSubMountsKey: true,
                        kNetFSSoftMountKey: true,
                        kNetFSMountAtMountDirKey: true
                        ] as! CFMutableDictionary
            }
            // swiftlint:enable force_cast
            let rc = NetFSMountURLSync(url as CFURL,
                                       NSURL(string: mountpath),
                                       share.username as CFString?,
                                       share.password as CFString?,
                                       Settings.openOptions,
                                       mountOptions,
                                       nil)
            switch rc {
                case 0:
                    self.updateShare(mountStatus: .mounted, for: share)
                    logger.info("\(url): successfully mounted")
                case 2:
                    self.updateShare(mountStatus: .errorOnMount, for: share)
                    logger.info("\(url): does not exist")
                    throw MounterError.doesNotExist
                case 17:
                    self.updateShare(mountStatus: .mounted, for: share)
                    logger.info("\(url): already mounted")
                    throw MounterError.alreadyMounted
                case 65:
                    self.updateShare(mountStatus: .toBeMounted, for: share)
                    logger.info("\(url): no route to host")
                    throw MounterError.noRouteToHost
                case -6003:
                    self.updateShare(mountStatus: .errorOnMount, for: share)
                    logger.info("\(url): share does not exist")
                    throw MounterError.shareDoesNotExist
                default:
                    self.updateShare(mountStatus: .errorOnMount, for: share)
                    logger.warning("\(url) unknown return code: \(rc)")
                    throw MounterError.unknownReturnCode
            }

        } else {
            self.updateShare(mountStatus: .mounted, for: share)
            logger.info("\(url): already mounted")
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
