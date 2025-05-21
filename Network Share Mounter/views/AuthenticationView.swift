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

// MARK: - Main Authentication View Refactored

struct AuthenticationView: View {
    @StateObject private var profileManager = AuthProfileManager.shared
    @State private var selectedProfileID: String?
    @State private var isAddingProfile = false
    @State private var isEditingProfile = false
    @State private var profileToEdit: AuthProfile?
    @State private var currentAssociatedShares: [Share] = []
    
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
                .frame(width: 300)
                .cornerRadius(6) // Add corner radius to match other views
                
                Divider()
                    .padding(.horizontal, 0.5) // Add very slight padding around divider
                
                DetailColumnView(
                    selectedProfileID: selectedProfileID,
                    profileManager: profileManager,
                    currentAssociatedShares: currentAssociatedShares,
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
             } catch {
                 logger.error("Failed to remove profile '\(profile.displayName)': \(error.localizedDescription)")
                 // TODO: Show error alert to user
             }
        }
    }
    
    private func handleRefreshTicket(_ profile: AuthProfile) {
        logger.info("Ticket refresh requested for profile \(profile.displayName) (placeholder action)")
        // Placeholder - Actual refresh logic would go here, possibly calling a KerberosManager
        // The .task in detail/row views will auto-refresh the UI status display if the ticket cache changes.
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
