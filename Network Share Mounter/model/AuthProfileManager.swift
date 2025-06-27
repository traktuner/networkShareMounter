import Foundation
import Combine
import OSLog

// MARK: - AuthProfileManager

/// Manages the collection of authentication profiles.
/// Handles loading/saving profile metadata (to UserDefaults) and coordinates password storage (via KeychainManager).
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
        Logger.dataModel.info("AuthProfileManager initialized. Loaded \(self.profiles.count) profiles.")
    }
    
    // --- Profile Management ---

    /// Adds a new profile and optionally saves its password to the Keychain.
    /// - Parameters:
    ///   - profile: The `AuthProfile` object to add (ID should be set).
    ///   - password: The password associated with the profile, if any.
    func addProfile(_ profile: AuthProfile, password: String?) async throws {
        guard !profiles.contains(where: { $0.id == profile.id }) else {
            Logger.dataModel.warning("Attempted to add profile with duplicate ID: \(profile.id)")
            // Optionally throw an error here
            return
        }
        
        // Add profile metadata
        profiles.append(profile)
        saveProfiles() // Save metadata changes
        
        // Save password if provided
        if let pwd = password, !pwd.isEmpty {
            try await savePassword(for: profile, password: pwd)
        }
        Logger.dataModel.info("Added profile '\(profile.displayName)' (ID: \(profile.id))")
    }

    /// Updates an existing profile's metadata. Does not modify the password.
    /// - Parameter profile: The `AuthProfile` with updated metadata.
    func updateProfile(_ profile: AuthProfile) async throws {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else {
            Logger.dataModel.warning("Attempted to update non-existent profile ID: \(profile.id)")
            // Optionally throw an error
            return
        }
        
        await MainActor.run {
            profiles[index] = profile
            objectWillChange.send()
        }
        saveProfiles() // Save metadata changes
        Logger.dataModel.info("Updated profile '\(profile.displayName)' (ID: \(profile.id))")
    }

    /// Removes a profile and its associated password from the Keychain.
    /// - Parameter profile: The `AuthProfile` to remove.
    func removeProfile(_ profile: AuthProfile) async throws {
        profiles.removeAll { $0.id == profile.id }
        saveProfiles() // Save metadata changes
        
        // Remove password from Keychain
        try await removePassword(for: profile)
        Logger.dataModel.info("Removed profile '\(profile.displayName)' (ID: \(profile.id))")
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

    // --- Password Management Coordination ---

    /// Saves or updates the password for a given profile in the Keychain.
    /// - Parameters:
    ///   - profile: The profile whose password needs to be saved.
    ///   - password: The password string to save.
    func savePassword(for profile: AuthProfile, password: String) async throws {
        guard !password.isEmpty else {
            // If password is empty, consider removing it instead? Or do nothing?
            // For now, we'll remove it if an empty password is explicitly saved.
            Logger.dataModel.info("Password for profile '\(profile.displayName)' is empty. Removing from keychain.")
            try await removePassword(for: profile)
            return
        }
        do {
            // Use profile ID as the 'account' in the Keychain query
            try keychainManager.saveCredential(forUsername: profile.id, andPassword: password, withService: keychainServiceForProfiles)
            Logger.dataModel.debug("Saved password to keychain for profile ID: \(profile.id)")
        } catch {
            Logger.dataModel.error("Failed to save password to keychain for profile ID \(profile.id): \(error.localizedDescription)")
            throw error // Re-throw the error
        }
    }

    /// Retrieves the password for a given profile from the Keychain.
    /// - Parameter profile: The profile whose password should be retrieved.
    /// - Returns: The password string if found, otherwise `nil`.
    func retrievePassword(for profile: AuthProfile) async throws -> String? {
        do {
            let password = try keychainManager.retrievePassword(forUsername: profile.id, andService: keychainServiceForProfiles)
            Logger.dataModel.debug("Retrieved password from keychain for profile ID: \(profile.id) - \(password == nil ? "Not Found" : "Found")")
            return password
        } catch KeychainError.itemNotFound {
             Logger.dataModel.info("Password not found in keychain for profile ID \(profile.id)")
             return nil // Return nil specifically for itemNotFound
         } catch {
            Logger.dataModel.error("Failed to retrieve password from keychain for profile ID \(profile.id): \(error.localizedDescription)")
            throw error // Re-throw other errors
        }
    }
    
    /// Removes the password for a given profile from the Keychain.
    /// - Parameter profile: The profile whose password should be removed.
    func removePassword(for profile: AuthProfile) async throws {
        do {
            try keychainManager.removeCredential(forUsername: profile.id, andService: keychainServiceForProfiles)
            Logger.dataModel.debug("Removed password from keychain for profile ID: \(profile.id)")
        } catch KeychainError.itemNotFound {
             Logger.dataModel.info("Attempted to remove password for profile ID \(profile.id), but it was not found in keychain.")
             // Ignore itemNotFound, as the goal is achieved (password is gone)
         } catch {
            Logger.dataModel.error("Failed to remove password from keychain for profile ID \(profile.id): \(error.localizedDescription)")
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
            Logger.dataModel.info("Successfully loaded \(self.profiles.count) profiles from UserDefaults.")
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
            Logger.dataModel.debug("Successfully saved \(self.profiles.count) profiles to UserDefaults.")
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
    /// - Kerberos credentials: Create profiles that reference existing keychain entries
    /// - Username/Password credentials: Migrate to new profile-based keychain structure
    /// This preserves FAU shared keychain entries while eliminating share-based duplicates
    func migrateFromLegacyCredentials() async throws {
        Logger.dataModel.info("🔄 Starting hybrid credential migration")
        
        // Get all existing share-based credentials  
        let shareCredentials = try keychainManager.retrieveAllShareBasedCredentials()
        guard !shareCredentials.isEmpty else {
            Logger.dataModel.info("No legacy credentials found, skipping migration")
            return
        }
        
        Logger.dataModel.info("📋 Found \(shareCredentials.count) legacy credentials to migrate")
        
        // Get Kerberos realm from preferences
        let prefs = PreferenceManager()
        let kerberosRealm = prefs.string(for: .kerberosRealm)
        
        // Get existing DogeAccounts (Kerberos accounts)
        let accountsManager = AccountsManager.shared
        let dogeAccounts = await accountsManager.accounts
        
        // Separate credentials into Kerberos and Username/Password groups
        var kerberosGroups: [String: (username: String, shares: [String], kerberosRealm: String?)] = [:]
        var passwordGroups: [String: (username: String, password: String, shares: [String])] = [:]
        
        for credential in shareCredentials {
            let groupKey = credential.username.lowercased()
            
            // Check if this credential belongs to a Kerberos account
            let isKerberos = isKerberosCredential(username: credential.username, 
                                                  kerberosRealm: kerberosRealm, 
                                                  dogeAccounts: dogeAccounts)
            
            if isKerberos {
                // Kerberos credential - create profile that references existing keychain entry
                let realm = extractKerberosRealm(username: credential.username, 
                                                 kerberosRealm: kerberosRealm, 
                                                 dogeAccounts: dogeAccounts)
                
                if var existing = kerberosGroups[groupKey] {
                    existing.shares.append(credential.shareURL)
                    kerberosGroups[groupKey] = existing
                } else {
                    kerberosGroups[groupKey] = (
                        username: credential.username,
                        shares: [credential.shareURL],
                        kerberosRealm: realm
                    )
                }
            } else {
                // Username/Password credential - migrate to new profile structure
                if var existing = passwordGroups[groupKey] {
                    existing.shares.append(credential.shareURL)
                    passwordGroups[groupKey] = existing
                } else {
                    passwordGroups[groupKey] = (
                        username: credential.username,
                        password: credential.password,
                        shares: [credential.shareURL]
                    )
                }
            }
        }
        
        Logger.dataModel.info("📊 Creating \(kerberosGroups.count) Kerberos profiles and \(passwordGroups.count) password profiles")
        
        // Create Kerberos profiles (reference existing keychain entries)
        for (_, group) in kerberosGroups {
            let profileId = UUID().uuidString
            
            let profile = AuthProfile(
                id: profileId,
                displayName: group.username,
                username: group.username,
                useKerberos: true,
                kerberosRealm: group.kerberosRealm,
                associatedNetworkShares: group.shares,
                symbolName: "ticket"
            )
            
            do {
                // Add profile WITHOUT password - Kerberos profiles reference existing keychain entries
                try await addProfile(profile, password: nil)
                Logger.dataModel.info("✅ Created Kerberos profile '\(group.username)' for \(group.shares.count) shares (references existing keychain)")
            } catch {
                Logger.dataModel.error("❌ Failed to create Kerberos profile '\(group.username)': \(error)")
            }
        }
        
        // Create Username/Password profiles (migrate to new structure)
        for (_, group) in passwordGroups {
            let profileId = UUID().uuidString
            
            let profile = AuthProfile(
                id: profileId,
                displayName: group.username,
                username: group.username,
                useKerberos: false,
                kerberosRealm: nil,
                associatedNetworkShares: group.shares,
                symbolName: "person.circle"
            )
            
            do {
                // Add profile WITH password - migrates to new profile-based keychain structure
                try await addProfile(profile, password: group.password)
                Logger.dataModel.info("✅ Created password profile '\(group.username)' for \(group.shares.count) shares (migrated to new keychain)")
            } catch {
                Logger.dataModel.error("❌ Failed to create password profile '\(group.username)': \(error)")
            }
        }
        
        Logger.dataModel.info("🎉 Hybrid migration completed successfully")
        Logger.dataModel.info("📋 Summary: \(kerberosGroups.count) Kerberos profiles (reference existing), \(passwordGroups.count) password profiles (migrated)")
    }
    
    /// Determines if a credential belongs to a Kerberos account
    private func isKerberosCredential(username: String, kerberosRealm: String?, dogeAccounts: [DogeAccount]) -> Bool {
        // Method 1: Check if username matches any DogeAccount UPN
        for account in dogeAccounts {
            if account.upn.lowercased() == username.lowercased() {
                Logger.dataModel.debug("✅ Kerberos credential detected via DogeAccount: \(username)")
                return true
            }
        }
        
        // Method 2: Check if username domain matches configured Kerberos realm
        if let realm = kerberosRealm, !realm.isEmpty,
           let userDomain = username.userDomain() {
            if userDomain.lowercased() == realm.lowercased() {
                Logger.dataModel.debug("✅ Kerberos credential detected via realm match: \(username)")
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
