import SwiftUI
import OSLog
import dogeADAuth // For KlistUtil - Assuming it's here

// MARK: - Profile Row View

/// View for displaying a single row in the profile list.
struct ProfileRowView: View {
    // Dependencies
    @ObservedObject var profileManager: AuthProfileManager
    let profileId: String
    
    // Computed property to get the current profile
    private var profile: AuthProfile {
        profileManager.getProfile(by: profileId) ?? AuthProfile(displayName: "Unbekannt")
    }
    
    // Check if this is a default realm profile
    private var isDefaultProfile: Bool {
        profileManager.isDefaultRealmProfile(profile)
    }
    
    // State to hold the result of the Kerberos ticket check
    @State private var ticketStatus: TicketStatus = .unknown

    // Logger
    private static var logger = Logger.authenticationView // Assuming this logger is accessible
    
    var body: some View {
        HStack(spacing: 10) { // Increase spacing between elements
            // Profile Icon
            Image(systemName: profile.symbolName ?? "person.circle") 
                .foregroundColor(.white)
                .padding(6)
                .background(
                    Circle()
                        .fill(profile.symbolColor)
                        .frame(width: 28, height: 28)
                )
            
            // Profile Name and Details
            VStack(alignment: .leading, spacing: 4) { // Add consistent spacing
                HStack {
                    Text(profile.displayName) 
                        .font(.headline)
                    
                    // Show indicator for default realm profile
                    if isDefaultProfile {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .help("Standard-Kerberos-Profil (nicht löschbar)")
                    }
                }
                
                if profile.useKerberos {
                    HStack(spacing: 4) {
                        Text("Kerberos:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(profile.kerberosRealm ?? "N/A")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color(.controlBackgroundColor))
                            .cornerRadius(3)
                    }
                } else {
                    Text(profile.username ?? "N/A")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            // Kerberos Ticket Status Indicator (only if using Kerberos)
            if profile.useKerberos {
                Circle()
                    .fill(ticketStatus.color)
                    .frame(width: 10, height: 10) // Increase size slightly for better visibility
                    .help(ticketStatus.helpText)
            }
        }
        .padding(.vertical, 6) // Add consistent vertical padding
        .task(id: profile.id) {
            // Check ticket status for this profile
            await checkTicketStatus()
        }
    }
    
    // Check if a Kerberos ticket exists for this profile
    private func checkTicketStatus() async {
        // Use the global ticket status checker
        let status = await checkKerberosTicketStatus(for: profile)
        
        // Update the status on the main thread
        await MainActor.run {
            ticketStatus = status
        }
        
        Self.logger.debug("(RowView) Ticket status for profile '\(profile.displayName)': \(status.displayText)")
    }
}

// MARK: - Preview

struct ProfileRowView_Previews: PreviewProvider {
    static let mockProfileManager = AuthProfileManager.shared
    static let profile1 = AuthProfile(displayName: "Test Profile 1", username: "test1")
    static let profile2 = AuthProfile(displayName: "Test Profile 2", username: "test2", useKerberos: true, kerberosRealm: "EXAMPLE.COM")
    
    static var previews: some View {
        // Preview for non-Kerberos profile
        ProfileRowView(profileManager: mockProfileManager, profileId: profile1.id)
            .padding()
            .previewDisplayName("Standard Profile")
            .onAppear {
                mockProfileManager.profiles = [profile1]
            }

        // Preview for Kerberos profile
        ProfileRowView(profileManager: mockProfileManager, profileId: profile2.id)
            .padding()
            .previewDisplayName("Kerberos Profile")
            .onAppear {
                mockProfileManager.profiles = [profile2]
            }
    }
}

