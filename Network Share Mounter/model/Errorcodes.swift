//
//  Errorcodes.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 19.12.23.
//  Copyright © 2024 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation

/// Defines error types that can occur during network share mount operations
///
/// This enum implements the `Error` protocol and provides a comprehensive set of error cases
/// that might occur during mounting, unmounting, and network operations related to shares.
/// Each case represents a specific error condition with localized descriptions to inform users.
enum MounterError: Error {
    /// Failed to create the directory where shares will be mounted
    case errorCreatingMountFolder
    
    /// Unable to determine or validate the mount directory component
    case errorCheckingMountDir
    
    /// Failed to encode the share URL properly
    case errorOnEncodingShareURL
    
    /// The provided mount URL is invalid or malformed
    case invalidMountURL
    
    /// The host portion of the URL is invalid or missing
    case invalidHost
    
    /// The mount point location cannot be accessed
    case mountpointInaccessible
    
    /// Unable to test network connectivity to the host
    case couldNotTestConnectivity
    
    /// The mount options provided are invalid
    case invalidMountOptions
    
    /// The share is already mounted at the requested location
    case alreadyMounted
    
    /// The share mount operation has been queued but not yet executed
    case mountIsQueued
    
    /// The target host cannot be reached over the network
    case targetNotReachable
    
    /// An unspecified error occurred during the operation
    case otherError
    
    /// No network route exists to the specified host
    case noRouteToHost
    
    /// The resource does not exist
    case doesNotExist
    
    /// The share does not exist on the remote server
    case shareDoesNotExist
    
    /// The operation returned an unknown or unexpected return code
    case unknownReturnCode
    
    /// The provided mount path is invalid
    case invalidMountPath
    
    /// The unmount operation failed
    case unmountFailed
    
    /// Connection to host timed out
    case timedOutHost
    
    /// Authentication credentials are invalid or missing
    case authenticationError
    
    /// The host server is not responding
    case hostIsDown
    
    /// The share was unmounted by user action
    case userUnmounted
    
    /// No error occurred (success state)
    case noError
    
    /// Kerberos authentication failed
    case krbAuthenticationError
    
    /// The device is outside the Kerberos domain
    case offDomain
    
    /// Kerberos authentication completed successfully
    case krbAuthSuccessful
    
    /// Access to the share was denied due to permissions
    case permissionDenied
    
    /// An existing directory is blocking the mount point
    case obstructingDirectory
}

extension MounterError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .errorCreatingMountFolder:
            return NSLocalizedString(
                "Error creating mount directory",
                comment: "Error creating mount directory"
            )
        case .errorCheckingMountDir:
            return NSLocalizedString(
                "Error creating mount directory",
                comment: "Error creating mount directory"
            )
        case .errorOnEncodingShareURL:
            return NSLocalizedString(
                "Cannot encode server URL",
                comment: "Cannot encode server URL"
            )
        case .invalidMountURL:
            return NSLocalizedString(
                "The path to the network share is invalid",
                comment: "The path to the network share is invalid"
            )
        case .invalidHost:
            return NSLocalizedString(
                "Hostname is invalid",
                comment: "Hostname is invalid"
            )
        case .mountpointInaccessible:
            return NSLocalizedString(
                "Mountpoint is inacessible",
                comment: "Mountpoint is inacessible"
            )
        case .couldNotTestConnectivity:
            return NSLocalizedString(
                "Network connectivity cannot be tested",
                comment: "Network connectivity cannot be tested"
            )
        case .invalidMountOptions:
            return NSLocalizedString(
                "Invalid mount options",
                comment: "Invalid mount options"
            )
        case .alreadyMounted:
            return NSLocalizedString(
                "Share is already mounted",
                comment: "Share is already mounted"
            )
        case .mountIsQueued:
            return NSLocalizedString(
                "Mount queued",
                comment: "Mount queued"
            )
        case .targetNotReachable:
            return NSLocalizedString(
                "Target host is not reachable",
                comment: "Target host is not reachable"
            )
        case .otherError:
            return NSLocalizedString(
                "Other error",
                comment: "Other error"
            )
        case .noRouteToHost:
            return NSLocalizedString(
                "Hostname error or no route to host",
                comment: "Hostname error or no route to host"
            )
        case .doesNotExist:
            return NSLocalizedString(
                "Does not exist",
                comment: "Does not exist"
            )
        case .shareDoesNotExist:
            return NSLocalizedString(
                "Share does not exist",
                comment: "Share does not exist"
            )
        case .unknownReturnCode:
            return NSLocalizedString(
                "Unknown return code, sorry",
                comment: "Unknown return code, sorry"
            )
        case .invalidMountPath:
            return NSLocalizedString(
                "Invalid mount path",
                comment: "Invalid mount path"
            )
        case .unmountFailed:
            return NSLocalizedString(
                "Cannot unmount share",
                comment: "Cannot unmount share"
            )
        case .timedOutHost:
            return NSLocalizedString(
                "Timeout on reaching host",
                comment: "Timeout on reaching host"
            )
        case .authenticationError:
            return NSLocalizedString(
                "Authentication error",
                comment: "Authentication error"
            )
        case .hostIsDown:
            return NSLocalizedString(
                "Host is down",
                comment: "Host is down"
            )
        case .userUnmounted:
            return NSLocalizedString(
                "User-mounted share",
                comment: "CoUser-mounted sharemment"
            )
        case .noError:
            return NSLocalizedString(
                "no error occured",
                comment: "no error occured"
            )
        case .krbAuthenticationError:
            return NSLocalizedString(
                "Kerberos authentication error",
                comment: "Kerberos authentication error"
            )
        case .offDomain:
            return NSLocalizedString(
                "outside kerberos domain",
                comment: "outside kerberos domain"
            )
        case .krbAuthSuccessful:
            return NSLocalizedString(
                "Kerberos authentication successful",
                comment: "Kerberos authentication successful"
            )
        case .permissionDenied:
            return NSLocalizedString(
                "Permission denied",
                comment: "Permission denied"
            )
        case .obstructingDirectory:
            return NSLocalizedString(
                "Can nout mount share because of obstructing directory",
                comment: "Can nout mount share because of obstructing directory"
            )
        }
    }
}

