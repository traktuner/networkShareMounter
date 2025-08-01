//
//  GeneralSettingsView.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 10.04.25.
//  Copyright © 2024 RRZE. All rights reserved.
//

import SwiftUI
import OSLog // Add OSLog for logging
import dogeADAuth

// MARK: - Ticket Status Enums

/// Represents the current status of a Kerberos ticket
enum TicketStatus: Equatable {
    case unknown           // Initial state, checking...
    case valid             // Active, non-expired ticket found
    case expired           // Ticket found but expired
    case missing           // No ticket found for principal
    case kdcUnreachable    // Cannot reach KDC (network issue, not auth failure)
    case authenticationError // Invalid credentials or other auth failures
    
    var color: Color {
        switch self {
        case .unknown:
            return .secondary
        case .valid:
            return .green
        case .expired, .missing:
            return .secondary  // Neutral - not necessarily an error
        case .kdcUnreachable:
            return .secondary  // Neutral - network issue, not auth failure
        case .authenticationError:
            return .red        // Real error - wrong credentials
        }
    }
    
    var displayText: String {
        switch self {
        case .unknown:
            return "Prüfe..."
        case .valid:
            return "Ticket gültig"
        case .expired:
            return "Ticket abgelaufen"
        case .missing:
            return "Kein Ticket"
        case .kdcUnreachable:
            return "KDC nicht erreichbar"
        case .authenticationError:
            return "Authentifizierungsfehler"
        }
    }
    
    var helpText: String {
        switch self {
        case .unknown:
            return "Ticket-Status wird geprüft"
        case .valid:
            return "Aktives Kerberos-Ticket gefunden"
        case .expired:
            return "Kerberos-Ticket ist abgelaufen"
        case .missing:
            return "Kein Kerberos-Ticket für diesen Principal gefunden"
        case .kdcUnreachable:
            return "Kerberos-Server (KDC) ist nicht erreichbar"
        case .authenticationError:
            return "Anmeldedaten sind ungültig oder anderen Authentifizierungsfehler"
        }
    }
}

/// Represents the status of a ticket refresh operation
enum TicketRefreshStatus: Equatable {
    case idle
    case refreshing
    case success
    case failed(String)
    
    var displayText: String {
        switch self {
        case .idle:
            return ""
        case .refreshing:
            return "Prüfe..."
        case .success:
            return "Erfolgreich aktualisiert"
        case .failed(let error):
            // Simplify common error messages for user-friendly display
            if error.contains("unable to reach any KDC") {
                return "KDC nicht erreichbar"
            } else if error.contains("invalid credentials") || error.contains("UnAuthenticated") {
                return "Ungültige Anmeldedaten"
            } else if error.contains("OffDomain") {
                return "Außerhalb der Domäne"
            } else {
                return "Fehler bei Aktualisierung"
            }
        }
    }
    
    var color: Color {
        switch self {
        case .idle:
            return .secondary
        case .refreshing:
            return .secondary
        case .success:
            return .green
        case .failed(let error):
            // Use same logic as TicketStatus for consistency
            if error.contains("unable to reach any KDC") {
                return .secondary  // Network issue, not auth failure
            } else {
                return .red        // Real authentication error
            }
        }
    }
}

// MARK: - Ticket Status Helper Functions

/// Checks the Kerberos ticket status for a given profile
func checkKerberosTicketStatus(for profile: AuthProfile) async -> TicketStatus {
    guard profile.useKerberos else {
        return .missing
    }
    
    guard let username = profile.username, !username.isEmpty,
          let realm = profile.kerberosRealm, !realm.isEmpty else {
        return .missing
    }
    
    // Construct the principal to check
    let baseUsername = username.contains("@") ? String(username.split(separator: "@").first ?? "") : username
    let principalToCheck = "\(baseUsername)@\(realm.uppercased())"
    
    do {
        // Check current tickets
        let klistUtil = klistUtil
        let tickets = await klistUtil.returnTickets()
        
        // Find matching ticket
        if let matchingTicket = tickets.first(where: { ticket in
            ticket.principal.caseInsensitiveCompare(principalToCheck) == .orderedSame
        }) {
            // Check if ticket is still valid
            return matchingTicket.expires > Date() ? .valid : .expired
        } else {
            // No ticket found for this principal
            return .missing
        }
    } catch {
        // Could not check tickets - might be KDC unreachable or other issue
        // For now, return unknown - could be enhanced with specific error handling
        return .unknown
    }
}

// MARK: - Main Authentication View Refactored

