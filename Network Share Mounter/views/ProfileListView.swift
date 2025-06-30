import SwiftUI
import OSLog

// MARK: - Profile List View

/// View for displaying the list of authentication profiles.
struct ProfileListView: View {
    // Dependencies
    @ObservedObject var profileManager: AuthProfileManager
    @Binding var selectedProfileID: String?
    
    // Actions triggered in the parent view
    var onAddProfile: () -> Void
    var onEditProfile: (AuthProfile) -> Void
    var onRemoveProfile: (AuthProfile) -> Void 
    var onRefreshTicket: (AuthProfile) -> Void

    var body: some View {
        VStack(spacing: 0) { // Use spacing 0 to connect List and Toolbar visually
            // Profile List
            List(selection: $selectedProfileID) {
                if profileManager.profiles.isEmpty {
                    VStack(alignment: .center, spacing: 12) {
                        // Add icon for better visual appeal
                        Image(systemName: "person.badge.key.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary.opacity(0.6))
                            .padding(.bottom, 8)
                        
                        Text("Keine Profile definiert.")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            
                        Text("Klicken Sie auf '+', um ein neues Profil zu erstellen.")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 150, alignment: .center)
                    .padding()
                } else {
                    // Generate rows for each profile
                    ForEach(profileManager.profiles) { profile in
                        ProfileRowView(profileManager: profileManager, profileId: profile.id)
                            .tag(profile.id)
                            .padding(.vertical, 1) // Add consistent row spacing
                            .contextMenu {
                                Button("Bearbeiten") {
                                    onEditProfile(profile)
                                }
                                
                                // Only show delete option if it's not a default realm profile
                                if !profileManager.isDefaultRealmProfile(profile) {
                                    Button("Löschen") {
                                        onRemoveProfile(profile)
                                    }
                                } else {
                                    Button("Löschen") {
                                        // Disabled button with explanation
                                    }
                                    .disabled(true)
                                    .help("Standard-Kerberos-Profile können nicht gelöscht werden")
                                }
                                
                                if profile.useKerberos {
                                    Divider()
                                    Button("Ticket aktualisieren") {
                                        onRefreshTicket(profile)
                                    }
                                }
                            }
                    }
                }
            }
            .listStyle(.bordered) // Use bordered style for better appearance
            .frame(minHeight: 100) // Ensure list has a minimum height
            
            // Bottom toolbar with actions
            HStack {
                Button(action: onAddProfile) {
                    Image(systemName: "plus")
                }
                .help("Profil hinzufügen")
                
                Button {
                    if let selectedID = selectedProfileID,
                       let profileToRemove = profileManager.getProfile(by: selectedID) {
                        onRemoveProfile(profileToRemove)
                    }
                } label: {
                    Image(systemName: "minus")
                }
                .help({
                    guard let selectedID = selectedProfileID,
                          let profile = profileManager.getProfile(by: selectedID) else {
                        return "Profil entfernen"
                    }
                    return profileManager.isDefaultRealmProfile(profile) ? 
                           "Standard-Kerberos-Profile können nicht gelöscht werden" : "Profil entfernen"
                }())
                .disabled({
                    guard let selectedID = selectedProfileID,
                          let profile = profileManager.getProfile(by: selectedID) else {
                        return true
                    }
                    return profileManager.isDefaultRealmProfile(profile)
                }())
                
                Spacer()
                
                // Refresh button for Kerberos tickets
                Button {
                    if let selectedID = selectedProfileID,
                       let profile = profileManager.getProfile(by: selectedID),
                       profile.useKerberos {
                        onRefreshTicket(profile)
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Kerberos-Ticket aktualisieren")
                .disabled(selectedProfileID == nil || 
                           (selectedProfileID != nil && 
                            profileManager.getProfile(by: selectedProfileID!)?.useKerberos != true))
            }
            .padding(8)
            .background(Color(.controlBackgroundColor))
        }
        // Add background to match DetailColumnView
        .background(Color(.controlBackgroundColor))
        // Add a subtle border for consistent styling
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        // Add a small amount of padding to the right side to match the DetailColumnView spacing
        .padding(.trailing, 1)
    }
}

// MARK: - Preview

struct ProfileListView_Previews: PreviewProvider {
    static let mockProfileManager = AuthProfileManager.shared
    static let profile1 = AuthProfile(displayName: "Test Profile 1", username: "test1")
    static let profile2 = AuthProfile(displayName: "Test Profile 2", username: "test2", useKerberos: true, kerberosRealm: "EXAMPLE.COM")

    // Use @State for the binding in the preview
    @State static var previewSelectedProfileID: String? = profile1.id

    static var previews: some View {
        // Preview with profiles
        ProfileListView(
            profileManager: mockProfileManager,
            selectedProfileID: $previewSelectedProfileID,
            onAddProfile: { print("Preview Add") },
            onEditProfile: { _ in print("Preview Edit") },
            onRemoveProfile: { _ in print("Preview Remove") },
            onRefreshTicket: { _ in print("Preview Refresh") }
        )
        .onAppear {
            mockProfileManager.profiles = [profile1, profile2]
        }
        .frame(width: 300, height: 400)
        .previewDisplayName("With Profiles")
        
        // Preview with empty list
        ProfileListView(
            profileManager: mockProfileManager,
            selectedProfileID: .constant(nil),
            onAddProfile: { print("Preview Add") },
            onEditProfile: { _ in print("Preview Edit") },
            onRemoveProfile: { _ in print("Preview Remove") },
            onRefreshTicket: { _ in print("Preview Refresh") }
        )
        .onAppear {
             mockProfileManager.profiles = []
         }
        .frame(width: 300, height: 400)
        .previewDisplayName("Empty List")
    }
}
