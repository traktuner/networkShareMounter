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
import AppKit // For NSApplication

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
            return "Checking..."
        case .valid:
            return "Ticket valid"
        case .expired:
            return "Ticket expired"
        case .missing:
            return "No ticket"
        case .kdcUnreachable:
            return "KDC unreachable"
        case .authenticationError:
            return "Authentication error"
        }
    }
    
    var helpText: String {
        switch self {
        case .unknown:
            return "Checking ticket status"
        case .valid:
            return "Active Kerberos ticket found"
        case .expired:
            return "Kerberos ticket has expired"
        case .missing:
            return "No Kerberos ticket found for this principal"
        case .kdcUnreachable:
            return "Kerberos server (KDC) is unreachable"
        case .authenticationError:
            return "Invalid credentials or other authentication error"
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
            return "Checking..."
        case .success:
            return "Successfully refreshed"
        case .failed(let error):
                // Simplify common error messages for user-friendly display
                if error.contains("unable to reach any KDC") {
                    return "KDC unreachable"
                } else if error.contains("invalid credentials") || error.contains("UnAuthenticated") {
                    return "Invalid credentials"
                } else if error.contains("OffDomain") {
                    return "Outside domain"
                } else if error.contains("Nicht für Kerberos konfiguriert") {
                    return "Not configured for Kerberos"
                } else if error.contains("Kein Passwort im Schlüsselbund") {
                    return "No password in keychain"
                } else {
                    return "Refresh failed"
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
    
    guard let realm = profile.kerberosRealm, !realm.isEmpty else {
        return .missing
    }

    // Check current tickets
    let klistUtil = klistUtil
    let tickets = await klistUtil.returnTickets()

    // For externally managed profiles NSM has no own username/credentials. The ticket is
    // provided by an external tool (Jamf Connect, Apple SSO Extension, AD binding), so we
    // simply report whether any valid ticket exists for the realm — NSM only observes it.
    if profile.isExternallyManaged {
        guard let matchingTicket = tickets.first(where: { ticket in
            ticket.principal.uppercased().hasSuffix("@\(realm.uppercased())")
        }) else {
            return .missing
        }
        return matchingTicket.expires > Date() ? .valid : .expired
    }

    guard let username = profile.username, !username.isEmpty else {
        return .missing
    }

    // Construct the principal to check
    let baseUsername = username.contains("@") ? String(username.split(separator: "@").first ?? "") : username
    let principalToCheck = "\(baseUsername)@\(realm.uppercased())"

    // Find matching ticket
    if let matchingTicket = tickets.first(where: { ticket in
        ticket.principal.caseInsensitiveCompare(principalToCheck) == .orderedSame
    }) {
        return matchingTicket.expires > Date() ? .valid : .expired
    } else {
        return .missing
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
    @State private var saveErrorMessage: String?

    // Injected global service
    @EnvironmentObject private var mounter: Mounter

    // Auto-open parameters
    let autoOpenProfileCreation: Bool
    let mdmRealm: String?

    /// Initializer with optional auto-open parameters
    init(autoOpenProfileCreation: Bool = false, mdmRealm: String? = nil) {
        self.autoOpenProfileCreation = autoOpenProfileCreation
        self.mdmRealm = mdmRealm
    }
    
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
                    mounter: mounter,
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
        .onAppear {
            // Auto-open profile creation dialog if requested (e.g., for MDM setup)
            if autoOpenProfileCreation && !profileManager.profiles.isEmpty == false {
                // Only auto-open if no profiles exist or if MDM setup is specifically needed
                if mdmRealm != nil {
                    let needsSetup = AuthProfileManager.shared.needsMDMKerberosSetup() != nil
                    if needsSetup {
                        DispatchQueue.main.async {
                            self.isAddingProfile = true
                        }
                    }
                }
            }
        }
        // Live-Update: Reload associated shares when Mounter posts a reconstruct notification
        .onReceive(NotificationCenter.default.publisher(for: Defaults.nsmReconstructMenuTriggerNotification)) { _ in
            Task {
                await loadAssociatedShares(for: selectedProfileID)
            }
        }
        .sheet(isPresented: $isAddingProfile) {
            ProfileEditorView(
                mounter: mounter,
                isPresented: $isAddingProfile,
                mdmRealm: mdmRealm,
                onSave: { newProfile, password in
                    Task {
                        do {
                            try await profileManager.addProfile(newProfile, password: password)
                            selectedProfileID = newProfile.id
                            for shareURL in newProfile.associatedNetworkShares ?? [] {
                                await mounter.shareManager.setAuthProfile(newProfile.id, forShareWithURL: shareURL)
                            }
                            await mounter.shareManager.checkForUnassignedProfiles(notifyWhenAllAssigned: true)
                            logger.info("Successfully added profile '\(newProfile.displayName)'.")
                        } catch {
                            logger.error("Failed to add profile '\(newProfile.displayName)': \(error.localizedDescription)")
                            await MainActor.run {
                                saveErrorMessage = error.localizedDescription
                            }
                        }
                    }
                }
            )
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
                                for shareURL in updatedProfile.associatedNetworkShares ?? [] {
                                    await mounter.shareManager.setAuthProfile(updatedProfile.id, forShareWithURL: shareURL)
                                }
                                await mounter.shareManager.checkForUnassignedProfiles(notifyWhenAllAssigned: true)
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
                                await MainActor.run {
                                    saveErrorMessage = error.localizedDescription
                                }
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
        .alert("Profile could not be saved", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { saveErrorMessage = nil }
        } message: {
            if let msg = saveErrorMessage {
                Text(msg)
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
                        ticketRefreshStatus[profile.id] = .failed("Not configured for Kerberos")
                    }
                    return
                }
                
                // Check current ticket status using returnTickets (which returns Ticket objects with public expires)
                let klistUtil = klistUtil
                let tickets = await klistUtil.returnTickets()
                
                // Check if we have a valid ticket for this profile
                // Construct the full principal with realm (same logic as checkKerberosTicketStatus)
                let baseUsername = username.contains("@") ? String(username.split(separator: "@").first ?? "") : username
                let realm = profile.kerberosRealm ?? "FAUAD.FAU.DE"
                let targetPrincipal = "\(baseUsername)@\(realm.uppercased())"

                logger.debug("🔍 Checking for ticket: \(targetPrincipal, privacy: .public)")

                let hasValidTicket = tickets.contains { ticket in
                    ticket.principal.caseInsensitiveCompare(targetPrincipal) == .orderedSame &&
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
                        ticketRefreshStatus[profile.id] = .failed("No password in keychain")
                        // Post error notification
                        NotificationCenter.default.post(name: .nsmNotification, object: nil, userInfo: ["KrbAuthError": MounterError.krbAuthenticationError])
                    }
                    return
                }
                
                // Create authentication session
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
                            let errorMessage = error?.localizedDescription ?? "Unknown error"
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
        let associatedURLs = selectedProfile.associatedNetworkShares ?? []
        // Match by authProfileID (primary – works even when networkShare contains %USERNAME%)
        // or by URL in associatedNetworkShares (fallback for legacy profiles).
        currentAssociatedShares = allShares.filter { share in
            share.authProfileID == id || associatedURLs.contains(share.networkShare)
        }
        logger.info("Loaded \(currentAssociatedShares.count) shares associated with profile '\(selectedProfile.displayName)'.")
    }
}

// MARK: - Preview

#Preview {
    AuthenticationView()
        .environmentObject(Mounter())
}

// MARK: - Authentication Delegate for Ticket Refresh

private class TicketRefreshDelegate: dogeADUserSessionDelegate, @unchecked Sendable {
    private let profile: AuthProfile
    private let completion: (Bool, Error?) -> Void
    private let logger = Logger.authenticationView
    
    init(profile: AuthProfile, completion: @escaping (Bool, Error?) -> Void) {
        self.profile = profile
        self.completion = completion
    }
    
    func dogeADAuthenticationSucceeded() async {
        logger.info("Authentication succeeded for ticket refresh: \(self.profile.displayName, privacy: .public)")
        
        do {
            guard let username = profile.username else {
                logger.error("No username configured for profile \(self.profile.displayName, privacy: .public)")
                completion(false, NSError(domain: "TicketRefresh", code: -1, userInfo: [NSLocalizedDescriptionKey: "No username configured"]))
                return
            }
            
            let output = try await cliTask("/usr/bin/kswitch -p \(username)")
            logger.debug("kswitch output: \(output)")
            
            completion(true, nil)
        } catch {
            logger.error("Error switching principal after authentication: \(error.localizedDescription)")
            completion(false, error)
        }
    }
    
    func dogeADAuthenticationFailed(error: dogeADSessionError, description: String) async {
        logger.error("Authentication failed for ticket refresh: \(self.profile.displayName, privacy: .public) - \(description)")
        
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
    }
}
