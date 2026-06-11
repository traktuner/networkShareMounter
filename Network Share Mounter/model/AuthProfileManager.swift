import Foundation
import Combine
import OSLog
import SwiftUI

// MARK: - AuthProfileError

enum AuthProfileError: LocalizedError {
    case duplicateProfileID
    case profileNotFound
    case validationFailed([String])
    case realmConflict(existingProfile: AuthProfile, newProfile: AuthProfile)

    var errorDescription: String? {
        switch self {
        case .duplicateProfileID:
            return "A profile with this ID already exists"
        case .profileNotFound:
            return "Profile not found"
        case .validationFailed(let errors):
            return "Profile validation failed: \(errors.joined(separator: ", "))"
        case .realmConflict(let existing, let new):
            return "Realm conflict: \(existing.displayName) conflicts with \(new.displayName)"
        }
    }
}

// MARK: - CredentialOnboardingInfo

/// Describes the credential gaps detected at app startup.
/// Passed from `AuthProfileManager` to the onboarding UI.
struct CredentialOnboardingInfo {
    /// MDM Kerberos realm that has no configured profile with a username. `nil` if no Kerberos gap.
    let kerberosRealm: String?
    /// Pre-filled username suggestion (from Jamf Connect or local Mac account name).
    let suggestedUsername: String
    /// MDM password shares that have no assigned AuthProfile.
    let unassignedPasswordShares: [Share]

    var needsOnboarding: Bool { kerberosRealm != nil || !unassignedPasswordShares.isEmpty }
}

// MARK: - AuthProfileManager

/// Manages the collection of authentication profiles.
/// Handles loading/saving profile metadata (to UserDefaults) and coordinates password storage (via KeychainManager).
@MainActor
class AuthProfileManager: ObservableObject {
    /// Shared singleton instance.
    static let shared = AuthProfileManager()

    /// The key used to store profile metadata in UserDefaults.
//    private let userDefaultsKey = "com.example.NetworkShareMounter.AuthProfiles"

    /// The published array of authentication profiles. Views can subscribe to this.
    @Published var profiles: [AuthProfile] = []

    /// Access to the Keychain manager.
    private let keychainManager = KeychainManager()

    private init() {
        loadProfiles()
        Logger.dataModel.info("AuthProfileManager initialized. Loaded \(self.profiles.count, privacy: .public) profiles.")
    }

    // --- Profile Management ---

    /// Adds a new profile and optionally saves its password to the Keychain.
    /// - Parameters:
    ///   - profile: The `AuthProfile` object to add (ID should be set).
    ///   - password: The password associated with the profile, if any.
    func addProfile(_ profile: AuthProfile, password: String?) async throws {
        guard !profiles.contains(where: { $0.id == profile.id }) else {
            Logger.dataModel.warning("Attempted to add profile with duplicate ID: \(profile.id, privacy: .public)")
            throw AuthProfileError.duplicateProfileID
        }

        // Validate profile
        let validation = await validateProfile(profile)
        if !validation.isValid {
            // Check if it's a realm conflict (needs UI confirmation)
            if let conflictingProfile = validation.realmConflict {
                Logger.dataModel.warning("⚠️ Realm conflict detected for '\(profile.displayName, privacy: .public)' with existing profile '\(conflictingProfile.displayName)'")
                throw AuthProfileError.realmConflict(existingProfile: conflictingProfile, newProfile: profile)
            }

            // Regular validation errors
            if !validation.errors.isEmpty {
                Logger.dataModel.error("❌ Profile validation failed for '\(profile.displayName, privacy: .public)': \(validation.errors.joined(separator: ", "))")
                throw AuthProfileError.validationFailed(validation.errors)
            }
        }

        // Add profile metadata
        profiles.append(profile)
        saveProfiles() // Save metadata changes

        // Save password if provided
        if let pwd = password, !pwd.isEmpty {
            try await savePassword(for: profile, password: pwd)
        }
        Logger.dataModel.info("Added profile '\(profile.displayName, privacy: .public)' (ID: \(profile.id, privacy: .public))")
    }

    /// Updates an existing profile's metadata. Does not modify the password.
    /// - Parameter profile: The `AuthProfile` with updated metadata.
    func updateProfile(_ profile: AuthProfile) async throws {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            Logger.dataModel.warning("Attempted to update non-existent profile ID: \(profile.id, privacy: .public)")
            throw AuthProfileError.profileNotFound
        }

        // Validate profile
        let validation = await validateProfile(profile)
        if !validation.isValid {
            // Check if it's a realm conflict (needs UI confirmation)
            if let conflictingProfile = validation.realmConflict {
                Logger.dataModel.warning("⚠️ Realm conflict detected for '\(profile.displayName, privacy: .public)' with existing profile '\(conflictingProfile.displayName)'")
                throw AuthProfileError.realmConflict(existingProfile: conflictingProfile, newProfile: profile)
            }

            // Regular validation errors
            if !validation.errors.isEmpty {
                Logger.dataModel.error("❌ Profile validation failed for '\(profile.displayName, privacy: .public)': \(validation.errors.joined(separator: ", "))")
                throw AuthProfileError.validationFailed(validation.errors)
            }
        }

