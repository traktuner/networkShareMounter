//
//  DSQueryable.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 15.12.23.
//  Copyright © 2019 Jamf. All rights reserved.
//  Copyright © 2023 RRZE. All rights reserved.
//

import OpenDirectory
import os
import OSLog

enum DSQueryableErrors: Error {
    case notLocalUser
    case multipleUsersFound
    case odFailure
}

/// The `DSQueryable` protocol allows adopters to easily search  the DSLocal node of macOS.
public protocol DSQueryable {}

// MARK: - Implimentations for DSQuerable protocol
public extension DSQueryable {
    
    /// `ODNode` to DSLocal for queries and account manipulation.
    var localNode: ODNode? {
        do {
            Logger.networkQueries.info("Finding the OpenDirectory DSLocal node.")
            return try ODNode.init(session: ODSession.default(), type: ODNodeType(kODNodeTypeLocalNodes))
        } catch {
            Logger.networkQueries.info("ODError creating local node.")
            return nil
        }
    }

    /// Conviennce function to discover if a shortname has an existing local account.
    ///
    /// - Parameter shortName: The name of the user to search for as a `String`.
    /// - Returns: `true` if the user exists in DSLocal, `false` if not.
    /// - Throws: Either an `ODFrameworkErrors` or a `DSQueryableErrors` if there is an error.
    func isUserLocal(_ shortName: String) throws -> Bool {
        do {
            _ = try getLocalRecord(shortName)
        } catch DSQueryableErrors.notLocalUser {
            return false
        } catch {
            throw error
        }
        return true
    }

    // Disabling line length warning for this method as it has a really long constant in it.
    // swiftlint:disable line_length

    /// Determine if a given shortname has an existing mobile account.
    /// - Parameter shortName: The name of the user to search for as a `String`.
    /// - Throws: Either an `ODFrameworkErrors` or a `DSQueryableErrors` if there is an error.
    /// - Returns: `true` if the user record is a mobile account, `false` if not.
    func isUserMobile(_ shortName: String) throws -> Bool {
        do {
            let userRecord = try getLocalRecord(shortName)
            if let authAuthorities = try userRecord.values(forAttribute: kODAttributeTypeAuthenticationAuthority) as? [String] {
                if authAuthorities.contains(";LocalCachedUser;") {
                    Logger.networkQueries.info("User is a mobile account.")
                    return true
                }
                Logger.networkQueries.info("User is not a mobile account.")
                return false
            }
            Logger.networkQueries.error("Something went wrong checking for a mobile account.")
            throw DSQueryableErrors.odFailure
        } catch {
            throw error
        }
    }
    // swiftlint:enable line_length

    /// Checks a local username and password to see if they are valid.
    ///
    /// - Parameters:
    ///   - userName: The name of the user to search for as a `String`.
    ///   - userPass: The password for the user being tested as a `String`.
    /// - Returns: `true` if the name and password combo are valid locally. `false` if the validation fails.
    /// - Throws: Either an `ODFrameworkErrors` or a `DSQueryableErrors` if there is an error.
    func isLocalPasswordValid(userName: String, userPass: String) throws -> Bool {
        do {
            let userRecord = try getLocalRecord(userName)
            try userRecord.verifyPassword(userPass)
        } catch {
            let castError = error as NSError
            switch castError.code {
            case Int(kODErrorCredentialsInvalid.rawValue):
                Logger.networkQueries.error("Tested password for user account: \(userName, privacy: .public) is not valid.")
                return false
            default:
                throw error
            }
        }
        return true
    }

