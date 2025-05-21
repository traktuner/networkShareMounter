import SwiftUI
import OSLog

// MARK: - Detail Column View

/// View for the right detail column in AuthenticationView.
/// Shows selected profile details or a placeholder.
struct DetailColumnView: View {
    // Dependencies
    let selectedProfileID: String?
    @ObservedObject var profileManager: AuthProfileManager // Needs AuthProfile definition
    let currentAssociatedShares: [Share] // Needs Share definition
    
    // Actions passed down to ProfileDetailView
    var onEditProfile: (AuthProfile) -> Void
    var onRefreshTicket: (AuthProfile) -> Void 
    
    // Logger
    private static var logger = Logger.authenticationView // Assuming this logger is accessible

    var body: some View {
        ScrollView {
            Group {
                // Find the profile based on ID
                let selectedProfile = profileManager.profiles.first { $0.id == selectedProfileID }

                if let profile = selectedProfile {
                    // Display profile details
                    ProfileDetailView(
                        profile: profile,
                        associatedShares: currentAssociatedShares,
                        onEditProfile: { onEditProfile(profile) }, 
                        onRefreshTicket: { onRefreshTicket(profile) } 
                    )
                } else {
                    // Display placeholder if no profile is selected or found
                    ProfileDetailPlaceholderView()
                }
            }
            .padding(20) // Move the padding to the content inside the ScrollView
        }
        // Add a subtle background to match styling in other views
        .background(Color(.controlBackgroundColor))
        // Add a subtle border for consistent styling
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        // Make the column take available space
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Preview

struct DetailColumnView_Previews: PreviewProvider {
    // Mock data for preview
    static let mockProfileManager = AuthProfileManager.shared // Use shared for preview ease?
    static let mockMounter = Mounter() // Placeholder
    
    // Create some mock profiles and shares for different states
    // This setup might need refinement based on actual initializers and data
    static let profile1 = AuthProfile(displayName: "Test Profile 1", username: "test1")
    static let profile2 = AuthProfile(displayName: "Test Profile 2", username: "test2", useKerberos: true, kerberosRealm: "EXAMPLE.COM")
    static let share1 = Share.createShare(networkShare: "smb://server/share1", authType: .pwd, mountStatus: .unmounted)
    static let share2 = Share.createShare(networkShare: "smb://server/share2", authType: .pwd, mountStatus: .mounted)
    
    // Pre-populate manager for preview if needed
    // static let _ = Task { await mockProfileManager.addProfile(profile1, password: nil) }
    // static let _ = Task { await mockProfileManager.addProfile(profile2, password: nil) }

    static var previews: some View {
        // Preview with a profile selected
        DetailColumnView(
            selectedProfileID: profile1.id,
            profileManager: mockProfileManager,
            currentAssociatedShares: [share1, share2],
            onEditProfile: { _ in print("Preview Edit") },
            onRefreshTicket: { _ in print("Preview Refresh") }
        )
        .previewDisplayName("Profile Selected")
        .onAppear {
             // Add profile1 to manager for preview if not done globally
             mockProfileManager.profiles = [profile1]
        }

        // Preview with no profile selected
        DetailColumnView(
            selectedProfileID: nil,
            profileManager: mockProfileManager,
            currentAssociatedShares: [],
            onEditProfile: { _ in print("Preview Edit") },
            onRefreshTicket: { _ in print("Preview Refresh") }
        )
        .previewDisplayName("No Profile Selected")
    }
}