struct AuthenticationView: View {
    @StateObject private var profileManager = AuthProfileManager.shared
    @State private var selectedProfileID: String?
    @State private var isAddingProfile = false
    @State private var isEditingProfile = false
    @State private var profileToEdit: AuthProfile?
    @State private var currentAssociatedShares: [Share] = []
    @State private var ticketRefreshStatus: [String: TicketRefreshStatus] = [:]
    
    // Access the Mounter (assuming appDelegate is accessible)
    // Consider injecting Mounter if appDelegate access is problematic
    private let mounter = appDelegate.mounter!
    
    // Logger
    // Assuming Logger.authenticationView is defined globally or via extension
    private let logger = Logger.authenticationView

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { 
            AuthenticationHeaderView()
            
            HStack(spacing: 0) {
                ProfileListView(
                    profileManager: profileManager, 
                    selectedProfileID: $selectedProfileID,
                    onAddProfile: { isAddingProfile = true },
                    onEditProfile: handleEditProfile, 
                    onRemoveProfile: handleRemoveProfile, 
                    onRefreshTicket: handleRefreshTicket 
                )
                .frame(width: 280)
                .cornerRadius(6) // Add corner radius to match other views
                
                Divider()
                    .padding(.horizontal, 0.5) // Add very slight padding around divider
                
                DetailColumnView(
                    selectedProfileID: selectedProfileID,
                    profileManager: profileManager,
                    currentAssociatedShares: currentAssociatedShares,
                    ticketRefreshStatus: ticketRefreshStatus,
                    onEditProfile: handleEditProfile, 
                    onRefreshTicket: handleRefreshTicket 
                )
                .cornerRadius(6) // Add corner radius to match other views
            }
            // Add spacing between header and content to match other views
            .padding(.top, 8)
        }
        // Add consistent outer padding to match NetworkSharesView and GeneralSettingsView
        .padding(20)
        .task(id: selectedProfileID) {
            await loadAssociatedShares(for: selectedProfileID)
        }
        .sheet(isPresented: $isAddingProfile) { 
            ProfileEditorView(mounter: mounter, isPresented: $isAddingProfile, onSave: { newProfile, password in
                Task {
                    do {
                        try await profileManager.addProfile(newProfile, password: password)
                        selectedProfileID = newProfile.id
                        logger.info("Successfully added profile '\(newProfile.displayName)'.")
                    } catch {
                        logger.error("Failed to add profile '\(newProfile.displayName)': \(error.localizedDescription)")
                        // TODO: Show error alert to user
                    }
                }
            })
        }
        .sheet(isPresented: $isEditingProfile) { 
            if let profile = profileToEdit {
                ProfileEditorView(
                    mounter: mounter,
                    isPresented: $isEditingProfile,
                    existingProfile: profile,
                    onSave: { updatedProfile, password in
                        Task {
                            do {
                                try await profileManager.updateProfile(updatedProfile)
                                if let pwd = password, !pwd.isEmpty {
                                    try await profileManager.savePassword(for: updatedProfile, password: pwd)
                                }
                                // Ensure UI updates happen on the main thread
                                await MainActor.run {
                                    // Force a refresh of the selected profile
                                    if selectedProfileID == updatedProfile.id {
                                        selectedProfileID = nil
                                        selectedProfileID = updatedProfile.id
                                    }
                                }
                                logger.info("Successfully updated profile '\(updatedProfile.displayName)'.")
                            } catch {
                                logger.error("Failed to update profile '\(updatedProfile.displayName)': \(error.localizedDescription)")
                                // TODO: Show error alert to user
                            }
                        }
                    }
                )
            } else {
                Text("Error: Profile to edit not found.") // Fallback view
            }
        }
        .onChange(of: isEditingProfile) { isEditing in
            // Clear profileToEdit when sheet is dismissed
            if !isEditing {
                profileToEdit = nil
            }
        }
        .onAppear {
             // Select first profile if none is selected initially
             if selectedProfileID == nil, let firstProfile = profileManager.profiles.first {
                 selectedProfileID = firstProfile.id
             }
             // Load shares for the initially selected profile
             if let initialID = selectedProfileID {
                 Task {
                     await loadAssociatedShares(for: initialID)
                 }
             }
         }
    }
    
    // --- Helper Functions for Actions --- 
    
    private func handleEditProfile(_ profile: AuthProfile) {
        profileToEdit = profile
        isEditingProfile = true
        logger.debug("Editing profile: \(profile.displayName)")
    }
    
    private func handleRemoveProfile(_ profile: AuthProfile) {
         Task {
             do {
                 try await profileManager.removeProfile(profile)
                 logger.info("Successfully removed profile '\(profile.displayName)'.")
                 if selectedProfileID == profile.id {
                     selectedProfileID = profileManager.profiles.first?.id
                 }
                 // Clear refresh status for removed profile
                 ticketRefreshStatus.removeValue(forKey: profile.id)
             } catch {
                 logger.error("Failed to remove profile '\(profile.displayName)': \(error.localizedDescription)")
                 // TODO: Show error alert to user
             }
        }
    }
    
    private func handleRefreshTicket(_ profile: AuthProfile) {
        logger.info("Starting ticket refresh for profile \(profile.displayName)")
        
        // Set refreshing status immediately
        ticketRefreshStatus[profile.id] = .refreshing
        
        Task {
            do {
                // Only handle Kerberos profiles
                guard profile.useKerberos, let username = profile.username else {
                    logger.warning("Profile \(profile.displayName) is not configured for Kerberos authentication")
                    await MainActor.run {
                        ticketRefreshStatus[profile.id] = .failed("Nicht für Kerberos konfiguriert")
                    }
                    return
                }
                
                // Check current ticket status using returnTickets (which returns Ticket objects with public expires)
                let klistUtil = klistUtil
                let tickets = await klistUtil.returnTickets()
                
                // Check if we have a valid ticket for this profile
                let targetPrincipal = username.lowercased()
                let hasValidTicket = tickets.contains { ticket in
                    ticket.principal.lowercased() == targetPrincipal && 
                    ticket.expires > Date()
                }
                
                if hasValidTicket {
                    logger.info("Valid ticket found for \(profile.displayName), no refresh needed")
                    await MainActor.run {
                        ticketRefreshStatus[profile.id] = .success
                        // Post success notification to update UI
                        NotificationCenter.default.post(name: .nsmNotification, object: nil, userInfo: ["krbAuthenticated": MounterError.krbAuthSuccessful])
                    }
                    
                    // Clear success status after 3 seconds
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(3))
                        ticketRefreshStatus[profile.id] = .idle
                    }
                    return
                }
                
                logger.info("No valid ticket found, starting authentication for \(profile.displayName)")
                
                // Get password from keychain using profile-based storage
                guard let password = try await profileManager.retrievePassword(for: profile) else {
                    logger.error("No password found in keychain for profile \(profile.displayName)")
                    await MainActor.run {
                        ticketRefreshStatus[profile.id] = .failed("Kein Passwort im Schlüsselbund")
                        // Post error notification
                        NotificationCenter.default.post(name: .nsmNotification, object: nil, userInfo: ["KrbAuthError": MounterError.krbAuthenticationError])
                    }
                    return
                }
                
                // Create authentication session
                let realm = profile.kerberosRealm ?? "FAUAD.FAU.DE"
                let session = dogeADSession(domain: realm, user: username)
                session.setupSessionFromPrefs(prefs: PreferenceManager())
                session.userPass = password
                
                // Set up delegate for authentication callbacks
                let authDelegate = TicketRefreshDelegate(profile: profile) { success, error in
                    Task { @MainActor in
                        if success {
                            logger.info("Ticket refresh successful for \(profile.displayName)")
                            ticketRefreshStatus[profile.id] = .success
                            // Post success notification to update menu and icon
                            NotificationCenter.default.post(name: .nsmNotification, object: nil, userInfo: ["krbAuthenticated": MounterError.krbAuthSuccessful])
                            
                            // Clear success status after 3 seconds
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(3))
                                ticketRefreshStatus[profile.id] = .idle
                            }
                        } else {
                            let errorMessage = error?.localizedDescription ?? "Unbekannter Fehler"
                            logger.error("Ticket refresh failed for \(profile.displayName): \(errorMessage)")
                            ticketRefreshStatus[profile.id] = .failed(errorMessage)
                            // Post error notification to update menu and icon
                            NotificationCenter.default.post(name: .nsmNotification, object: nil, userInfo: ["KrbAuthError": MounterError.krbAuthenticationError])
                            
                            // Clear error status after 5 seconds
                            Task { @MainActor in
                                try? await Task.sleep(for: .seconds(5))
                                ticketRefreshStatus[profile.id] = .idle
                            }
                        }
                    }
                }
                
                session.delegate = authDelegate
                
                // Start authentication
                await session.authenticate(authTestOnly: false)
                
            } catch {
                logger.error("Error during ticket refresh for \(profile.displayName): \(error.localizedDescription)")
                await MainActor.run {
                    ticketRefreshStatus[profile.id] = .failed(error.localizedDescription)
                    // Post error notification
                    NotificationCenter.default.post(name: .nsmNotification, object: nil, userInfo: ["KrbAuthError": MounterError.krbAuthenticationError])
                    
                    // Clear error status after 5 seconds
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(5))
                        ticketRefreshStatus[profile.id] = .idle
                    }
                }
            }
        }
    }
    
    // --- Data Loading --- 
    
    private func loadAssociatedShares(for profileID: String?) async {
        guard let id = profileID, let selectedProfile = profileManager.getProfile(by: id) else {
            currentAssociatedShares = [] 
            logger.debug("Cleared associated shares (no profile selected or found).")
            return
        }
        logger.debug("Loading associated shares for profile: \(selectedProfile.displayName)")
        let allShares = await mounter.shareManager.allShares
        if let associatedURLs = selectedProfile.associatedNetworkShares {
            currentAssociatedShares = allShares.filter { share in
                associatedURLs.contains(share.networkShare)
            }
            logger.info("Loaded \(currentAssociatedShares.count) shares associated with profile '\(selectedProfile.displayName)'.")
        } else {
            currentAssociatedShares = []
            logger.info("Profile '\(selectedProfile.displayName)' has no associated shares.")
        }
    }
}

