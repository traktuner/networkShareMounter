//
//  GetKerberosStatusIntent.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 04.02.26.
//  Copyright © 2026 RRZE. All rights reserved.
//

import AppIntents
import Foundation
import dogeADAuth

/// Result structure for Kerberos ticket status information.
struct KerberosTicketStatus: Codable {
    var hasValidTicket: Bool
    var principal: String?
    var expirationDate: Date?
    var remainingTime: String?
}

/// An App Intent that retrieves the current Kerberos ticket status.
///
/// This intent looks up the credential cache for the configured Kerberos realm(s)
/// and returns structured information about ticket status, principal, and
/// expiration time.
///
/// Unlike other intents, this one does not open the app and directly
/// returns the status information for use in Shortcuts conditions.
struct GetKerberosStatusIntent: AppIntent {
    
    /// The localized display title shown in Shortcuts, Siri, and other system surfaces.
    static var title: LocalizedStringResource = LocalizedStringResource("GetKerberosStatus.Title", table: "Localizable")
    
    /// The localized, user-facing description explaining what this intent does.
    static var description = IntentDescription(LocalizedStringResource("GetKerberosStatus.Description", table: "Localizable"))
    
    /// Indicates whether the host app should open when the intent is executed.
    ///
    static var openAppWhenRun: Bool = false
    
    /// Performs the intent by checking Kerberos ticket status.
    ///
    /// - Returns: An intent result with ticket status information and a human-readable dialog.
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let status = await checkKerberosStatus()
        
        let dialog: IntentDialog
        if status.hasValidTicket {
            if let principal = status.principal, let remaining = status.remainingTime {
                dialog = IntentDialog(stringLiteral: String(
                    format: String(localized: "GetKerberosStatus.Success", table: "Localizable"),
                    principal,
                    remaining
                ))
            } else {
                dialog = IntentDialog(LocalizedStringResource("GetKerberosStatus.TicketFound", table: "Localizable"))
            }
        } else {
            dialog = IntentDialog(LocalizedStringResource("GetKerberosStatus.NoTicket", table: "Localizable"))
        }
        
        let statusString = formatStatusString(status)
        return .result(value: statusString, dialog: dialog)
    }
    
    /// Checks the current Kerberos ticket status.
    ///
    /// A recent authentication failure cached by the main app wins over existing tickets,
    /// because a ticket can still be present although authentication with it failed.
    ///
    /// - Returns: A KerberosTicketStatus structure with ticket information.
    private func checkKerberosStatus() async -> KerberosTicketStatus {
        let cachedValidity = recentCachedValidity()
        if cachedValidity == false {
            return KerberosTicketStatus(hasValidTicket: false)
        }

        guard let cache = await relevantCache() else {
            return KerberosTicketStatus(hasValidTicket: cachedValidity == true)
        }
        return KerberosTicketStatus(
            hasValidTicket: true,
            principal: cache.principal,
            expirationDate: cache.expires,
            remainingTime: formatRemainingTime(until: cache.expires)
        )
    }

    /// Returns the ticket validity cached by the main app, if it is less than 5 minutes old.
    private func recentCachedValidity() -> Bool? {
        guard let cachedStatus = UserDefaults.standard.dictionary(forKey: "kerberosTicketStatus"),
              let hasValidTicket = cachedStatus["hasValidTicket"] as? Bool,
              let lastUpdated = cachedStatus["lastUpdated"] as? TimeInterval,
              Date().timeIntervalSince1970 - lastUpdated < 300 else {
            return nil
        }
        return hasValidTicket
    }

    /// Finds the valid credential cache for the configured Kerberos realm(s).
    ///
    /// Without any configured realm, the default cache (or any valid cache) is used.
    private func relevantCache() async -> CredentialCache? {
        let caches = await KlistUtil().listCaches()

        var targets: [(realm: String, principal: String?)] = await MainActor.run {
            AuthProfileManager.shared.profiles.compactMap { profile -> (realm: String, principal: String?)? in
                guard profile.useKerberos, let realm = profile.kerberosRealm, !realm.isEmpty else { return nil }
                let principal = profile.username.flatMap {
                    $0.isEmpty ? nil : KerberosCacheCoordinator.principal(forUsername: $0, realm: realm)
                }
                return (realm, principal)
            }
        }
        if let defaultRealm = PreferenceManager().string(for: .kerberosRealm), !defaultRealm.isEmpty {
            targets.append((defaultRealm, nil))
        }

        guard !targets.isEmpty else {
            let validCaches = caches.filter { !$0.isExpired }
            return validCaches.first(where: \.isDefault) ?? validCaches.first
        }

        for target in targets {
            if let cache = KerberosCacheCoordinator.bestCache(in: caches, realm: target.realm, principal: target.principal) {
                return cache
            }
        }
        return nil
    }

    /// Formats the remaining time until ticket expiration.
    ///
    /// - Parameter date: The expiration date.
    /// - Returns: A human-readable string like "2h 30m" or "expired".
    private func formatRemainingTime(until date: Date) -> String {
        let now = Date()
        let interval = date.timeIntervalSince(now)
        
        if interval <= 0 {
            return String(localized: "GetKerberosStatus.Expired", table: "Localizable")
        }
        
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
    
    /// Formats the status structure as a string for Shortcuts output.
    ///
    /// - Parameter status: The ticket status to format.
    /// - Returns: A formatted string representation.
    private func formatStatusString(_ status: KerberosTicketStatus) -> String {
        if status.hasValidTicket {
            var result = String(localized: "GetKerberosStatus.StatusValid", table: "Localizable")
            if let principal = status.principal {
                result += "\n\(String(localized: "GetKerberosStatus.StatusPrincipal", table: "Localizable")): \(principal)"
            }
            if let remaining = status.remainingTime {
                result += "\n\(String(localized: "GetKerberosStatus.StatusRemaining", table: "Localizable")): \(remaining)"
            }
            return result
        } else {
            return String(localized: "GetKerberosStatus.StatusNoTicket", table: "Localizable")
        }
    }
}
