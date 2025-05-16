import SwiftUI
import OSLog
import dogeADAuth // For KlistUtil - Assuming it's here

// MARK: - Profile Row View

/// View for displaying a single row in the profile list.
struct ProfileRowView: View {
    let profile: AuthProfile
    
    // State to hold the result of the Kerberos ticket check
    @State private var ticketStatus: Bool? = nil // nil: unknown, true: active, false: inactive

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
                Text(profile.displayName) 
                    .font(.headline)
                
                Text(profile.useKerberos ? "Kerberos: \(profile.kerberosRealm ?? "N/A")" : profile.username ?? "N/A")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Kerberos Ticket Status Indicator (only if using Kerberos)
            if profile.useKerberos {
                Circle()
                    .fill(ticketStatus == true ? Color.green : 
                          ticketStatus == false ? Color.red : Color.gray)
                    .frame(width: 10, height: 10) // Increase size slightly for better visibility
                    .help(ticketStatus == true ? "Kerberos-Ticket aktiv" : 
                          ticketStatus == false ? "Kein gültiges Kerberos-Ticket" : "Ticket-Status unbekannt")
            }
        }
        .padding(.vertical, 6) // Add consistent vertical padding
        .task {
            // Only check ticket status if using Kerberos
            if profile.useKerberos {
                await checkTicketStatus()
            }
        }
    }
    
    // Check if a Kerberos ticket exists for this profile
    private func checkTicketStatus() async {
        // Reset to unknown initially
        ticketStatus = nil
        
        // Only check for Kerberos profiles
        guard profile.useKerberos, let realm = profile.kerberosRealm else {
            return
        }
        
        do {
            // Call the KlistUtil to check if a ticket exists
//            let hasTicket = try await KlistUtil.shared.hasActiveTicketForRealm(realm: realm)
            let hasTicket = true
            
            // Update the status on the main thread
            await MainActor.run {
                ticketStatus = hasTicket
            }
        } catch {
            Self.logger.error("Failed to check Kerberos ticket status: \(error.localizedDescription)")
            
            // Set status to false on error
            await MainActor.run {
                ticketStatus = false
            }
        }
    }
}

// MARK: - Preview

struct ProfileRowView_Previews: PreviewProvider {
    static let profile1 = AuthProfile(displayName: "Test Profile 1", username: "test1")
    static let profile2 = AuthProfile(displayName: "Test Profile 2", username: "test2", useKerberos: true, kerberosRealm: "EXAMPLE.COM")
    
    static var previews: some View {
        // Preview for non-Kerberos profile
        ProfileRowView(profile: profile1)
            .padding()
            .previewDisplayName("Standard Profile")

        // Preview for Kerberos profile
        ProfileRowView(profile: profile2)
            .padding()
            .previewDisplayName("Kerberos Profile")
    }
}