    /// Searches DSLocal for an account short name and returns the `ODRecord` for the user if found.
    ///
    /// - Parameter shortName: The name of the user to search for as a `String`.
    /// - Returns: The `ODRecord` of the user if one is found in DSLocal.
    /// - Throws: Either an `ODFrameworkErrors` or a `DSQueryableErrors` if there is an error or the user is not local.
    func getLocalRecord(_ shortName: String) throws -> ODRecord {
        do {
            Logger.networkQueries.debug("Building OD query for name: \(shortName, privacy: .public)...")
            let query = try ODQuery.init(node: localNode,
                                         forRecordTypes: kODRecordTypeUsers,
                                         attribute: kODAttributeTypeRecordName,
                                         matchType: ODMatchType(kODMatchEqualTo),
                                         queryValues: shortName,
                                         returnAttributes: kODAttributeTypeNativeOnly,
                                         maximumResults: 0)
            guard let records = try query.resultsAllowingPartial(false) as? [ODRecord] else {
                throw DSQueryableErrors.odFailure
            }

            if records.count > 1 {
                Logger.networkQueries.error("More than one local user found for name \(shortName, privacy: .public).")
                throw DSQueryableErrors.multipleUsersFound
            }
            guard let record = records.first else {
                Logger.networkQueries.info("No local user found.")
                throw DSQueryableErrors.notLocalUser
            }
            Logger.networkQueries.info("Found local user.")
            return record
        } catch {
            Logger.networkQueries.error("Local OpenDirectory Error while trying to check for local user: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Validate  password
    ///
    /// - Parameters:
    ///   - pass: The password of the user to check as a `String`.
    /// - Returns: `true` if upass is valid, false if not.
    func validatePasswordPolicy(_ pass: String) -> Bool {
        do {
            try localNode?.passwordContentCheck(pass, forRecordName: "")
            return true
        } catch {
            Logger.networkQueries.error("Local OpenDirectory Error while trying to validate user: \(error.localizedDescription, privacy: .public)")
        }
        return false
    }

    /// Finds all local user records on the Mac.
    ///
    /// - Returns: A `Array` that contains the `ODRecord` for every account in DSLocal.
    /// - Throws: An error from `ODFrameworkErrors` if something fails.
    func getAllLocalUserRecords() throws -> [ODRecord] {
        do {
            let query = try ODQuery.init(node: localNode,
                                         forRecordTypes: kODRecordTypeUsers,
                                         attribute: kODAttributeTypeRecordName,
                                         matchType: ODMatchType(kODMatchEqualTo),
                                         queryValues: kODMatchAny,
                                         returnAttributes: kODAttributeTypeAllAttributes,
                                         maximumResults: 0)
            guard let results = try query.resultsAllowingPartial(false) as? [ODRecord] else {
                throw DSQueryableErrors.odFailure
            }
            return results
        } catch {
            Logger.networkQueries.error("Local OpenDirectory Error while trying to check for local user: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Returns all the non-system users on a system above UID 500.
    ///
    /// - Returns: A `Array` that contains the `ODRecord` of all the non-system user accounts in DSLocal.
    /// - Throws: An error from `ODFrameworkErrors` if something fails.
    func getAllNonSystemUsers() throws -> [ODRecord] {
        do {
            let allRecords = try getAllLocalUserRecords()
            let nonSystem = try allRecords.filter { (record) -> Bool in
                guard let uid = try record.values(forAttribute: kODAttributeTypeUniqueID) as? [String] else {
                    return false
                }
                return Int(uid.first ?? "") ?? 0 > 500 && record.recordName.first != "_"
            }
            return nonSystem
        } catch {
            Logger.networkQueries.error("Local OpenDirectory Error while trying to check for local user: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    /// Returns User avatar path if exists.
    /// - Parameter userName: Usernam as in User Record.
    /// - Returns: absolute path to avatar image.
    func getUserAvatar(userName: String) -> String? {
        do {
            let userRecord: ODRecord = try getLocalRecord(userName)
            let avatarPaths = try userRecord.values(forAttribute: kODAttributeTypePicture)
            if let imagePath = avatarPaths.first as? String {
                Logger.networkQueries.info("Found avatar for user: \(userName, privacy: .public)")
                return imagePath
            }
            Logger.networkQueries.info("Could not find avatar for user: \(userName, privacy: .public)")
            return nil
        } catch {
            Logger.networkQueries.info("Local OpenDirectory Error while trying to check for local user: \(error.localizedDescription, privacy: .public)")
        }
        return nil
    }
}

