//
//  GetKerberosStatusIntent.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 04.02.26.
//  Copyright © 2026 RRZE. All rights reserved.
//

import AppIntents
import Foundation

/// Result structure for Kerberos ticket status information.
struct KerberosTicketStatus: Codable {
    var hasValidTicket: Bool
    var principal: String?
    var expirationDate: Date?
    var remainingTime: String?
}

/// An App Intent that retrieves the current Kerberos ticket status.
///
/// This intent checks for active Kerberos tickets by executing `klist`
/// and parsing the output. It returns structured information about ticket
/// status, principal, and expiration time.
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
    /// Set to `true` to ensure the intent appears as an App Shortcut.
    static var openAppWhenRun: Bool = true
    
    /// Performs the intent by checking Kerberos ticket status.
    ///
    /// Executes `klist` command and parses the output to determine:
    /// - Whether valid tickets exist
    /// - Default principal name
    /// - Ticket expiration date
    /// - Remaining validity time
    ///
    /// - Returns: An intent result with ticket status information and a human-readable dialog.
    /// - Throws: May throw if the klist command fails.
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
    /// First checks UserDefaults cache (updated by main app), then falls back to klist.
    ///
    /// - Returns: A KerberosTicketStatus structure with ticket information.
    private func checkKerberosStatus() async -> KerberosTicketStatus {
        // Try to read cached status from UserDefaults (set by main app)
        if let cachedStatus = UserDefaults.standard.dictionary(forKey: "kerberosTicketStatus"),
           let hasValidTicket = cachedStatus["hasValidTicket"] as? Bool,
           let lastUpdated = cachedStatus["lastUpdated"] as? TimeInterval {
            
            let cacheAge = Date().timeIntervalSince1970 - lastUpdated
            
            // Use cached value if less than 5 minutes old
            if cacheAge < 300 {
                NSLog("[GetKerberosStatus] Using cached status: \(hasValidTicket) (age: \(Int(cacheAge))s)")
                
                if hasValidTicket {
                    // Try to get detailed info from klist
                    if let detailedStatus = try? await checkKlistDirectly(), detailedStatus.hasValidTicket {
                        return detailedStatus
                    }
                    // Fallback to basic status
                    return KerberosTicketStatus(hasValidTicket: true)
                } else {
                    return KerberosTicketStatus(hasValidTicket: false)
                }
            }
        }
        
        NSLog("[GetKerberosStatus] No valid cache, checking klist directly")
        return (try? await checkKlistDirectly()) ?? KerberosTicketStatus(hasValidTicket: false)
    }
    
    /// Executes klist directly to check ticket status.
    private func checkKlistDirectly() async throws -> KerberosTicketStatus {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/klist")
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        try task.run()
        task.waitUntilExit()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8) else {
            NSLog("[GetKerberosStatus] Failed to decode klist output")
            throw NSError(domain: "GetKerberosStatus", code: 1)
        }
        
        NSLog("[GetKerberosStatus] klist exit code: \(task.terminationStatus)")
        
        if task.terminationStatus != 0 {
            NSLog("[GetKerberosStatus] klist failed with exit code \(task.terminationStatus)")
            throw NSError(domain: "GetKerberosStatus", code: Int(task.terminationStatus))
        }
        
        return parseKlistOutput(output)
    }
    
    /// Parses klist output to extract ticket information.
    ///
    /// Expected format:
    /// ```
    /// Credentials cache: API:12345
    /// Principal: username@REALM.DE
    ///
    /// Issued                Expires               Principal
    /// Feb  4 10:00:00 2026  Feb  4 20:00:00 2026  krbtgt/REALM.DE@REALM.DE
    /// ```
    ///
    /// - Parameter output: The raw output from klist command.
    /// - Returns: A KerberosTicketStatus structure with parsed information.
    private func parseKlistOutput(_ output: String) -> KerberosTicketStatus {
        var status = KerberosTicketStatus(hasValidTicket: false)
        
        let lines = output.components(separatedBy: .newlines)
        
        for line in lines {
            if line.starts(with: "Principal:") {
                let principal = line.replacingOccurrences(of: "Principal:", with: "").trimmingCharacters(in: .whitespaces)
                status.principal = principal
                status.hasValidTicket = true
            }
            
            if line.contains("krbtgt/") {
                let components = line.split(separator: " ", omittingEmptySubsequences: true)
                if components.count >= 6 {
                    let expiresDateString = "\(components[3]) \(components[4]) \(components[5])"
                    status.expirationDate = parseDate(expiresDateString)
                    
                    if let expDate = status.expirationDate {
                        status.remainingTime = formatRemainingTime(until: expDate)
                    }
                }
            }
        }
        
        return status
    }
    
    /// Parses a date string in klist format.
    ///
    /// - Parameter dateString: Date string like "Feb  4 20:00:00 2026"
    /// - Returns: Parsed Date object, or nil if parsing fails.
    private func parseDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "MMM d HH:mm:ss yyyy"
        return formatter.date(from: dateString)
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
