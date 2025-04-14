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
        HStack {
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
            VStack(alignment: .leading) {
                Text(profile.displayName) 
                    .font(.headline)
                
                Text(profile.useKerberos ? "Kerberos: \(profile.kerberosRealm ?? "N/A")" : profile.username ?? "N/A")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Kerberos Ticket Status Indicator
            if profile.useKerberos {
                HStack {
                    if let status = ticketStatus {
                        Circle()
                            .fill(status ? .green : .red)
                            .frame(width: 8, height: 8)
                            .help(status ? "Aktives Kerberos-Ticket gefunden" : "Kein aktives Kerberos-Ticket gefunden")
                        Text(status ? "Ticket aktiv" : "Kein Ticket")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    } else {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 8, height: 8)
                        Text("Prüfe...")
                             .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        // Task to check ticket status
        .task(id: profile.id) { 
            await checkTicketStatus()
        }
    }
    
    /// Asynchronously checks the Kerberos ticket status for the current profile.
    private func checkTicketStatus() async {
        guard profile.useKerberos else {
            ticketStatus = nil 
            return
        }
        
        ticketStatus = nil // Reset before check
        
        guard let username = profile.username, !username.isEmpty, 
              let realm = profile.kerberosRealm, !realm.isEmpty else {
            Self.logger.warning("Cannot check Kerberos ticket for profile '\(profile.displayName)': Missing username or realm.")
            ticketStatus = false 
            return
        }
        
        let principalToCheck = "\(username)@\(realm.uppercased())"
        Self.logger.debug("Checking Kerberos ticket for principal: \(principalToCheck)")

        // Assuming KlistUtil and its klist() method are available
        let klistUtil = KlistUtil() 
        let activeTickets = await klistUtil.klist() 
        
        let hasActiveTicket = activeTickets.contains { ticket in
            ticket.principal.caseInsensitiveCompare(principalToCheck) == .orderedSame
        }
        
        ticketStatus = hasActiveTicket
        Self.logger.debug("Kerberos ticket status for \(principalToCheck): \(hasActiveTicket)")
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
