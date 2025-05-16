import SwiftUI
import OSLog

// MARK: - Add Share View

/// A view presented as a sheet to add a new network share configuration.
struct AddShareView: View {
    // Dependencies & Callbacks
    @Binding var isPresented: Bool
    let mounter: Mounter // Needed to access ShareManager
    @ObservedObject var profileManager: AuthProfileManager // Needed for profile selection
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

    var body: some View {
        // Remove NavigationView, manage title and buttons manually
        // NavigationView {
            Form {
                // Manual Title
                Text("Neuen Share hinzufügen")
                    .font(.headline)
                    .padding(.bottom)
                
                Section("Share-Details") {
                    TextField("Netzwerkpfad (z.B. smb://server/pfad)", text: $networkShare)
                        .lineLimit(1)
                        .autocorrectionDisabled()
                        // Add more modifiers as needed (text content type, etc.)
                    
                    TextField("Anzeigename (optional)", text: $shareDisplayName)
                        .lineLimit(1)
                }
                
                Section("Authentifizierung") {
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
                    
                    Button("Speichern") {
                        Task {
                            await handleSaveChanges()
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
            try await mounter.shareManager.addShare(newShare)
            logger.info("Successfully added share '\(newShare.networkShare)' to ShareManager.")

            // 4. Update profile if one was selected
            if let profileID = selectedProfileID {
                guard let profile = profileManager.getProfile(by: profileID) else {
                    logger.error("Selected profile ID \(profileID) not found in ProfileManager.")
                    // Proceed with saving share, but log profile issue
                    // TODO: Maybe inform user?
                    return // Exit after logging error?
                }
                
                var updatedProfile = profile
                var updatedShares = updatedProfile.associatedNetworkShares ?? []
                
                // Avoid adding duplicates
                if !updatedShares.contains(newShare.networkShare) {
                    updatedShares.append(newShare.networkShare)
                    updatedProfile.associatedNetworkShares = updatedShares
                    
                    // Save the updated profile
                    try await profileManager.updateProfile(updatedProfile)
                    logger.info("Successfully associated share '\(newShare.networkShare)' with profile '\(updatedProfile.displayName)'.")
                } else {
                     logger.warning("Share '\(newShare.networkShare)' already associated with profile '\(profile.displayName)'.")
                }
            }
            
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
}

// MARK: - Preview

struct AddShareView_Previews: PreviewProvider {
    static let mockMounter = Mounter() // Placeholder
    static let mockProfileManager = AuthProfileManager.shared
    
    // Pre-populate manager for preview
    static let profile1 = AuthProfile(displayName: "Test Profile 1", username: "test1")
    static let profile2 = AuthProfile(displayName: "Test Profile 2", username: "test2", useKerberos: true, kerberosRealm: "EXAMPLE.COM")

    static var previews: some View {
        // Need a dummy binding for isPresented
        @State var isPresented = true
        
        AddShareView(
            isPresented: $isPresented,
            mounter: mockMounter,
            profileManager: mockProfileManager,
            onSave: { print("Preview Save Tapped") }
        )
        .onAppear {
            mockProfileManager.profiles = [profile1, profile2]
        }
    }
}
