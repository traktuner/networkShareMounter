import SwiftUI

/// View for configuring network shares
struct NetworkSharesView: View {
    // Beispiel-Daten für das Design
    @State private var shares = [
        NetworkShare(
            id: UUID(),
            name: "Dokumente",
            url: "smb://server.example.com/documents",
            isMounted: true,
            profileName: "Büro", 
            profileSymbol: "building.2", 
            profileColor: .blue
        ),
        NetworkShare(
            id: UUID(),
            name: "Projekte",
            url: "smb://server.example.com/projects",
            isMounted: false,
            profileName: "Home-Office", 
            profileSymbol: "house", 
            profileColor: .green
        ),
        NetworkShare(
            id: UUID(),
            name: "Arbeitsgruppe",
            url: "smb://teamserver.example.com/shared",
            isMounted: false,
            profileName: nil, 
            profileSymbol: nil, 
            profileColor: nil
        )
    ]
    
    @State private var selectedShareID: UUID?
    @State private var showAddSheet = false
    @State private var showProfileSelector = false
    @State private var shareToAssignProfile: NetworkShare?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header description
            Text("Konfigurieren Sie die Netzwerk-Shares, die Sie automatisch verbinden möchten.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            // List of shares with simple layout
            VStack(spacing: 0) {
                ForEach(shares) { share in
                    HStack {
                        HStack(spacing: 6) {
                            // Show associated profile icon if a profile is linked
                            if let profileSymbol = share.profileSymbol,
                               let profileColor = share.profileColor {
                                Image(systemName: profileSymbol)
                                    .foregroundColor(.white)
                                    .background(
                                        Circle()
                                            .fill(profileColor)
                                            .frame(width: 24, height: 24)
                                    )
                                    .help(share.profileName ?? "")
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(share.name)
                                    .font(.headline)
                                Text(share.url)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        // Associated profile name
                        if let profileName = share.profileName {
                            Text(profileName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                        }
                        
                        // Simple status indicator
                        Circle()
                            .fill(share.isMounted ? Color.green : Color.gray)
                            .frame(width: 10, height: 10)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedShareID = share.id
                    }
                    .contextMenu {
                        Button(share.isMounted ? "Trennen" : "Verbinden") {
                            if let index = shares.firstIndex(where: { $0.id == share.id }) {
                                shares[index].isMounted.toggle()
                            }
                        }
                        
                        Button(share.profileName == nil ? "Profil zuweisen..." : "Profil ändern...") {
                            shareToAssignProfile = share
                            showProfileSelector = true
                        }
                        
                        if share.profileName != nil {
                            Button("Profilzuweisung aufheben") {
                                if let index = shares.firstIndex(where: { $0.id == share.id }) {
                                    shares[index].profileName = nil
                                    shares[index].profileSymbol = nil
                                    shares[index].profileColor = nil
                                }
                            }
                        }
                        
                        Divider()
                        
                        Button("Löschen") {
                            if let index = shares.firstIndex(where: { $0.id == share.id }) {
                                shares.remove(at: index)
                            }
                            if selectedShareID == share.id {
                                selectedShareID = nil
                            }
                        }
                    }
                    .background(selectedShareID == share.id ? Color.accentColor.opacity(0.1) : Color.clear)
                    
                    if share.id != shares.last?.id {
                        Divider()
                    }
                }
                
                if shares.isEmpty {
                    VStack(spacing: 8) {
                        Text("Keine Netzwerk-Shares konfiguriert")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("Klicken Sie auf '+', um einen neuen Share hinzuzufügen")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .padding()
                }
            }
            .background(Color(.controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
            
            // Bottom toolbar with action buttons
            HStack {
                Button(action: { showAddSheet = true }) {
                    Image(systemName: "plus")
                }
                .help("Hinzufügen")
                
                Button(action: {
                    if let selectedID = selectedShareID,
                       let index = shares.firstIndex(where: { $0.id == selectedID }) {
                        shares.remove(at: index)
                        selectedShareID = nil
                    }
                }) {
                    Image(systemName: "minus")
                }
                .help("Entfernen")
                .disabled(selectedShareID == nil)
                
                Button(action: {
                    if let selectedID = selectedShareID,
                       let share = shares.first(where: { $0.id == selectedID }) {
                        shareToAssignProfile = share
                        showProfileSelector = true
                    }
                }) {
                    Image(systemName: "person.badge.key")
                }
                .help("Profil zuweisen")
                .disabled(selectedShareID == nil)
                
                Spacer()
                
                Button(action: {
                    if let selectedID = selectedShareID,
                       let index = shares.firstIndex(where: { $0.id == selectedID }) {
                        shares[index].isMounted.toggle()
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.up.arrow.down")
                        if let selectedID = selectedShareID,
                           let share = shares.first(where: { $0.id == selectedID }) {
                            Text(share.isMounted ? "Trennen" : "Verbinden")
                        } else {
                            Text("Verbinden")
                        }
                    }
                }
                .disabled(selectedShareID == nil)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .sheet(isPresented: $showAddSheet) {
            AddShareView(isPresented: $showAddSheet, onSave: { newShare in
                shares.append(newShare)
                selectedShareID = newShare.id
            })
        }
        .sheet(isPresented: $showProfileSelector) {
            if let share = shareToAssignProfile {
                ProfileSelectorView(
                    isPresented: $showProfileSelector,
                    onProfileSelected: { profileName, profileSymbol, profileColor in
                        if let index = shares.firstIndex(where: { $0.id == share.id }) {
                            shares[index].profileName = profileName
                            shares[index].profileSymbol = profileSymbol
                            shares[index].profileColor = profileColor
                        }
                    }
                )
            }
        }
    }
}

/// Model representing a network share for design
struct NetworkShare: Identifiable {
    var id: UUID
    var name: String
    var url: String
    var isMounted: Bool
    var profileName: String?
    var profileSymbol: String?
    var profileColor: Color?
}

/// View for adding a new share
struct AddShareView: View {
    @Binding var isPresented: Bool
    var onSave: (NetworkShare) -> Void
    
    @State private var shareName: String = ""
    @State private var shareURL: String = ""
    @State private var selectedProfileName: String? = nil
    
    // Beispiel Profile für die Design-Phase
    let availableProfiles = [
        (name: "Büro", symbol: "building.2", color: Color.blue),
        (name: "Home-Office", symbol: "house", color: Color.green)
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Neuen Network Share hinzufügen")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Name:")
                TextField("z.B. Arbeitsdokumente", text: $shareName)
                    .textFieldStyle(.roundedBorder)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Server-URL:")
                TextField("smb://server.example.com/share", text: $shareURL)
                    .textFieldStyle(.roundedBorder)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Profil zuweisen (optional):")
                
                Picker("Profil auswählen", selection: $selectedProfileName) {
                    Text("Keines").tag(nil as String?)
                    
                    ForEach(availableProfiles, id: \.name) { profile in
                        HStack {
                            Image(systemName: profile.symbol)
                                .foregroundColor(.white)
                                .padding(4)
                                .background(
                                    Circle()
                                        .fill(profile.color)
                                        .frame(width: 20, height: 20)
                                )
                            Text(profile.name)
                        }
                        .tag(profile.name as String?)
                    }
                }
                .pickerStyle(.menu)
            }
            
            Spacer()
            
            HStack {
                Button("Abbrechen") {
                    isPresented = false
                }
                
                Spacer()
                
                Button("Hinzufügen") {
                    // Find the selected profile tuple based on the name, if a name is selected
                    let selectedProfileTuple = availableProfiles.first { $0.name == selectedProfileName }
                    
                    // Create the new share regardless of profile selection
                    let newShare = NetworkShare(
                        id: UUID(),
                        name: shareName,
                        url: shareURL,
                        isMounted: false,
                        profileName: selectedProfileTuple?.name,
                        profileSymbol: selectedProfileTuple?.symbol,
                        profileColor: selectedProfileTuple?.color
                    )
                    
                    // Save and dismiss
                    onSave(newShare)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(shareName.isEmpty || shareURL.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 400, height: 300)
    }
}

/// View for selecting an auth profile
struct ProfileSelectorView: View {
    @Binding var isPresented: Bool
    var onProfileSelected: (String, String, Color) -> Void
    
    // Beispiel Profile für die Design-Phase
    let availableProfiles = [
        (name: "Büro", symbol: "building.2", color: Color.blue),
        (name: "Home-Office", symbol: "house", color: Color.green),
        (name: "Universität", symbol: "graduationcap", color: Color.purple)
    ]
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Profil auswählen")
                .font(.headline)
            
            List {
                ForEach(availableProfiles, id: \.name) { profile in
                    HStack {
                        Image(systemName: profile.symbol)
                            .foregroundColor(.white)
                            .padding(6)
                            .background(
                                Circle()
                                    .fill(profile.color)
                                    .frame(width: 28, height: 28)
                            )
                        
                        Text(profile.name)
                            .font(.headline)
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onProfileSelected(profile.name, profile.symbol, profile.color)
                        isPresented = false
                    }
                }
            }
            
            Button("Abbrechen") {
                isPresented = false
            }
        }
        .padding(20)
        .frame(width: 300, height: 300)
    }
}

#Preview {
    NetworkSharesView()
} 