        profiles[index] = profile
        saveProfiles() // Save metadata changes
        Logger.dataModel.info("Updated profile '\(profile.displayName, privacy: .public)' (ID: \(profile.id, privacy: .public))")
    }

    /// Replaces an existing Kerberos profile with a new one for the same realm.
    /// This method handles the case where a user confirms they want to replace an existing profile.
    /// - Parameters:
    ///   - newProfile: The new profile to add
    ///   - existingProfile: The existing profile to replace
    ///   - password: Optional password for the new profile
    func replaceKerberosProfile(_ newProfile: AuthProfile, replacing existingProfile: AuthProfile, password: String?) async throws {
        guard newProfile.useKerberos && existingProfile.useKerberos else {
            Logger.dataModel.error("❌ replaceKerberosProfile called with non-Kerberos profiles")
            throw AuthProfileError.validationFailed(["Both profiles must be Kerberos profiles"])
        }

        Logger.dataModel.info("🔄 Replacing Kerberos profile '\(existingProfile.displayName)' with '\(newProfile.displayName)'")

        // Remove the existing profile (including keychain entries)
        try await removeProfile(existingProfile)

        // Add the new profile (bypassing realm conflict check since we explicitly want to replace)
        guard !profiles.contains(where: { $0.id == newProfile.id }) else {
            throw AuthProfileError.duplicateProfileID
        }

        // Basic validation only (skip realm conflict check)
        if newProfile.useKerberos && !newProfile.isValidKerberosProfile {
            throw AuthProfileError.validationFailed(["The username must be entered in the format username@domain.de."])
        }

        // Add the new profile
        profiles.append(newProfile)
        saveProfiles()

        // Save password if provided
        if let pwd = password, !pwd.isEmpty {
            try await savePassword(for: newProfile, password: pwd)
        }

        Logger.dataModel.info("✅ Successfully replaced Kerberos profile. New profile ID: \(newProfile.id, privacy: .public)")
    }

    /// Removes a profile and its associated password from the Keychain.
    /// - Parameter profile: The `AuthProfile` to remove.
    func removeProfile(_ profile: AuthProfile) async throws {
        profiles.removeAll { $0.id == profile.id }
        saveProfiles() // Save metadata changes

        // Remove password from Keychain
        try await removePassword(for: profile)
        Logger.dataModel.info("Removed profile '\(profile.displayName, privacy: .public)' (ID: \(profile.id, privacy: .public))")
    }

    /// Retrieves a profile by its unique ID.
    /// - Parameter id: The ID of the profile to retrieve.
    /// - Returns: The `AuthProfile` if found, otherwise `nil`.
    func getProfile(by id: String) -> AuthProfile? {
        return profiles.first { $0.id == id }
    }

    /// Finds the first profile that lists the given network share URL in its `associatedNetworkShares`.
    /// - Parameter networkShare: The network share URL string to search for.
    /// - Returns: The matching `AuthProfile` if found, otherwise `nil`.
    func findProfile(for networkShare: String) -> AuthProfile? {
        // Iterate through profiles and check if the networkShare is in their associated list
        return profiles.first { profile in
            profile.associatedNetworkShares?.contains(networkShare) ?? false
        }
    }

    /// Removes a share URL from all profiles that reference it in `associatedNetworkShares`.
    /// Call this whenever a share is deleted so no profile retains a stale reference.
    /// - Parameter shareURL: The network share URL string to remove.
    func removeShareFromAllProfiles(shareURL: String) async {
        for profile in profiles {
            guard var shares = profile.associatedNetworkShares,
                  shares.contains(shareURL) else { continue }
            shares.removeAll { $0 == shareURL }
            var updatedProfile = profile
            updatedProfile.associatedNetworkShares = shares.isEmpty ? nil : shares
            do {
                try await updateProfile(updatedProfile)
                Logger.dataModel.info("🗑️ Removed stale share '\(shareURL, privacy: .public)' from profile '\(profile.displayName, privacy: .public)'")
            } catch {
                Logger.dataModel.error("❌ Failed to remove stale share from profile '\(profile.displayName, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Auto-Assignment

    /// Automatically assigns a Kerberos profile to a share based on realm and username matching.
    /// Uses intelligent prioritization when multiple profiles match the realm.
    /// - Parameters:
    ///   - shareURL: The network share URL to assign a profile to
    ///   - username: Optional username from the share configuration
    ///   - kerberosRealm: The Kerberos realm to match against
    /// - Returns: The profile ID if a match was found, nil otherwise
    func autoAssignKerberosProfile(shareURL: String, username: String?, kerberosRealm: String) -> String? {
        Logger.dataModel.debug("🔍 Auto-assigning Kerberos profile for share: \(shareURL, privacy: .public), realm: \(kerberosRealm, privacy: .public)")

        // Find all Kerberos profiles matching the realm
        let candidateProfiles = profiles.filter { profile in
            profile.useKerberos &&
            profile.kerberosRealm?.uppercased() == kerberosRealm.uppercased()
        }

        // No matching profiles found
        guard !candidateProfiles.isEmpty else {
            Logger.dataModel.warning("⚠️ No Kerberos profile found for realm: \(kerberosRealm, privacy: .public), share: \(shareURL, privacy: .public)")
            return nil
        }

        // Exactly one match - use it
        if candidateProfiles.count == 1 {
            let profile = candidateProfiles[0]
            Logger.dataModel.info("✅ Auto-assigned Kerberos profile '\(profile.displayName, privacy: .public)' to share: \(shareURL, privacy: .public)")
            return profile.id
        }

        // Multiple matches - use prioritization logic
        Logger.dataModel.debug("🔍 Found \(candidateProfiles.count) Kerberos profiles for realm \(kerberosRealm, privacy: .public), applying prioritization")

        // Priority 1: Username match (if share has username)
        if let username = username {
            if let usernameMatch = candidateProfiles.first(where: {
                $0.username?.lowercased() == username.lowercased()
            }) {
                Logger.dataModel.info("✅ Auto-assigned Kerberos profile '\(usernameMatch.displayName, privacy: .public)' (username match) to share: \(shareURL, privacy: .public)")
                return usernameMatch.id
            }
        }

        // Priority 2: Profile with most associated shares (likely the "main" profile)
        if let mainProfile = candidateProfiles.max(by: {
            ($0.associatedNetworkShares?.count ?? 0) < ($1.associatedNetworkShares?.count ?? 0)
        }) {
            Logger.dataModel.info("✅ Auto-assigned Kerberos profile '\(mainProfile.displayName, privacy: .public)' (most shares) to share: \(shareURL, privacy: .public)")
            return mainProfile.id
        }

        // Fallback: First profile (shouldn't happen but safe)
        let fallbackProfile = candidateProfiles[0]
        Logger.dataModel.info("✅ Auto-assigned Kerberos profile '\(fallbackProfile.displayName, privacy: .public)' (fallback) to share: \(shareURL, privacy: .public)")
        return fallbackProfile.id
    }

    /// Automatically assigns a password profile to a share based on username matching.
    /// Supports matching against both password profiles and Kerberos profiles with UPN usernames.
    /// - Parameters:
    ///   - shareURL: The network share URL to assign a profile to
    ///   - username: The username from the share configuration
    /// - Returns: The profile ID if exactly one match was found, nil if zero or multiple matches (ambiguous)
    func autoAssignPasswordProfile(shareURL: String, username: String) -> String? {
        Logger.dataModel.debug("🔍 Auto-assigning password profile for share: \(shareURL), username: \(username)")

        // Extract local part of username (before @ for UPN format)
        let shareUsernameLocal = username.split(separator: "@").first.map(String.init) ?? username

        // Find all profiles (Password AND Kerberos) where username matches
        let candidateProfiles = profiles.filter { profile in
            guard let profileUsername = profile.username else { return false }

            // Extract local part from profile username (handles UPN like "user@DOMAIN.DE")
            let profileUsernameLocal = profileUsername.split(separator: "@").first.map(String.init) ?? profileUsername

            return profileUsernameLocal.lowercased() == shareUsernameLocal.lowercased()
        }

        // No matching profiles found
        guard !candidateProfiles.isEmpty else {
            Logger.dataModel.warning("⚠️ No profile found for username: \(username, privacy: .public), share: \(shareURL, privacy: .public)")
            return nil
        }

        // Exactly one match - auto-assign
        if candidateProfiles.count == 1 {
            let profile = candidateProfiles[0]
            Logger.dataModel.info("✅ Auto-assigned profile '\(profile.displayName, privacy: .public)' to password share: \(shareURL, privacy: .public)")
            return profile.id
        }

        // Multiple matches - ambiguous, requires user decision
        Logger.dataModel.warning("⚠️ Found \(candidateProfiles.count) profiles for username '\(username, privacy: .public)' - ambiguous, requires user selection")
        Logger.dataModel.debug("   Candidates: \(candidateProfiles.map { $0.displayName }.joined(separator: ", "))")
        return nil
    }

    // --- Password Management Coordination ---

    /// Saves or updates the password for a given profile in the Keychain.
    /// - Parameters:
    ///   - profile: The profile whose password needs to be saved.
    ///   - password: The password string to save.
    func savePassword(for profile: AuthProfile, password: String) async throws {
        guard !password.isEmpty else {
            // If password is empty, consider removing it instead? Or do nothing?
            // For now, we'll remove it if an empty password is explicitly saved.
            Logger.dataModel.info("Password for profile '\(profile.displayName, privacy: .public)' is empty. Removing from keychain.")
            try await removePassword(for: profile)
            return
        }
        do {
            // Use profile ID as the 'account' in the Keychain query
            try keychainManager.saveCredential(forUsername: profile.id, andPassword: password, withService: keychainServiceForProfiles)
            Logger.dataModel.debug("Saved password to keychain for profile ID: \(profile.id, privacy: .public)")
        } catch {
            Logger.dataModel.error("Failed to save password to keychain for profile ID \(profile.id, privacy: .public): \(error.localizedDescription)")
            throw error // Re-throw the error
        }
    }

    /// Retrieves the password for a given profile from the Keychain.
    /// - Parameter profile: The profile whose password should be retrieved.
    /// - Returns: The password string if found, otherwise `nil`.
    func retrievePassword(for profile: AuthProfile) async throws -> String? {
        do {
            let password = try keychainManager.retrievePassword(forUsername: profile.id, andService: keychainServiceForProfiles)
            Logger.dataModel.debug("Retrieved password from keychain for profile ID: \(profile.id, privacy: .public) - \(password == nil ? "Not Found" : "Found", privacy: .public)")
            return password
        } catch KeychainError.itemNotFound {
            Logger.dataModel.info("Password not found in keychain for profile ID \(profile.id, privacy: .public)")
             return nil // Return nil specifically for itemNotFound
         } catch {
             Logger.dataModel.error("Failed to retrieve password from keychain for profile ID \(profile.id, privacy: .public): \(error.localizedDescription)")
            throw error // Re-throw other errors
        }
    }

    /// Removes the password for a given profile from the Keychain.
    /// - Parameter profile: The profile whose password should be removed.
    func removePassword(for profile: AuthProfile) async throws {
        do {
            try keychainManager.removeCredential(forUsername: profile.id, andService: keychainServiceForProfiles)
            Logger.dataModel.debug("Removed password from keychain for profile ID: \(profile.id, privacy: .public)")
        } catch KeychainError.itemNotFound {
             Logger.dataModel.info("Attempted to remove password for profile ID \(profile.id, privacy: .public), but it was not found in keychain.")
             // Ignore itemNotFound, as the goal is achieved (password is gone)
         } catch {
            Logger.dataModel.error("Failed to remove password from keychain for profile ID \(profile.id, privacy: .public): \(error.localizedDescription)")
            throw error // Re-throw other errors
        }
    }

    // --- Persistence ---

    /// Loads profiles from UserDefaults.
    private func loadProfiles() {
        guard let data = UserDefaults.standard.data(forKey: Defaults.authProfileKey) else {
            Logger.dataModel.info("No profile data found in UserDefaults.")
            self.profiles = [] // Start with empty array if no data
            return
        }

        do {
            let decoder = JSONDecoder()
            self.profiles = try decoder.decode([AuthProfile].self, from: data)
            Logger.dataModel.info("Successfully loaded \(self.profiles.count, privacy: .public) profiles from UserDefaults.")
        } catch {
            Logger.dataModel.error("Failed to decode profiles from UserDefaults: \(error.localizedDescription)")
            self.profiles = [] // Reset to empty on error
        }
    }

    /// Saves the current profiles array to UserDefaults.
    private func saveProfiles() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(profiles)
            UserDefaults.standard.set(data, forKey: Defaults.authProfileKey)
            Logger.dataModel.debug("Successfully saved \(self.profiles.count, privacy: .public) profiles to UserDefaults.")
        } catch {
            Logger.dataModel.error("Failed to encode profiles for UserDefaults: \(error.localizedDescription)")
        }
    }

    // --- Keychain Configuration ---

    /// Defines the service identifier used for storing profile passwords in the Keychain.
    private var keychainServiceForProfiles: String {
        // Using the bundle identifier makes it unique to this application.
        return Bundle.main.bundleIdentifier ?? "com.example.NetworkShareMounter.AuthProfilePasswords"
    }

    // MARK: - Hybrid Migration

    /// Performs a hybrid migration from legacy share-based credentials to profiles
    /// Reads shares directly from UserDefaults/MDM configuration to avoid timing issues
    /// This approach ensures we have all share data before starting migration
    func migrateFromLegacyCredentials() async throws {
        Logger.dataModel.info("🔄 Starting hybrid credential migration (direct config approach)")

        // Store original profiles for rollback in case of failure
        let originalProfiles = profiles

        do {
            // Get shares directly from UserDefaults/MDM configuration (not ShareManager)
            let shareConfigs = getAllShareConfigurations()
            Logger.dataModel.info("Found \(shareConfigs.count, privacy: .public) share configurations to analyze")

        // Get FAU shared credentials for additional Kerberos profile creation
        let fauCredentials = try keychainManager.retrieveAllFAUSharedCredentials()
        Logger.dataModel.info("Found \(fauCredentials.count, privacy: .public) FAU shared credentials")

        // Process each share individually based on AuthType and found keychain entries
        var kerberosProfiles: [String: KerberosProfileData] = [:]
        var passwordProfiles: [String: PasswordProfileData] = [:]

        // Process each share configuration (only those with explicit usernames)
        for shareConfig in shareConfigs {
            guard let username = shareConfig.username else {
                Logger.dataModel.debug("Skipping share without username: \(shareConfig.shareURL, privacy: .public)")
                continue
            }

            let groupKey = username.lowercased()

            // Try to get password and determine keychain type for this specific share
            guard let credentialInfo = getPasswordForShareConfig(shareConfig) else {
                Logger.dataModel.warning("⚠️ No password found for share: \(shareConfig.shareURL, privacy: .public)")
                continue
            }

            // Determine profile type based on ACTUAL keychain entry type (not just AuthType)
            switch credentialInfo.keychainType {
            case KeychainEntryType.kerberosUPN, KeychainEntryType.fauShared:
                // Found UPN or FAU shared entry -> Kerberos profile (keep existing keychain)
                if var existing = kerberosProfiles[groupKey] {
                    existing.shares.append(shareConfig.shareURL)
                    kerberosProfiles[groupKey] = existing
                } else {
                    let kerberosCheck = await checkIfKerberosUser(username: username)
                    let fallbackRealm = getMDMKerberosRealm() ?? "FAUAD.FAU.DE"
                    kerberosProfiles[groupKey] = KerberosProfileData(
                        username: username,
                        shares: [shareConfig.shareURL],
                        kerberosRealm: kerberosCheck.realm ?? fallbackRealm,
                        keychainType: credentialInfo.keychainType
                    )
                    Logger.dataModel.debug("✅ Kerberos profile: \(username, privacy: .public) (keychain: \(String(describing: credentialInfo.keychainType)))")
                }

            case KeychainEntryType.shareBased:
                // Found share-based entry -> Password profile (migrate keychain)
                if var existing = passwordProfiles[groupKey] {
                    existing.shares.append(shareConfig.shareURL)
                    passwordProfiles[groupKey] = existing
                } else {
                    passwordProfiles[groupKey] = PasswordProfileData(
                        username: username,
                        password: credentialInfo.password,
                        shares: [shareConfig.shareURL]
                    )
                    Logger.dataModel.debug("✅ Password profile: \(username, privacy: .public) (share-based keychain)")
                }
            }
        }

        // Also check FAU shared credentials for additional Kerberos profiles (users without shares)
        for fauCredential in fauCredentials {
            let groupKey = fauCredential.username.lowercased()

            // Skip if we already have this user from shares
            if kerberosProfiles[groupKey] != nil {
                continue
            }

            // Check if this is a Kerberos user
            let isKerberos = await checkIfKerberosUser(username: fauCredential.username)

            if isKerberos.isKerberos {
                let fallbackRealm = getMDMKerberosRealm() ?? "FAUAD.FAU.DE"
                kerberosProfiles[groupKey] = KerberosProfileData(
                        username: fauCredential.username,
                        shares: [], // No shares associated yet
                        kerberosRealm: isKerberos.realm ?? fallbackRealm,
                        keychainType: KeychainEntryType.fauShared
                    )
                Logger.dataModel.debug("✅ Added FAU Kerberos user: \(fauCredential.username, privacy: .public)")
            }
        }

        Logger.dataModel.info("Created \(kerberosProfiles.count, privacy: .public) Kerberos profiles and \(passwordProfiles.count, privacy: .public) password profiles")

        // Create Kerberos profiles (reference existing keychain entries - DON'T migrate)
        for (_, profileData) in kerberosProfiles {
            let profileId = UUID().uuidString

            let profile = AuthProfile(
                id: profileId,
                displayName: profileData.username,
                username: profileData.username,
                useKerberos: true,
                kerberosRealm: profileData.kerberosRealm,
                associatedNetworkShares: profileData.shares,
                symbolName: "ticket"
            )

            profiles.append(profile)
            Logger.dataModel.info("✅ Created Kerberos profile for \(profileData.username, privacy: .public) (references existing \(String(describing: profileData.keychainType)) keychain)")
        }

        // Create and migrate password profiles (migrate keychain entries)
        for (_, profileData) in passwordProfiles {
            let profileId = UUID().uuidString

            let profile = AuthProfile(
                id: profileId,
                displayName: profileData.username,
                username: profileData.username,
                useKerberos: false,
                kerberosRealm: nil,
                associatedNetworkShares: profileData.shares,
                symbolName: "person"
            )

            // Migrate password to new profile-based keychain structure
            do {
                try keychainManager.saveCredential(
                    forUsername: profileId,
                    andPassword: profileData.password,
                    withService: keychainServiceForProfiles
                )

                profiles.append(profile)
                Logger.dataModel.info("✅ Migrated password profile for \(profileData.username, privacy: .public)")

                // TODO: Remove old share-based entries after successful migration
                // This should be done carefully to avoid data loss
                // for shareURL in profileData.shares {
                //     if let url = URL(string: shareURL) {
                //         try? keychainManager.removeCredential(forShare: url, withUsername: profileData.username)
                //     }
                // }

            } catch {
                Logger.dataModel.error("❌ Failed to migrate password for \(profileData.username, privacy: .public): \(error)")
                // Continue with other profiles instead of failing entire migration
                continue
            }
        }

        Logger.dataModel.info("Created \(kerberosProfiles.count, privacy: .public) Kerberos profiles and \(passwordProfiles.count) password profiles")

        // Save all profiles to UserDefaults
        saveProfiles()

        // Update existing user shares to link with newly created profiles
        await updateExistingSharesWithProfiles()

            Logger.dataModel.info("✅ Hybrid migration completed: \(kerberosProfiles.count, privacy: .public) Kerberos profiles, \(passwordProfiles.count, privacy: .public) password profiles")

        } catch {
            Logger.dataModel.error("❌ Migration failed: \(error.localizedDescription)")

            // Rollback: restore original profiles
            profiles = originalProfiles
            saveProfiles()

            Logger.dataModel.warning("⚠️ Rolled back to original profiles due to migration failure")
            throw error
        }
    }

    // MARK: - Share Configuration Reading

    /// Share configuration structure for migration
    private struct ShareConfiguration {
        let shareURL: String
        let username: String?
        let authType: String
    }

    /// Kerberos profile data for migration
    private struct KerberosProfileData {
        let username: String
        var shares: [String]
        let kerberosRealm: String
        let keychainType: KeychainEntryType
    }

    /// Password profile data for migration
    private struct PasswordProfileData {
        let username: String
        let password: String
        var shares: [String]
    }

    /// Gets all share configurations directly from UserDefaults/MDM (bypasses ShareManager timing issues)
    private func getAllShareConfigurations() -> [ShareConfiguration] {
        var configurations: [ShareConfiguration] = []
        let userDefaults = UserDefaults.standard
        let prefs = PreferenceManager()

        // 1. Process MDM shares (new format)
        if let sharesDict = userDefaults.array(forKey: Defaults.managedNetworkSharesKey) as? [[String: String]], !sharesDict.isEmpty {
            Logger.dataModel.debug("Processing \(sharesDict.count) MDM shares (new format)")

            for shareElement in sharesDict {
                guard let shareUrlString = shareElement[Defaults.networkShare] else { continue }

                // Determine username (same logic as ShareManager)
                let userName: String?
                if let username = prefs.string(for: .usernameOverride) {
                    userName = username
                } else if let username = shareElement[Defaults.username] {
                    userName = username
                } else {
                    userName = NSUserName()
                }

                // Keep raw URL — %USERNAME% resolved at mount/display time via Share.resolvedNetworkShare(username:)
                let shareRectified = shareUrlString
                let authType = shareElement[Defaults.authType] ?? AuthType.krb.rawValue

                configurations.append(ShareConfiguration(
                    shareURL: shareRectified,
                    username: userName,
                    authType: authType
                ))
            }
        }
        // 2. Process legacy MDM shares if no new format found
        else if let nwShares = userDefaults.array(forKey: Defaults.networkSharesKey) as? [String], !nwShares.isEmpty {
            Logger.dataModel.debug("Processing \(nwShares.count, privacy: .public) legacy MDM shares")

            for share in nwShares {
                let shareRectified = share // %USERNAME% resolved at mount/display time
                configurations.append(ShareConfiguration(
                    shareURL: shareRectified,
                    username: NSUserName(),
                    authType: AuthType.krb.rawValue
                ))
            }
        }

        // 3. Process user-defined shares
        if let privSharesDict = userDefaults.array(forKey: Defaults.userNetworkShares) as? [[String: String]], !privSharesDict.isEmpty {
            Logger.dataModel.debug("Processing \(privSharesDict.count, privacy: .public) user-defined shares (new format)")

            for shareElement in privSharesDict {
                guard let shareUrlString = shareElement[Defaults.networkShare] else { continue }

                configurations.append(ShareConfiguration(
                    shareURL: shareUrlString,
                    username: shareElement[Defaults.username],
                    authType: shareElement[Defaults.authType] ?? AuthType.krb.rawValue
                ))
            }
        }
        // Legacy user shares
        else if let nwShares = userDefaults.array(forKey: Defaults.customSharesKey) as? [String], !nwShares.isEmpty {
            Logger.dataModel.debug("Processing \(nwShares.count, privacy: .public) legacy user shares")

            for share in nwShares {
                configurations.append(ShareConfiguration(
                    shareURL: share,
                    username: nil, // Legacy shares don't have explicit usernames
                    authType: AuthType.krb.rawValue
                ))
            }
        }

        Logger.dataModel.info("Collected \(configurations.count, privacy: .public) total share configurations")
        return configurations
    }

    /// Gets password for a specific share configuration from keychain
    /// Searches based on the share's AuthType to determine the correct keychain format
    private func getPasswordForShareConfig(_ shareConfig: ShareConfiguration) -> (password: String, keychainType: KeychainEntryType)? {
        guard let username = shareConfig.username else {
            Logger.dataModel.warning("Invalid share config: \(shareConfig.shareURL, privacy: .public)")
            return nil
        }

        // Determine search strategy based on AuthType
        if shareConfig.authType == AuthType.krb.rawValue {
            // For Kerberos shares, try UPN-based entries first (these should stay in keychain)
            if let upnPassword = tryGetUPNPassword(for: username) {
                Logger.dataModel.debug("✅ Found UPN-based Kerberos password for \(username, privacy: .public)")
                return (password: upnPassword, keychainType: KeychainEntryType.kerberosUPN)
            }

            // Try FAU shared keychain
            if let fauPassword = tryGetFAUPassword(for: username) {
                Logger.dataModel.debug("✅ Found FAU shared Kerberos password for \(username, privacy: .public)")
                return (password: fauPassword, keychainType: KeychainEntryType.fauShared)
            }
        }

        // For password-based shares or fallback, try share-based entries (these should be migrated)
        if let url = URL(string: shareConfig.shareURL) {
            do {
                if let password = try keychainManager.retrievePassword(forShare: url, withUsername: username) {
                    Logger.dataModel.debug("✅ Found share-based password for \(shareConfig.shareURL, privacy: .public)")
                    return (password: password, keychainType: KeychainEntryType.shareBased)
                }
            } catch KeychainError.itemNotFound {
                Logger.dataModel.debug("No share-based password found for \(shareConfig.shareURL, privacy: .public)")
            } catch {
                Logger.dataModel.warning("Error retrieving share-based password: \(error)")
            }
        }

        Logger.dataModel.debug("❌ No password found for \(username, privacy: .public) in any keychain location")
        return nil
    }

    /// Types of keychain entries to determine migration strategy
    private enum KeychainEntryType {
        case kerberosUPN    // UPN-based Kerberos entry (keep in keychain)
        case fauShared      // FAU shared keychain entry (keep in keychain)
        case shareBased     // Share-based entry (migrate to profile format)
    }

    /// Try to get UPN-based password for Kerberos authentication
    private func tryGetUPNPassword(for username: String) -> String? {
        let localPart = username.split(separator: "@").first.map(String.init) ?? username.lowercased()
        let realmPart = username.contains("@") ? (username.split(separator: "@").last.map(String.init) ?? "fauad.fau.de") : "fauad.fau.de"

        // Try both lowercase and uppercase realm variants
        let upnVariants = [
            "\(localPart.lowercased())@\(realmPart.lowercased())",
            "\(localPart.lowercased())@\(realmPart.uppercased())"
        ]

        for upn in upnVariants {
            do {
                if let password = try keychainManager.retrievePassword(forUsername: upn, andService: Defaults.keyChainService) {
                    Logger.dataModel.debug("Found UPN password for \(upn, privacy: .public)")
                    return password
                }
            } catch KeychainError.itemNotFound {
                continue
            } catch {
                Logger.dataModel.warning("Error accessing UPN credentials for \(upn, privacy: .public): \(error)")
            }
        }
        Logger.dataModel.debug("No UPN password found for \(username, privacy: .public)")
        return nil
    }

    /// Try to get password from FAU shared keychain
    private func tryGetFAUPassword(for username: String) -> String? {
        do {
            let fauCredentials = try keychainManager.retrieveAllFAUSharedCredentials()
            return fauCredentials.first(where: { $0.username.lowercased() == username.lowercased() })?.password
        } catch {
            Logger.dataModel.debug("Could not retrieve FAU credentials: \(error)")
            return nil
        }
    }

    /// Try to get Kerberos password using various approaches
    private func tryGetKerberosPassword(for username: String, shareURL: String) -> String? {
        // Try with lowercase username (common pattern for Kerberos)
        let lowercaseUsername = username.lowercased()

        // Try different keychain services that might be used for Kerberos
        let possibleServices = [
            "de.fau.rrze.faucredentials",
            Defaults.keyChainService,
            "networkShareMounter"
        ]

        for service in possibleServices {
            do {
                let password = try keychainManager.retrievePassword(forUsername: lowercaseUsername, andService: service)
                Logger.dataModel.debug("Found Kerberos password with service: \(service)")
                return password
            } catch {
                // Continue to next service
            }
        }
        return nil
    }

    /// Gets password for a specific share and username from keychain
    private func getPasswordForShare(_ share: Share, username: String) async -> String? {
        guard let url = URL(string: share.networkShare) else {
            Logger.dataModel.warning("Invalid share URL: \(share.networkShare, privacy: .public)")
            return nil
        }

        do {
            // Try to get password using existing KeychainManager methods
            let password = try keychainManager.retrievePassword(forShare: url, withUsername: username)
            Logger.dataModel.debug("Found password for \(share.networkShare, privacy: .public) with user \(username)")
            return password
        } catch KeychainError.itemNotFound {
            Logger.dataModel.debug("No password found for \(share.networkShare, privacy: .public) with user \(username)")
            return nil
        } catch {
            Logger.dataModel.warning("Error retrieving password for \(share.networkShare, privacy: .public): \(error)")
            return nil
        }
    }

    /// Determines if a credential belongs to a Kerberos account
    private func isKerberosCredential(username: String, kerberosRealm: String?, dogeAccounts: [DogeAccount]) -> Bool {
        // Method 1: Check if username matches any DogeAccount UPN
        for account in dogeAccounts {
            if account.upn.lowercased() == username.lowercased() {
                Logger.dataModel.debug("✅ Kerberos credential detected via DogeAccount: \(username, privacy: .public)")
                return true
            }
        }

        // Method 2: Check if username domain matches configured Kerberos realm
        if let realm = kerberosRealm, !realm.isEmpty,
           let userDomain = username.userDomain() {
            if userDomain.lowercased() == realm.lowercased() {
                Logger.dataModel.debug("✅ Kerberos credential detected via realm match: \(username, privacy: .public)")
                return true
            }
        }

        Logger.dataModel.debug("🔍 Standard credential: \(username)")
        return false
    }

    /// Extracts the Kerberos realm for a credential
    private func extractKerberosRealm(username: String, kerberosRealm: String?, dogeAccounts: [DogeAccount]) -> String? {
        // Try to get realm from username domain
        if let userDomain = username.userDomain() {
            return userDomain
        }
        // Fall back to configured realm
        return kerberosRealm
    }

    // MARK: - Validation Methods

    /// Checks if a regular (non-external) Kerberos profile already exists for the given realm.
    /// External pseudo-profiles are excluded so they don't count as realm conflicts.
    func findExistingKerberosProfile(forRealm realm: String) -> AuthProfile? {
        return profiles.first { profile in
            profile.useKerberos &&
            !profile.isExternallyManaged &&
            profile.kerberosRealm?.uppercased() == realm.uppercased()
        }
    }

    /// Returns an existing external pseudo-profile for the given realm, or creates one.
    /// The returned profile has `isExternallyManaged = true`, carries no credentials,
    /// and is read-only in the UI. It is used solely to satisfy the "assigned profile"
    /// requirement for shares whose Kerberos tickets are managed externally.
    func createOrFindExternalKerberosProfile(for realm: String) async -> String {
        let normalizedRealm = realm.uppercased()

        if let existing = profiles.first(where: {
            $0.isExternallyManaged &&
            $0.kerberosRealm?.uppercased() == normalizedRealm
        }) {
            Logger.dataModel.debug("♻️ Reusing existing external Kerberos profile for realm \(normalizedRealm, privacy: .public)")
            return existing.id
        }

        var profile = AuthProfile(
            displayName: normalizedRealm,
            useKerberos: true,
            kerberosRealm: normalizedRealm
        )
        profile.isExternallyManaged = true
        profile.symbolName = "externaldrive.badge.checkmark"
        profile.symbolColorData = Color.teal.toData()

        // Bypass normal addProfile to avoid realm-conflict check against regular profiles
        profiles.append(profile)
        saveProfiles()
        Logger.dataModel.info("✅ Created external Kerberos pseudo-profile for realm \(normalizedRealm, privacy: .public) (ID: \(profile.id, privacy: .public))")
        return profile.id
    }

    /// Validates a Kerberos profile against existing DogeAccounts.
    /// Returns true if the profile's username exists in DogeAccounts or if validation is not applicable.
    func validateKerberosProfile(_ profile: AuthProfile) async -> Bool {
        guard profile.useKerberos, let username = profile.username else {
            // Non-Kerberos profiles don't need DogeAccount validation
            return !profile.useKerberos
        }

        let accountsManager = AccountsManager.shared
        let dogeAccounts = await accountsManager.accounts

        let isValid = dogeAccounts.contains { account in
            account.upn.lowercased() == username.lowercased()
        }

        if !isValid {
            Logger.dataModel.warning("⚠️ Kerberos profile validation failed: Username '\(username, privacy: .public)' not found in DogeAccounts")
        } else {
            Logger.dataModel.debug("✅ Kerberos profile validation passed for username: \(username, privacy: .public)")
        }

        return isValid
    }

    /// Comprehensive profile validation including basic checks and DogeAccount validation for Kerberos.
    /// Returns validation result and user-friendly error messages.
    func validateProfile(_ profile: AuthProfile) async -> (isValid: Bool, errors: [String], realmConflict: AuthProfile?) {
        var errors: [String] = []
        var realmConflict: AuthProfile? = nil

        // Basic validation from AuthProfile
        if !profile.isValidKerberosProfile {
            if profile.useKerberos && !profile.isValidKerberosUsername {
                errors.append("The username must be entered in the format username@domain.de")
            }
            if profile.useKerberos && !profile.hasConsistentKerberosRealm {
                errors.append("The domain in the username does not match the configured Kerberos domain")
            }
        }

        // Check for realm conflicts in Kerberos profiles
        if profile.useKerberos, let realm = profile.kerberosRealm {
            if let existingProfile = findExistingKerberosProfile(forRealm: realm) {
                // Only report conflict if it's not the same profile being updated
                if existingProfile.id != profile.id {
                    realmConflict = existingProfile
                    // Don't add to errors - this will be handled by UI confirmation
                }
            }
        }

        // DogeAccount validation for Kerberos profiles: advisory only, does not block creation.
        // Accounts from other realms or profiles created before login would fail here unnecessarily.
        if profile.useKerberos {
            _ = await validateKerberosProfile(profile)
        }

        return (errors.isEmpty && realmConflict == nil, errors, realmConflict)
    }

    // MARK: - Default Realm Profile Management

    /// Checks if a default realm profile already exists
    /// A default realm profile is one that uses Kerberos and matches the MDM-configured realm
    func hasDefaultRealmProfile() -> Bool {
        let prefs = PreferenceManager()
        guard let mdmRealm = prefs.string(for: .kerberosRealm), !mdmRealm.isEmpty else { return false }

        return profiles.contains { profile in
            profile.useKerberos &&
            profile.kerberosRealm?.lowercased() == mdmRealm.lowercased()
        }
    }

    /// Checks if MDM has configured a Kerberos realm but no matching profile exists yet
    /// Returns the MDM realm if setup is needed, nil otherwise
    func needsMDMKerberosSetup() -> String? {
        let prefs = PreferenceManager()
        guard let mdmRealm = prefs.string(for: .kerberosRealm), !mdmRealm.isEmpty else {
            return nil // No MDM realm configured
        }

        // Check if we already have a profile for this realm
        let hasExistingProfile = profiles.contains { profile in
            profile.useKerberos &&
            profile.kerberosRealm?.lowercased() == mdmRealm.lowercased()
        }

        return hasExistingProfile ? nil : mdmRealm
    }

    /// Checks if the given realm is configured via MDM and should be locked in UI
    func isMDMConfiguredRealm(_ realm: String?) -> Bool {
        let prefs = PreferenceManager()
        guard let mdmRealm = prefs.string(for: .kerberosRealm), !mdmRealm.isEmpty,
              let realm = realm else { return false }

        return mdmRealm.lowercased() == realm.lowercased()
    }

    /// Creates a default realm profile if MDM realm is configured and no default profile exists
    func createDefaultRealmProfileIfNeeded() async throws {
        let prefs = PreferenceManager()
        guard let mdmRealm = prefs.string(for: .kerberosRealm), !mdmRealm.isEmpty else {
            Logger.dataModel.debug("No MDM Kerberos realm configured")
            return
        }

        // Check if default realm profile already exists
        if hasDefaultRealmProfile() {
            Logger.dataModel.debug("Default realm profile already exists for realm: \(mdmRealm, privacy: .public)")
            return
        }

        Logger.dataModel.info("Creating default realm profile for MDM realm: \(mdmRealm, privacy: .public)")

        // Get username from DogeAccounts for the realm
        let accountsManager = AccountsManager.shared
        let dogeAccounts = await accountsManager.accounts

        // Find matching DogeAccount for this realm
        let matchingAccount = dogeAccounts.first { account in
            let accountRealm = account.upn.components(separatedBy: "@").last?.uppercased()
            return accountRealm == mdmRealm.uppercased()
        }

        let username = matchingAccount?.upn ?? "\(NSUserName())@\(mdmRealm)"

        // Create default realm profile
        let profileId = UUID().uuidString
        let profile = AuthProfile(
            id: profileId,
            displayName: "Standard Kerberos",
            username: username,
            useKerberos: true,
            kerberosRealm: mdmRealm,
            associatedNetworkShares: [],
            symbolName: "ticket"
        )

        // Add to profiles and save
        profiles.append(profile)
        saveProfiles()

        Logger.dataModel.info("Default realm profile created successfully")
    }

    /// Checks if a profile is the default realm profile (non-deletable)
    func isDefaultRealmProfile(_ profile: AuthProfile) -> Bool {
        let prefs = PreferenceManager()
        guard let mdmRealm = prefs.string(for: .kerberosRealm), !mdmRealm.isEmpty else { return false }

        return profile.useKerberos &&
               profile.kerberosRealm?.lowercased() == mdmRealm.lowercased() &&
               profile.displayName == "Standard Kerberos"
    }

    // MARK: - Helper Functions for Migration

    /// Gets the MDM-configured Kerberos realm as fallback for migration
    private func getMDMKerberosRealm() -> String? {
        let prefs = PreferenceManager()
        return prefs.string(for: .kerberosRealm)
    }

    /// Checks if a username belongs to a Kerberos user
    /// Returns both the result and the associated realm
    private func checkIfKerberosUser(username: String) async -> (isKerberos: Bool, realm: String?) {
        // Get Kerberos realm from preferences
        let prefs = PreferenceManager()
        let kerberosRealm = prefs.string(for: .kerberosRealm)

        // Get existing DogeAccounts (Kerberos accounts)
        let accountsManager = AccountsManager.shared
        let dogeAccounts = await accountsManager.accounts

        // Check if username matches any DogeAccount UPN
        let matchesDogeAccount = dogeAccounts.contains { account in
            account.upn.lowercased() == username.lowercased()
        }

        if matchesDogeAccount {
            // Extract realm from DogeAccount or use configured realm
            if let account = dogeAccounts.first(where: { $0.upn.lowercased() == username.lowercased() }) {
                let realm = extractRealmFromUPN(account.upn) ?? kerberosRealm
                return (true, realm)
            }
        }

        // Check if username domain matches configured Kerberos realm
        if let realm = kerberosRealm, !realm.isEmpty {
            if username.lowercased().hasSuffix("@\(realm.lowercased())") {
                return (true, realm)
            }
        }

        return (false, nil)
    }

    /// Extracts realm from UPN (User Principal Name)
    private func extractRealmFromUPN(_ upn: String?) -> String? {
        guard let upn = upn else { return nil }
        let components = upn.split(separator: "@")
        return components.count > 1 ? String(components[1]) : nil
    }

    // MARK: - Credential Onboarding

    /// Checks whether the user needs to be prompted for network credentials.
    ///
    /// Returns a `CredentialOnboardingInfo` describing the gaps, or `nil` when everything is
    /// already configured (existing profiles, AD binding, or no realm/shares configured).
    func credentialOnboardingInfo(realm: String?, allShares: [Share], isADBound: Bool) -> CredentialOnboardingInfo? {
        var krbRealm: String? = nil

        if let realm = realm, !realm.isEmpty, !isADBound {
            // Only prompt for Kerberos credentials if at least one share actually relies on
            // app-managed Kerberos. Shares flagged with externalKerberosManagement get their
            // tickets from an external tool (Jamf Connect, Apple SSO Extension, AD binding),
            // so NSM needs no credentials and must not prompt.
            let needsAppManagedKerberos = allShares.contains {
                $0.authType == .krb && !$0.externalKerberosManagement
            }
            let hasProfile = profiles.contains {
                $0.useKerberos &&
                !$0.isExternallyManaged &&
                ($0.kerberosRealm?.caseInsensitiveCompare(realm) == .orderedSame) &&
                !($0.username?.isEmpty ?? true)
            }
            if needsAppManagedKerberos && !hasProfile {
                krbRealm = realm
            }
        }

        let unassignedPwd = allShares.filter {
            $0.managed &&
            $0.authType == .pwd &&
            ($0.authProfileID == nil || ($0.authProfileID?.isEmpty ?? false))
        }

        guard krbRealm != nil || !unassignedPwd.isEmpty else { return nil }

        let suggestedUsername = jamfConnectUsername() ?? NSUserName()
        return CredentialOnboardingInfo(
            kerberosRealm: krbRealm,
            suggestedUsername: suggestedUsername,
            unassignedPasswordShares: unassignedPwd
        )
    }

    /// Creates the necessary AuthProfiles from onboarding input and links MDM password shares.
    func createOnboardingProfiles(
        username: String,
        password: String,
        info: CredentialOnboardingInfo,
        shareManager: ShareManager
    ) async throws {
        // Kerberos profile
        if let realm = info.kerberosRealm {
            let upn = username.contains("@") ? username : "\(username)@\(realm)"
            let profileName = UserDefaults.standard.string(forKey: PreferenceKeys.kerberosProfileDisplayName.rawValue)
                .flatMap { $0.isEmpty ? nil : $0 } ?? realm
            let krbProfile = AuthProfile(
                displayName: profileName,
                username: upn,
                useKerberos: true,
                kerberosRealm: realm
            )
            try await addProfile(krbProfile, password: password)
            Logger.dataModel.info("✅ Created Kerberos onboarding profile '\(profileName, privacy: .public)' for realm \(realm, privacy: .public)")

            // Auto-assign all unassigned Kerberos shares to the new profile
            let allShares = await shareManager.allShares
            for share in allShares where share.authType == .krb && share.authProfileID == nil {
                if let profileID = autoAssignKerberosProfile(shareURL: share.networkShare, username: share.username, kerberosRealm: realm) {
                    await shareManager.setAuthProfile(profileID, forShareWithURL: share.networkShare)
                }
            }
        }

        // Password profile (shared by all unassigned MDM password shares)
        if !info.unassignedPasswordShares.isEmpty {
            let shareURLs = info.unassignedPasswordShares.map { $0.networkShare }
            var pwdProfile = AuthProfile(
                displayName: username,
                username: username,
                useKerberos: false
            )
            pwdProfile.associatedNetworkShares = shareURLs
            try await addProfile(pwdProfile, password: password)

            // Update in-memory authProfileID for each share
            if let created = profiles.last(where: { !$0.useKerberos && $0.username == username }) {
                for share in info.unassignedPasswordShares {
                    await shareManager.setAuthProfile(created.id, forShareWithURL: share.networkShare)
                }
            }
            Logger.dataModel.info("✅ Created Password onboarding profile for \(info.unassignedPasswordShares.count, privacy: .public) shares")
        }
    }

    /// Reads the Jamf Connect state plist to find a pre-configured short username.
    private func jamfConnectUsername() -> String? {
        let plistURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/com.jamf.connect.state.plist")
        guard let dict = NSDictionary(contentsOf: plistURL) else { return nil }
        return (dict["CustomShortName"] as? String ?? dict["UserShortName"] as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
    }

    // MARK: - Share Migration

    /// Updates existing user shares to link them with newly created AuthProfiles
    /// This ensures v3→v4 migration connects existing shares with the correct profiles
    func updateExistingSharesWithProfiles() async {
        Logger.dataModel.info("🔗 Starting share migration to link existing shares with AuthProfiles")

        // Read current user shares from UserDefaults
        guard let userShares = UserDefaults.standard.array(forKey: Defaults.userNetworkShares) as? [[String: String]] else {
            Logger.dataModel.info("📝 No user shares found to migrate")
            return
        }

        var updatedShares: [[String: String]] = []
        var migrationCount = 0

        for shareConfig in userShares {
            var updatedShare = shareConfig

            // Skip shares that already have an authProfileID
            if shareConfig[Defaults.authProfileID] != nil {
                Logger.dataModel.debug("⏭️ Share \(shareConfig[Defaults.networkShare] ?? "unknown") already has authProfileID, skipping")
                updatedShares.append(updatedShare)
                continue
            }

            // Get share details
            guard let shareURL = shareConfig[Defaults.networkShare],
                  let username = shareConfig[Defaults.username] else {
                Logger.dataModel.debug("⏭️ Share missing URL or username, skipping: \(shareConfig, privacy: .public)")
                updatedShares.append(updatedShare)
                continue
            }

            // Find matching AuthProfile for this username
            let matchingProfile = profiles.first { profile in
                // For password profiles: exact username match
                if !profile.useKerberos {
                    return profile.username?.lowercased() == username.lowercased()
                }

                // For Kerberos profiles: check if username matches (with or without domain)
                let profileUsername = profile.username?.components(separatedBy: "@")[0]
                let shareUsername = username.components(separatedBy: "@")[0]
                return profileUsername?.lowercased() == shareUsername.lowercased()
            }

            if let profile = matchingProfile {
                updatedShare[Defaults.authProfileID] = profile.id
                migrationCount += 1
                Logger.dataModel.info("✅ Linked share \(shareURL, privacy: .public) with AuthProfile '\(profile.displayName, privacy: .public)' (ID: \(profile.id, privacy: .public))")

                // For AuthProfile shares, determine correct authType
                updatedShare[Defaults.authType] = profile.useKerberos ? AuthType.krb.rawValue : AuthType.pwd.rawValue
            } else {
                Logger.dataModel.warning("⚠️ No matching AuthProfile found for share \(shareURL, privacy: .public) with username \(username, privacy: .public)")
            }

            updatedShares.append(updatedShare)
        }

        // Save updated shares back to UserDefaults
        if migrationCount > 0 {
            UserDefaults.standard.set(updatedShares, forKey: Defaults.userNetworkShares)
            Logger.dataModel.info("✅ Share migration completed: \(migrationCount, privacy: .public) shares linked with AuthProfiles")
        } else {
            Logger.dataModel.info("📝 No shares needed AuthProfile linking")
        }
    }
}

// MARK: - Logger Extension
// Ensure this extension or an equivalent is available where AuthProfileManager is used.
// If you centralize logger definitions, you might import that instead.
extension Logger {
    private static var subsystem = Bundle.main.bundleIdentifier!
    // Ensure this category doesn't conflict if defined elsewhere
    // static let dataModel = Logger(subsystem: subsystem, category: "DataModel")
    // If already defined, this extension might not be needed here.
    // If not defined, uncomment the line above or ensure appropriate logger access.
}