// MARK: - Logger Extension (Ensure accessible)
// Define or ensure Logger.authenticationView exists
// Example:
// extension Logger {
//     private static var subsystem = Bundle.main.bundleIdentifier!
//     static let authenticationView = Logger(subsystem: subsystem, category: "AuthenticationView")
// }

// MARK: - Preview

#Preview {
    AuthenticationView()
        // Optionally provide mock data manager in preview if needed
        // .environmentObject(MockAuthProfileManager())
}

// Remove definitions of extracted subviews from here:
/*
// MARK: - Subviews

/// Header View for Authentication Settings
struct AuthenticationHeaderView: View { ... }

// Placeholder view when no profile is selected
struct ProfileDetailPlaceholderView: View { ... }

/// View for the right detail column (shows selected profile details or placeholder)
struct DetailColumnView: View { ... }

/// View for displaying the list of authentication profiles.
struct ProfileListView: View { ... }

/// View for displaying a single row in the profile list.
struct ProfileRowView: View { ... }

// MARK: - ProfileDetailView

struct ProfileDetailView: View { ... }
*/ 

// MARK: - Authentication Delegate for Ticket Refresh

private class TicketRefreshDelegate: dogeADUserSessionDelegate {
    private let profile: AuthProfile
    private let completion: (Bool, Error?) -> Void
    private let logger = Logger.authenticationView
    
