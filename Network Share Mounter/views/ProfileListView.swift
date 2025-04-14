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
                // Check if profiles are empty
                if profileManager.profiles.isEmpty {
                    Text("Keine Profile definiert.")
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding()
                } else {
                    ForEach(profileManager.profiles) { profile in
                        ProfileRowView(profile: profile)
                            .tag(profile.id)
                            .contextMenu {
                                Button("Bearbeiten") {
                                    onEditProfile(profile)
                                }
                                Button("Löschen") {
                                    // Removal is handled by parent via onRemoveProfile closure
                                    onRemoveProfile(profile)
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
            // Use standard list style for macOS
            .listStyle(.inset(alternatesRowBackgrounds: true))
            
            Divider() // Add a divider above the toolbar
            
            // Toolbar for Add/Remove buttons
            HStack {
                Button {
                    onAddProfile()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Neues Profil hinzufügen")
                .buttonStyle(.borderless) // Use borderless for toolbar look
                
                Button {
                    if let selectedID = selectedProfileID,
                       let profileToRemove = profileManager.profiles.first(where: { $0.id == selectedID }) {
                        onRemoveProfile(profileToRemove)
                    }
                } label: {
                    Image(systemName: "minus")
                }
                .help("Ausgewähltes Profil entfernen")
                .disabled(selectedProfileID == nil)
                .buttonStyle(.borderless)
                
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            // Add a subtle background to the toolbar area
            .background(.bar)
        }
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
