import SwiftUI
import OSLog

// MARK: - AuthProfile Model

/// Represents an authentication profile used for connecting to network shares.
/// Contains metadata about the profile; the associated password is stored securely in the Keychain.
struct AuthProfile: Identifiable, Codable, Equatable {
    /// Unique identifier for the profile. Used to link shares and Keychain entries.
    var id: String = UUID().uuidString
    
    /// User-defined name for the profile (e.g., "Work", "Home", "University").
    var displayName: String
    
    /// Username associated with the profile. Optional if using Kerberos without explicit username.
    var username: String?
    
    /// Indicates whether Kerberos authentication should be used for this profile.
    var useKerberos: Bool = false
    
    /// The Kerberos realm (e.g., "UNI-ERLANGEN.DE"). Required if `useKerberos` is true.
    var kerberosRealm: String?
    
    /// List of network share URLs (strings) that this profile should be used for.
    var associatedNetworkShares: [String]?
    
    /// SF Symbol name for visual representation in the UI.
    var symbolName: String? = "person.circle" // Default symbol
    
    /// Color data for the symbol's background. Stored as Data for Codability.
    var symbolColorData: Data? = Color.gray.toData() // Default color data
    
    /// A computed property to easily get the SwiftUI Color. Not Codable.
    var symbolColor: Color {
        get {
            guard let data = symbolColorData else { return .gray }
            return Color(data: data) ?? .gray
        }
        set {
            symbolColorData = newValue.toData()
        }
    }
    
    // Equatable conformance based on ID
    static func == (lhs: AuthProfile, rhs: AuthProfile) -> Bool {
        lhs.id == rhs.id
    }
    
    /// Helper to check if a password entry should exist in the keychain.
    /// A password is required if Kerberos is *not* used, or if Kerberos *is* used but requires username/password for ticket fetching.
    /// Note: This is a simplified check. Real logic might depend on specific Kerberos setup.
    var requiresPasswordInKeychain: Bool {
        return !useKerberos || (useKerberos && username != nil) // Simplified: Assume password needed if username present for Kerberos
    }

    /// Validates if the username is in proper UPN format for Kerberos authentication.
    /// UPN format: username@REALM.COM
    var isValidKerberosUsername: Bool {
        guard useKerberos, let username = username else { return !useKerberos }

        // UPN format: username@realm
        let components = username.split(separator: "@")
        guard components.count == 2 else { return false }

        let userPart = String(components[0])
        let realmPart = String(components[1])

        // Basic validation
        return !userPart.isEmpty &&
               !realmPart.isEmpty &&
               realmPart.uppercased() == realmPart // Realms are typically uppercase
    }

    /// Validates that the username realm matches the configured Kerberos realm.
    var hasConsistentKerberosRealm: Bool {
        guard useKerberos,
              let username = username,
              let realm = kerberosRealm else { return !useKerberos }

        let usernameRealm = username.components(separatedBy: "@").last
        return usernameRealm?.uppercased() == realm.uppercased()
    }

    /// Comprehensive validation for Kerberos profiles.
    var isValidKerberosProfile: Bool {
        guard useKerberos else { return true } // Non-Kerberos profiles are always valid here
        return isValidKerberosUsername && hasConsistentKerberosRealm
    }
}

// MARK: - Color <-> Data Conversion Helper

extension Color {
    /// Converts SwiftUI Color to Data for storing in Codable structs.
    func toData() -> Data? {
        do {
            // Use NSColor for macOS
            let nsColor = NSColor(self)
            // Archive NSColor instead of UIColor
            let data = try NSKeyedArchiver.archivedData(withRootObject: nsColor, requiringSecureCoding: false)
            return data
        } catch {
            Logger.authProfile.error("Failed to archive NSColor to Data: \(error.localizedDescription)")
            return nil
        }
    }

    /// Initializes SwiftUI Color from Data.
    init?(data: Data) {
        do {
            // Unarchive NSColor instead of UIColor
            if let nsColor = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: data) {
                // Initialize SwiftUI Color from NSColor
                self.init(nsColor: nsColor)
            } else {
                Logger.authProfile.error("Failed to unarchive NSColor from Data.")
                return nil
            }
        } catch {
            Logger.authProfile.error("Failed to unarchive NSColor from Data: \(error.localizedDescription)")
            return nil
        }
    }
} 
