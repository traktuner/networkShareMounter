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
        VStack(spacing: 0) {
            // Scrollable content area
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(windowTitle)
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text(isEditing ? "Bearbeiten Sie die Einstellungen für diesen Netzwerk-Share." : "Fügen Sie einen neuen Netzwerk-Share hinzu.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Share Details Section
                    GroupBox {
                        VStack(alignment: .leading, spacing: 16) {
                            shareDetailsFields
                        }
                        .padding(16)
                    } label: {
                        Label("Share-Details", systemImage: "externaldrive")
                            .font(.headline)
                    }
                    
                    // Authentication Section
                    GroupBox {
                        VStack(alignment: .leading, spacing: 16) {
                            authenticationSection
                        }
                        .padding(16)
                    } label: {
                        Label("Authentifizierung", systemImage: "person.badge.key")
                            .font(.headline)
                    }
                }
                .padding(24)
            }
            
            // Bottom buttons bar
            Divider()
            
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
            .padding(20)
        }
        .frame(minWidth: 500, minHeight: 450)
        .onAppear {
            setupForEditing()
        }
    }
    
    // MARK: - UI Components
    
    @ViewBuilder
    private var shareDetailsFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Netzwerkpfad:")
                    .frame(width: 100, alignment: .trailing)
                TextField("smb://server/pfad", text: $networkShare)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .disabled(isEditing && (existingShare?.managed == true))
            }
            
            HStack {
                Text("Anzeigename:")
                    .frame(width: 100, alignment: .trailing)
                TextField("Optional", text: $shareDisplayName)
                    .textFieldStyle(.roundedBorder)
            }
            
            if isEditing && (existingShare?.managed == true) {
                HStack {
                    Image(systemName: "info.circle.fill")
                        .foregroundColor(.blue)
                        .font(.caption)
                    Text("Dieser Share wird zentral verwaltet und kann nicht geändert werden.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    @ViewBuilder
    private var authenticationSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if profileManager.profiles.isEmpty && !isEditing {
                // Loading state
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Profile werden geladen...")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Zugehöriges Profil")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Picker("Profil auswählen", selection: $selectedProfileID) {
                        // Add "None" option
                        Label("Kein Profil (Standard-System)", systemImage: "gear")
                            .tag(String?.none)
                        
                        if !profileManager.profiles.isEmpty {
                            Divider()
                            
                            // List available profiles
                            ForEach(profileManager.profiles) { profile in
                                Label {
                                    Text(profile.displayName)
                                } icon: {
                                    Image(systemName: profile.symbolName ?? "person.circle")
                                        .foregroundColor(.white)
                                        .font(.caption)
                                        .frame(width: 16, height: 16)
                                        .background(
                                            Circle()
                                                .fill(profile.symbolColor)
                                        )
                                }
                                .tag(profile.id as String?)
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Help text
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Wählen Sie ein Authentifizierungsprofil für diesen Share aus.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("Ohne Profil werden Standard-Systemmechanismen (z.B. Kerberos) verwendet.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
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
            authType: (selectedProfileID ?? "").isEmpty ? .krb : .pwd, // Safe unwrap and check with isEmpty
            mountStatus: .unmounted,
            managed: false, // User-added shares are not managed
            shareDisplayName: displayName,
            authProfileID: (selectedProfileID ?? "").isEmpty ? nil : selectedProfileID // Safe unwrap before use
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
