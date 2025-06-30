import SwiftUI
import OSLog

// MARK: - Add/Edit Share View

/// A view presented as a sheet to add a new network share configuration or edit an existing one.
struct AddShareView: View {
    // Dependencies & Callbacks
    @Binding var isPresented: Bool
    let mounter: Mounter // Needed to access ShareManager
    @ObservedObject var profileManager: AuthProfileManager // Needed for profile selection
    var existingShare: Share? // Optional - if provided, we're editing instead of adding
    var onSave: () -> Void // Action to perform after saving
    
    // Environment for dismissal
    @Environment(\.dismiss) var dismiss

    // State for form fields
    @State private var networkShare: String = "" // e.g., smb://server/share
    @State private var shareDisplayName: String = ""
    @State private var selectedProfileID: String? = nil // Profile ID or nil for "None"
    
    // Logger
    private let logger = Logger.networkSharesView // Use logger from parent view category for now

    // Constants
    private let noProfileOptionID = "__NONE__" // Special ID for "None" option
    
    // Computed properties
    private var isEditing: Bool {
        existingShare != nil
    }
    
    private var windowTitle: String {
        isEditing ? "Share bearbeiten" : "Neuen Share hinzufügen"
    }

    var body: some View {
        // Remove NavigationView, manage title and buttons manually
        // NavigationView {
            Form {
                // Manual Title
                Text(windowTitle)
                    .font(.headline)
                    .padding(.bottom)
                
                Section("Share-Details") {
                    TextField("Netzwerkpfad (z.B. smb://server/pfad)", text: $networkShare)
                        .lineLimit(1)
                        .autocorrectionDisabled()
                        .disabled(isEditing && (existingShare?.managed == true)) // Disable editing for managed shares
                        // Add more modifiers as needed (text content type, etc.)
                    
                    TextField("Anzeigename (optional)", text: $shareDisplayName)
                        .lineLimit(1)
                }
                
                Section("Authentifizierung") {
                    if profileManager.profiles.isEmpty && !isEditing {
                        // Show loading state for new shares if no profiles are loaded yet
                        HStack {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Profile werden geladen...")
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 8)
                    } else {
                        Picker("Zugehöriges Profil:", selection: $selectedProfileID) {
                            // Add "None" option
                            Text("Kein Profil (Standard/System)").tag(String?.none) // Tag nil
                            
                            // List available profiles
                            ForEach(profileManager.profiles) { profile in
                                HStack {
                                    Image(systemName: profile.symbolName ?? "person.circle")
                                        .foregroundColor(profile.symbolColor)
                                    Text(profile.displayName)
                                }
                                .tag(profile.id as String?) // Tag optional ID
                            }
                        }
                        // Allow the picker to take more horizontal space
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    
                    // Add help text if needed
                    Text("Wählen Sie ein Authentifizierungsprofil aus, das für diesen Share verwendet werden soll. Wenn kein Profil ausgewählt wird, werden Standard-Systemmechanismen (z.B. Kerberos) versucht.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer() // Push buttons to the bottom if Form is scrollable
                
                // Manual Buttons
                HStack {
                    Button("Abbrechen") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                    
                    Spacer()
                    
                    Button(isEditing ? "Änderungen speichern" : "Speichern") {
                        Task {
                            if isEditing {
                                await handleUpdateChanges()
                            } else {
                                await handleSaveChanges()
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(networkShare.isEmpty) 
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.top)
                
            }
            // Remove navigation modifiers
            // .navigationTitle("Neuen Share hinzufügen")
            // .toolbar { ... }
            .padding(20) // Use consistent 20pt padding like other views
        // }
        .frame(minWidth: 450, minHeight: 400) // Increased height to accommodate padding
        .onAppear {
            setupForEditing()
        }
    }
    
    // --- Setup Methods ---
    
    /// Sets up the form fields when editing an existing share
    private func setupForEditing() {
        guard let share = existingShare else { return }
        
        networkShare = share.networkShare
        shareDisplayName = share.shareDisplayName ?? ""
        
        // Find associated profile for this share
        selectedProfileID = findAssociatedProfile(for: share)
        
        logger.info("Setup editing for share: \(share.networkShare)")
    }
    
    /// Finds which profile (if any) is associated with the given share
    private func findAssociatedProfile(for share: Share) -> String? {
        for profile in profileManager.profiles {
            if let associatedShares = profile.associatedNetworkShares,
               associatedShares.contains(share.networkShare) {
                return profile.id
            }
        }
        return nil
    }
    
    // --- Actions --- 
    
    /// Handles validation, share creation, profile update, and dismissal.
    private func handleSaveChanges() async { // Make the function async
        logger.info("Attempting to save new share: \(networkShare)")
        
        // 1. Validate input (basic)
        guard networkShare.contains("://") else {
            logger.error("Invalid network share format: \(networkShare)")
            // TODO: Show validation error alert to user
            return
        }
        
        // 2. Create Share object
        let displayName = shareDisplayName.isEmpty ? nil : shareDisplayName
        let newShare = Share.createShare(
            networkShare: networkShare,
            authType: .krb, // Default to Kerberos, actual auth depends on profile/Mounter logic
            mountStatus: .unmounted,
            managed: false, // User-added shares are not managed
            shareDisplayName: displayName
        )
        
        do {
            // 3. Add share via ShareManager
            // Assuming addShare handles duplicate checks internally
            await mounter.shareManager.addShare(newShare)
            logger.info("Successfully added share '\(newShare.networkShare)' to ShareManager.")

            // 4. Update profile if one was selected
            try await updateProfileAssociation(for: newShare.networkShare, oldShareURL: nil)
            
            // 5. Call onSave completion handler (signals success to parent)
            onSave() 
            
            // 6. Dismiss the sheet
            dismiss()
            
        } catch {
            // Handle errors from addShare or updateProfile
            logger.error("Failed to save new share or update profile: \(error.localizedDescription)")
            // TODO: Show error alert to the user
        }
    }
    
    /// Handles updating an existing share
    private func handleUpdateChanges() async {
        guard let originalShare = existingShare else {
            logger.error("Cannot update: original share not found")
            return
        }
        
        logger.info("Attempting to update share: \(originalShare.networkShare) -> \(networkShare)")
        
        // 1. Validate input (basic)
        guard networkShare.contains("://") else {
            logger.error("Invalid network share format: \(networkShare)")
            // TODO: Show validation error alert to user
            return
        }
        
        do {
            // 2. Update share properties
            var updatedShare = originalShare
            let oldShareURL = originalShare.networkShare
            
            updatedShare.networkShare = networkShare
            updatedShare.shareDisplayName = shareDisplayName.isEmpty ? nil : shareDisplayName
            
            // 3. Update share in ShareManager
            await mounter.updateShare(for: updatedShare)
            logger.info("Successfully updated share in ShareManager.")
            
            // 4. Update profile associations if share URL changed or profile selection changed
            try await updateProfileAssociation(for: networkShare, oldShareURL: oldShareURL)
            
            // 5. Call onSave completion handler (signals success to parent)
            onSave()
            
            // 6. Dismiss the sheet
            dismiss()
            
        } catch {
            logger.error("Failed to update share or profile associations: \(error.localizedDescription)")
            // TODO: Show error alert to the user
        }
    }
    
    /// Updates profile associations for the share
    private func updateProfileAssociation(for shareURL: String, oldShareURL: String?) async throws {
        // Remove old associations if share URL changed
        if let oldURL = oldShareURL, oldURL != shareURL {
            try await removeShareFromAllProfiles(shareURL: oldURL)
        }
        
        // Add new association if a profile is selected
        if let profileID = selectedProfileID {
            guard let profile = profileManager.getProfile(by: profileID) else {
                logger.error("Selected profile ID \(profileID) not found in ProfileManager.")
                // Proceed with saving share, but log profile issue
                return
            }
            
            var updatedProfile = profile
            var updatedShares = updatedProfile.associatedNetworkShares ?? []
            
            // Remove old URL if it was different
            if let oldURL = oldShareURL, oldURL != shareURL {
                updatedShares.removeAll { $0 == oldURL }
            }
            
            // Add new URL if not already present
            if !updatedShares.contains(shareURL) {
                updatedShares.append(shareURL)
                updatedProfile.associatedNetworkShares = updatedShares
                
                // Save the updated profile
                try await profileManager.updateProfile(updatedProfile)
                logger.info("Successfully associated share '\(shareURL)' with profile '\(updatedProfile.displayName)'.")
            } else {
                logger.warning("Share '\(shareURL)' already associated with profile '\(profile.displayName)'.")
            }
        } else {
            // No profile selected - remove share from all profiles
            try await removeShareFromAllProfiles(shareURL: shareURL)
        }
    }
    
    /// Removes a share URL from all profiles that contain it
    private func removeShareFromAllProfiles(shareURL: String) async throws {
        for profile in profileManager.profiles {
            if var associatedShares = profile.associatedNetworkShares,
               associatedShares.contains(shareURL) {
                
                var updatedProfile = profile
                associatedShares.removeAll { $0 == shareURL }
                updatedProfile.associatedNetworkShares = associatedShares
                
                try await profileManager.updateProfile(updatedProfile)
                logger.info("Removed share '\(shareURL)' from profile '\(profile.displayName)'.")
            }
        }
    }
}

// MARK: - Preview

struct AddShareView_Previews: PreviewProvider {
    static let mockMounter = Mounter() // Placeholder
    static let mockProfileManager = AuthProfileManager.shared
    
    // Pre-populate manager for preview
    static let profile1 = AuthProfile(displayName: "Test Profile 1", username: "test1")
    static let profile2 = AuthProfile(displayName: "Test Profile 2", username: "test2", useKerberos: true, kerberosRealm: "EXAMPLE.COM")
    static let mockShare = Share.createShare(networkShare: "smb://server/share", authType: .pwd, mountStatus: .unmounted, shareDisplayName: "Test Share")

    static var previews: some View {
        // Need a dummy binding for isPresented
        @State var isPresented = true
        
        // Preview for adding new share
        AddShareView(
            isPresented: $isPresented,
            mounter: mockMounter,
            profileManager: mockProfileManager,
            onSave: { print("Preview Save Tapped") }
        )
        .onAppear {
            mockProfileManager.profiles = [profile1, profile2]
        }
        .previewDisplayName("Add New Share")
        
        // Preview for editing existing share
        AddShareView(
            isPresented: $isPresented,
            mounter: mockMounter,
            profileManager: mockProfileManager,
            existingShare: mockShare,
            onSave: { print("Preview Update Tapped") }
        )
        .onAppear {
            mockProfileManager.profiles = [profile1, profile2]
        }
        .previewDisplayName("Edit Existing Share")
    }
}
