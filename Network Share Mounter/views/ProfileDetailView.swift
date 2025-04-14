import SwiftUI
import OSLog
import dogeADAuth // For KlistUtil - Assuming it's here

// MARK: - Profile Detail View

struct ProfileDetailView: View {
    // Dependencies
    let profile: AuthProfile
    let associatedShares: [Share] 
    let onEditProfile: () -> Void
    let onRefreshTicket: () -> Void
    
    // Access the Mounter (needed for share actions)
    // Assuming appDelegate.mounter is globally accessible or passed differently
    private let mounter = appDelegate.mounter!
    
    // State for Kerberos ticket status
    @State private var ticketStatus: Bool? = nil

    // Logger
    private static var logger = Logger.authenticationView // Assuming this logger is accessible

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Profile Header
            profileHeader
            
            Divider()
            
            // Authentication Information Section
            authInfoSection
            
            Divider()
            
            // Associated Shares Section
            associatedSharesSection
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Task to check ticket status
        .task(id: profile.id) { 
            await checkTicketStatus()
        }
    }

    // MARK: Subviews for Body
    
    private var profileHeader: some View {
        HStack {
            Image(systemName: profile.symbolName ?? "person.circle")
                .foregroundColor(.white)
                .padding(8)
                .background(
                    Circle()
                        .fill(profile.symbolColor)
                        .frame(width: 40, height: 40)
                )
            
            Text(profile.displayName)
                .font(.title2)
                .fontWeight(.semibold)
            
            Spacer()
            
            Button("Bearbeiten") {
                onEditProfile()
            }
        }
    }
    
    private var authInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Anmeldedaten")
                .font(.headline)
            
            if profile.useKerberos {
                 HStack {
                    VStack(alignment: .leading) {
                        Text("Kerberos-Authentifizierung")
                            .fontWeight(.medium)
                        Text("Realm: \(profile.kerberosRealm ?? "N/A")")
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    kerberosStatusView // Extracted Kerberos status
                }
            } else {
                standardAuthView // Extracted standard auth info
            }
        }
    }
    
    // View for Kerberos Status Indicator and Refresh Button
    private var kerberosStatusView: some View {
        VStack(alignment: .trailing) {
             HStack {
                if let status = ticketStatus {
                    Circle()
                        .fill(status ? .green : .red)
                        .frame(width: 10, height: 10)
                        .help(status ? "Aktives Kerberos-Ticket gefunden" : "Kein aktives Kerberos-Ticket gefunden")
                    Text(status ? "Ticket gültig" : "Kein gültiges Ticket")
                } else {
                    ProgressView().scaleEffect(0.5).frame(width: 10, height: 10)
                    Text("Prüfe...")
                }
            }
            .font(.caption)
            
            Button("Ticket aktualisieren") {
                Self.logger.info("Ticket refresh requested for profile \(profile.displayName)")
                onRefreshTicket() // Call original action if needed
                // Trigger a re-check after attempting refresh
                ticketStatus = nil 
            }
            .disabled(ticketStatus != false) // Disable if unknown or already valid
        }
    }
    
    // View for Standard Username/Password Display
    private var standardAuthView: some View {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
            GridRow {
                Text("Benutzername:")
                Text(profile.username ?? "N/A")
            }
            GridRow {
                Text("Passwort:")
                Text("Gespeichert im Schlüsselbund")
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
    }
    
    private var associatedSharesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
             HStack {
                Text("Zugeordnete Shares (\(associatedShares.count))")
                    .font(.headline)
                    .padding(.bottom, 4)
                Spacer()
                // Placeholder button - needs implementation if desired
                // Button("Verknüpfen...") { ... }.font(.caption)
            }
            
            if associatedShares.isEmpty {
                Text("Diesem Profil sind keine Shares zugeordnet.")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical)
            } else {
                // Use a List for better scrollability if many shares
                List(associatedShares) { share in
                    associatedShareRow(share)
                }
                .listStyle(.plain) // Use plain style to avoid extra borders
                .frame(minHeight: 100, maxHeight: 300) // Adjust height as needed
            }
        }
    }
    
    // View for a single associated share row
    @ViewBuilder
    private func associatedShareRow(_ share: Share) -> some View {
         HStack {
            Image(systemName: "externaldrive")
                .foregroundColor(.secondary)
            Text(share.shareDisplayName ?? share.networkShare)
            Spacer()
            Circle()
                 .fill(mountStatusColor(for: share.mountStatus))
                 .frame(width: 8, height: 8)
                 .help(share.mountStatus.rawValue) // Add tooltip for status
            Text(share.mountStatus.rawValue)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button(share.mountStatus == .mounted ? "Trennen" : "Verbinden") {
                handleMountToggle(for: share)
            }
            Button("Profilzuweisung aufheben") {
                 handleUnassignShare(share)
            }
        }
    }
    
    // --- Helper Functions ---
    
    /// Asynchronously checks the Kerberos ticket status for the current profile.
    private func checkTicketStatus() async {
        guard profile.useKerberos else {
            ticketStatus = nil 
            return
        }
        ticketStatus = nil 
        guard let username = profile.username, !username.isEmpty, 
              let realm = profile.kerberosRealm, !realm.isEmpty else {
            Self.logger.warning("Cannot check Kerberos ticket for profile '\(profile.displayName)': Missing username or realm.")
            ticketStatus = false 
            return
        }
        let principalToCheck = "\(username)@\(realm.uppercased())"
        Self.logger.debug("(DetailView) Checking Kerberos ticket for principal: \(principalToCheck)")
        let klistUtil = KlistUtil() 
        let activeTickets = await klistUtil.klist() 
        let hasActiveTicket = activeTickets.contains { ticket in
            ticket.principal.caseInsensitiveCompare(principalToCheck) == .orderedSame
        }
        ticketStatus = hasActiveTicket
        Self.logger.debug("(DetailView) Kerberos ticket status for \(principalToCheck): \(hasActiveTicket)")
    }
    
    /// Returns the appropriate color for the mount status indicator.
    private func mountStatusColor(for status: MountStatus) -> Color {
         switch status {
        case .mounted: return .green
        case .unmounted, .queued, .toBeMounted, .undefined, .userUnmounted: return .gray
        case .missingPassword, .invalidCredentials, .errorOnMount, .obstructingDirectory, .unreachable: return .red
        case .unknown: return .orange
        }
    }
    
    /// Handles the mount/unmount action from the context menu.
    private func handleMountToggle(for share: Share) {
        Task {
            if share.mountStatus == .mounted {
                await mounter.unmountShare(for: share)
            } else {
                await mounter.mountGivenShares(userTriggered: true, forShare: share.id)
            }
            // TODO: Consider how to refresh the associatedShares list if needed
            // This might require the parent view (AuthenticationView) to reload.
        }
    }
    
    /// Handles removing the profile assignment from a share.
    private func handleUnassignShare(_ share: Share) {
        // Placeholder for future implementation
        // Needs to interact with AuthProfileManager to remove share URL from profile's list
        // and potentially update the ShareManager if shares are persisted with profile info (which they aren't currently)
        Self.logger.info("Unassign share '\(share.networkShare)' from profile '\(profile.displayName)' requested (Not Implemented)")
        // Example (Conceptual - requires AuthProfileManager method):
        // Task {
        //     try? await AuthProfileManager.shared.removeShareAssociation(from: profile, shareURL: share.networkShare)
        // }
    }
}