    init(profile: AuthProfile, completion: @escaping (Bool, Error?) -> Void) {
        self.profile = profile
        self.completion = completion
    }
    
    func dogeADAuthenticationSucceded() async {
        logger.info("Authentication succeeded for ticket refresh: \(self.profile.displayName, privacy: .public)")
        
        do {
            // Switch to the authenticated principal
            guard let username = profile.username else {
                logger.error("No username configured for profile \(self.profile.displayName, privacy: .public)")
                completion(false, NSError(domain: "TicketRefresh", code: -1, userInfo: [NSLocalizedDescriptionKey: "No username configured"]))
                return
            }
            
            let output = try await cliTask("/usr/bin/kswitch -p \(username)")
            logger.debug("kswitch output: \(output)")
            
            // Get user info (optional)
            // await session?.userInfo()
            
            completion(true, nil)
        } catch {
            logger.error("Error switching principal after authentication: \(error.localizedDescription)")
            completion(false, error)
        }
    }
    
    func dogeADAuthenticationFailed(error: dogeADSessionError, description: String) async {
        logger.error("Authentication failed for ticket refresh: \(self.profile.displayName, privacy: .public) - \(description)")
        
        // Handle specific error types
        switch error {
        case .UnAuthenticated:
            logger.error("Invalid credentials for \(self.profile.displayName, privacy: .public)")
        case .OffDomain:
            logger.error("Outside Kerberos domain for \(self.profile.displayName, privacy: .public)")
        default:
            logger.error("Unknown authentication error for \(self.profile.displayName, privacy: .public): \(description)")
        }
        
        completion(false, NSError(domain: "TicketRefresh", code: -1, userInfo: [NSLocalizedDescriptionKey: description]))
    }
    
    func dogeADUserInformation(user: ADUserRecord) {
        logger.debug("User information received for ticket refresh: \(user.userPrincipal, privacy: .public)")
        // Optional: Update user information in preferences
    }
} 