// MARK: - Preview

struct ProfileDetailView_Previews: PreviewProvider {
    static let mockMounter = Mounter() // Placeholder
    
    static var profile1: AuthProfile {
        var p = AuthProfile(displayName: "Standard Profile", username: "user1")
        p.associatedNetworkShares = ["smb://server/share1"]
        p.symbolColor = .orange
        return p
    }
    static var profile2: AuthProfile {
         var p = AuthProfile(displayName: "Kerberos Profile", username: "user2", useKerberos: true, kerberosRealm: "REALM.COM")
         p.associatedNetworkShares = ["smb://server/share2", "smb://server/share3"]
         p.symbolColor = .purple
         return p
     }
     
    static let share1 = Share.createShare(networkShare: "smb://server/share1", authType: .pwd, mountStatus: .mounted)
    static let share2 = Share.createShare(networkShare: "smb://server/share2", authType: .krb, mountStatus: .unmounted)
    static let share3 = Share.createShare(networkShare: "smb://server/share3", authType: .krb, mountStatus: .errorOnMount)

    static var previews: some View {
        // Preview for standard profile
        ProfileDetailView(
            profile: profile1,
            associatedShares: [share1],
            onEditProfile: { print("Preview Edit") },
            onRefreshTicket: { print("Preview Refresh") }
        )
        .previewDisplayName("Standard Profile")

        // Preview for Kerberos profile
        ProfileDetailView(
            profile: profile2,
            associatedShares: [share2, share3],
            onEditProfile: { print("Preview Edit") },
            onRefreshTicket: { print("Preview Refresh") }
        )
        .previewDisplayName("Kerberos Profile")
    }
}
