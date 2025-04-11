//
//  GeneralSettingsView.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 10.04.25.
//  Copyright © 2024 RRZE. All rights reserved.
//

import SwiftUI
import OSLog // Add OSLog for logging

/// View for configuring authentication settings
struct AuthenticationView: View {
    // Use @StateObject for the singleton managers
    @StateObject private var profileManager = AuthProfileManager.shared

    // Use the ID type from the model
    @State private var selectedProfileID: String? // Changed from UUID to String (if AuthProfile.id is String)
    @State private var isAddingProfile = false
    @State private var isEditingProfile = false
    @State private var profileToEdit: AuthProfile?
    
    // State variable to hold shares for the selected profile
    @State private var currentAssociatedShares: [Share] = []
    
    // Access the Mounter
    private let mounter = appDelegate.mounter!

    var body: some View {
        // Outer VStack to place Header above the split view
        VStack(alignment: .leading, spacing: 0) { 
            
            // Header Section (now at the top level)
            HStack(spacing: 12) {
                Image(systemName: "person.badge.key") 
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Color.orange) 
                    .cornerRadius(6)
                    .frame(width: 32, height: 32)
                    
                VStack(alignment: .leading) {
                    Text("Authentifizierung") 
                        .font(.headline)
                        .fontWeight(.medium)
                    Text("Verwalten Sie hier Ihre Authentifizierungsprofile für Netzwerkverbindungen.") 
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer() 
            }
            .padding(12) // Internal padding
            .background(.quaternary.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(10)
        
            // Main structure using the extracted ProfileListView
            HStack(spacing: 0) {
                ProfileListView(
                    profileManager: profileManager, 
                    selectedProfileID: $selectedProfileID,
                    onAddProfile: { isAddingProfile = true },
                    onEditProfile: { profile in
                        profileToEdit = profile
                        isEditingProfile = true
                    },
                    onRemoveProfile: { profile in
                        Task {
                            try? await profileManager.removeProfile(profile)
                            if selectedProfileID == profile.id {
                                selectedProfileID = profileManager.profiles.first?.id
                            }
                        }
                    },
                    onRefreshTicket: { profile in
                        // TODO: Implement actual Kerberos ticket refresh logic
                        Logger.viewCycle.info("Ticket refresh requested for profile \(profile.displayName)")
                    }
                )
                .frame(width: 300)
                
                // Divider between columns
                Divider()
                
                // Right Detail Column
                ScrollView {
                    if let selectedID = selectedProfileID,
                       let profile = profileManager.profiles.first(where: { $0.id == selectedID }) {
                        // Pass the state variable holding the filtered shares
                        ProfileDetailView(
                            profile: profile,
                            associatedShares: currentAssociatedShares, // Pass the state variable
                            onEditProfile: {
                                profileToEdit = profile
                                isEditingProfile = true
                            },
                            onRefreshTicket: {
                                // TODO: Implement actual Kerberos ticket refresh logic
                                Logger.viewCycle.info("Ticket refresh requested for profile \(profile.displayName)")
                            }
                        )
                    } else {
                        VStack(alignment: .center) {
                            Text("Wählen Sie ein Profil aus oder erstellen Sie ein neues Profil")
                                .foregroundColor(.secondary)
                                // Center placeholder text vertically if needed
                                // .frame(maxHeight: .infinity) 
                        }
                        // Give the placeholder some padding and make it fill width
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(20) 
                    }
                }
                // Apply padding around the ScrollView content area
                .padding(20)
            } // End of Main HStack
        } // End of Outer VStack
        // Fetch associated shares when the selected profile changes
        .onChange(of: selectedProfileID) { _, newProfileID in
            Task {
                await loadAssociatedShares(for: newProfileID)
            }
        }
        .sheet(isPresented: $isAddingProfile) {
            ProfileEditorView(isPresented: $isAddingProfile, onSave: { newProfile, password in
                Task {
                    try? await profileManager.addProfile(newProfile, password: password)
                    selectedProfileID = newProfile.id
                }
            })
        }
        .sheet(isPresented: $isEditingProfile) {
            if let profile = profileToEdit {
                ProfileEditorView(
                    isPresented: $isEditingProfile,
                    existingProfile: profile,
                    onSave: { updatedProfile, password in
                        Task {
                            try? await profileManager.updateProfile(updatedProfile)
                            if let pwd = password, !pwd.isEmpty {
                                try? await profileManager.savePassword(for: updatedProfile, password: pwd)
                            }
                        }
                    }
                )
            }
        }
    }
    
    /// Asynchronously loads shares associated with the given profile ID.
    private func loadAssociatedShares(for profileID: String?) async {
        guard let id = profileID else {
            currentAssociatedShares = []
            return
        }
        let allShares = await mounter.shareManager.allShares
        currentAssociatedShares = allShares.filter { $0.profileID == id }
        Logger.viewCycle.info("Loaded \(currentAssociatedShares.count) shares associated with profile ID \(id)")
    }
}

// MARK: - Subviews

/// View for displaying the list of authentication profiles.
struct ProfileListView: View {
    // Use ObservedObject for managers passed from the parent
    @ObservedObject var profileManager: AuthProfileManager
    @Binding var selectedProfileID: String?
    
    // Actions to be triggered in the parent view
    var onAddProfile: () -> Void
    var onEditProfile: (AuthProfile) -> Void
    var onRemoveProfile: (AuthProfile) -> Void // Action for '-' button
    var onRefreshTicket: (AuthProfile) -> Void // Action for context menu

    var body: some View {
        VStack {
            List(selection: $selectedProfileID) {
                ForEach(profileManager.profiles) { profile in
                    ProfileRowView(profile: profile)
                        .tag(profile.id)
                        .contextMenu {
                            Button("Bearbeiten") {
                                onEditProfile(profile)
                            }
                            Button("Löschen") {
                                // Direct removal via manager for context menu
                                Task {
                                    try? await profileManager.removeProfile(profile)
                                    // Deselect if the selected one was deleted
                                    if selectedProfileID == profile.id {
                                        selectedProfileID = profileManager.profiles.first?.id
                                    }
                                }
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
            
            // Toolbar for Add/Remove buttons
            HStack {
                Button(action: onAddProfile) {
                    Image(systemName: "plus")
                }
                .help("Neues Profil hinzufügen")
                
                Button(action: {
                    if let selectedID = selectedProfileID,
                       let profileToRemove = profileManager.profiles.first(where: { $0.id == selectedID }) {
                        onRemoveProfile(profileToRemove)
                    }
                }) {
                    Image(systemName: "minus")
                }
                .help("Profil entfernen")
                .disabled(selectedProfileID == nil)
                
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}

/// View for displaying a single row in the profile list.
struct ProfileRowView: View {
    let profile: AuthProfile

    var body: some View {
        HStack {
            Image(systemName: profile.symbolName ?? "person.circle") // Use default symbol if nil
                .foregroundColor(.white)
                .padding(6)
                .background(
                    Circle()
                        .fill(profile.symbolColor)
                        .frame(width: 28, height: 28)
                )
            
            VStack(alignment: .leading) {
                Text(profile.displayName) // Use displayName now
                    .font(.headline)
                
                Text(profile.useKerberos ? "Kerberos: \(profile.kerberosRealm ?? "N/A")" : profile.username ?? "N/A")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Display Kerberos ticket status (needs real logic)
            if profile.useKerberos {
                HStack {
                    Circle()
                        // TODO: Replace with actual ticket status check
                        .fill(profile.hasValidTicket ?? false ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(profile.hasValidTicket ?? false ? "Ticket aktiv" : "Kein Ticket")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct ProfileDetailView: View {
    let profile: AuthProfile
    let associatedShares: [Share] // Use the real Share model
    let onEditProfile: () -> Void
    let onRefreshTicket: () -> Void
    
    // Access the Mounter
    private let mounter = appDelegate.mounter!

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Profile header
            HStack {
                Image(systemName: profile.symbolName)
                    .foregroundColor(.white)
                    .padding(8)
                    .background(
                        Circle()
                            .fill(profile.symbolColor)
                            .frame(width: 40, height: 40)
                    )
                
                Text(profile.name)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button("Bearbeiten") {
                    onEditProfile()
                }
            }
            
            Divider()
            
            // Authentication information
            VStack(alignment: .leading, spacing: 16) {
                Text("Anmeldedaten")
                    .font(.headline)
                
                if profile.useKerberos {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Kerberos-Authentifizierung")
                                .fontWeight(.medium)
                            Text("Realm: \(profile.kerberosRealm)")
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            HStack {
                                Circle()
                                    .fill(profile.hasValidTicket ? .green : .red)
                                    .frame(width: 10, height: 10)
                                Text(profile.hasValidTicket ? "Ticket gültig" : "Kein gültiges Ticket")
                            }
                            
                            Button("Ticket aktualisieren") {
                                onRefreshTicket()
                            }
                            .disabled(profile.hasValidTicket)
                        }
                    }
                } else {
                    Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                        GridRow {
                            Text("Benutzername:")
                            Text(profile.username)
                        }
                        GridRow {
                            Text("Passwort:")
                            Text(profile.password)
                        }
                    }
                }
            }
            
            Divider()
            
            // Associated shares
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Zugeordnete Shares (\(associatedShares.count))")
                        .font(.headline)
                        .padding(.bottom, 4)
                    
                    Spacer()
                    
                    Button("Verknüpfen...") {
                        // Design-Platzhalter
                    }
                    .font(.caption)
                }
                
                if associatedShares.isEmpty {
                    Text("Diesem Profil sind keine Shares zugeordnet.")
                        .foregroundColor(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(associatedShares) { share in
                            HStack {
                                Image(systemName: "externaldrive") // Generic share icon
                                    .foregroundColor(.secondary)
                                // Use shareDisplayName if available, otherwise networkShare
                                Text(share.shareDisplayName ?? share.networkShare)
                                Spacer()
                                // Show mount status icon/text
                                Circle()
                                     .fill(mountStatusColor(for: share.mountStatus))
                                     .frame(width: 8, height: 8)
                                Text(share.mountStatus.rawValue)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 2)
                            // Add context menu for share actions (optional)
                            .contextMenu {
                                Button(share.mountStatus == .mounted ? "Trennen" : "Verbinden") {
                                    Task {
                                        if share.mountStatus == .mounted {
                                            await mounter.unmountShare(for: share)
                                        } else {
                                            await mounter.mountGivenShares(userTriggered: true, forShare: share.id)
                                        }
                                        // Note: Reloading shares here won't update this specific view directly
                                        // unless AuthenticationView reloads its shareManager data.
                                        // Consider using @ObservedObject or other state management if needed.
                                    }
                                }
                                Button("Profilzuweisung aufheben") {
                                    // TODO: Implement logic to remove profile from share
                                    Logger.viewCycle.info("Remove profile assignment requested for share \(share.networkShare)")
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    /// Returns the appropriate color for the mount status indicator.
    private func mountStatusColor(for status: MountStatus) -> Color {
        switch status {
        case .mounted:
            return .green
        case .unmounted, .queued:
            return .gray
        case .missingPassword, .invalidCredentials, .errorOnMount, .obstructingDirectory, .unreachable:
            return .red
        case .unknown:
            return .orange
        }
    }
}

struct ProfileEditorView: View {
    @Binding var isPresented: Bool
    var existingProfile: AuthProfile?
    // Adjust onSave to accept optional password separately
    var onSave: (AuthProfile, String?) -> Void // Changed signature
    
    @State private var profileName: String
    @State private var username: String
    @State private var password: String // Keep password state for UI
    @State private var useKerberos: Bool
    @State private var kerberosRealm: String
    @State private var selectedSymbol: String
    @State private var selectedColor: Color
    
    // To track if password field was actually edited
    @State private var passwordChanged: Bool = false
    
    init(isPresented: Binding<Bool>, existingProfile: AuthProfile? = nil, onSave: @escaping (AuthProfile, String?) -> Void) {
        self._isPresented = isPresented
        self.existingProfile = existingProfile
        self.onSave = onSave // Updated signature
        
        // Initialize state from existing profile or with defaults
        if let profile = existingProfile {
            self._profileName = State(initialValue: profile.displayName)
            self._username = State(initialValue: profile.username ?? "")
            self._password = State(initialValue: "") // Start with empty password field for existing profiles
            self._useKerberos = State(initialValue: profile.useKerberos)
            self._kerberosRealm = State(initialValue: profile.kerberosRealm ?? "")
            self._selectedSymbol = State(initialValue: profile.symbolName ?? "person.circle")
            self._selectedColor = State(initialValue: profile.symbolColor)
        } else {
            // Defaults for new profile
            self._profileName = State(initialValue: "")
            self._username = State(initialValue: "")
            self._password = State(initialValue: "")
            self._useKerberos = State(initialValue: false)
            self._kerberosRealm = State(initialValue: "")
            self._selectedSymbol = State(initialValue: "person.circle")
            self._selectedColor = State(initialValue: .blue)
        }
    }
    
    // Available symbols for selection
    let availableSymbols = ["person", "building.2", "house", "briefcase", "desktopcomputer", 
                            "laptopcomputer", "server.rack", "network", "folder", "graduationcap"]
    
    // Available colors for selection
    let availableColors: [(name: String, color: Color)] = [
        ("Blau", .blue), ("Grün", .green), ("Rot", .red), ("Orange", .orange),
        ("Lila", .purple), ("Pink", .pink), ("Gelb", .yellow), ("Grau", .gray)
    ]
    
    var body: some View {
        VStack(spacing: 20) {
            Text(existingProfile == nil ? "Neues Profil erstellen" : "Profil bearbeiten")
                .font(.headline)
            
            // Profile visual configuration
            HStack(spacing: 20) {
                // Symbol selector
                VStack(alignment: .leading, spacing: 4) {
                    Text("Symbol:")
                    
                    Picker("Symbol wählen", selection: $selectedSymbol) {
                        ForEach(availableSymbols, id: \.self) { symbol in
                            Image(systemName: symbol).tag(symbol)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }
                
                // Color selector
                VStack(alignment: .leading, spacing: 4) {
                    Text("Farbe:")
                    
                    Picker("Farbe wählen", selection: $selectedColor) {
                        ForEach(availableColors, id: \.name) { colorOption in
                            HStack {
                                Circle()
                                    .fill(colorOption.color)
                                    .frame(width: 16, height: 16)
                                Text(colorOption.name)
                            }
                            .tag(colorOption.color)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }
                
                // Preview
                VStack {
                    Text("Vorschau:")
                    
                    Image(systemName: selectedSymbol)
                        .foregroundColor(.white)
                        .padding(8)
                        .background(
                            Circle()
                                .fill(selectedColor)
                                .frame(width: 40, height: 40)
                        )
                }
            }
            
            // Basic profile information
            VStack(alignment: .leading, spacing: 4) {
                Text("Bezeichnung:")
                TextField("z.B. Büro oder Home-Office", text: $profileName)
                    .textFieldStyle(.roundedBorder)
            }
            
            // Authentication type toggle
            Toggle("Kerberos-Authentifizierung verwenden", isOn: $useKerberos)
                .padding(.vertical, 4)
            
            // Authentication details
            if useKerberos {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Kerberos Realm:")
                    TextField("z.B. UNI-ERLANGEN.DE", text: $kerberosRealm)
                        .textFieldStyle(.roundedBorder)
                }
                 // Optionally show username/password fields even for Kerberos if needed for ticket fetching
                 // Add a comment explaining why they might be needed
                 Text("Benutzername/Passwort (optional für Kerberos-Ticket Aktualisierung):")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
                
                VStack(alignment: .leading, spacing: 12) {
                     VStack(alignment: .leading, spacing: 4) {
                        Text("Benutzername:")
                        TextField("Optional", text: $username)
                            .textFieldStyle(.roundedBorder)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Passwort:")
                        SecureField("Optional - Nur eingeben zum Ändern", text: $password)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: password) { _, _ in passwordChanged = true }
                    }
                }
                
            } else { // Standard Username/Password Auth
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Benutzername:")
                        TextField("Benutzername eingeben", text: $username)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Passwort:")
                        SecureField(existingProfile == nil ? "Passwort eingeben" : "Neues Passwort eingeben (optional)", text: $password)
                            .textFieldStyle(.roundedBorder)
                             // Track if password field was changed
                            .onChange(of: password) { _, _ in passwordChanged = true }
                    }
                }
            }
            
            Spacer()
            
            // Action buttons
            HStack {
                Button("Abbrechen") {
                    isPresented = false
                }
                
                Spacer()
                
                Button("Speichern") {
                    // Create the profile metadata object
                    var profileToSave = AuthProfile(
                        id: existingProfile?.id ?? UUID().uuidString, // Use existing ID or generate new one
                        displayName: profileName,
                        username: username.isEmpty ? nil : username, // Store nil if empty
                        useKerberos: useKerberos,
                        kerberosRealm: kerberosRealm.isEmpty ? nil : kerberosRealm, // Store nil if empty
                        symbolName: selectedSymbol,
                        symbolColor: selectedColor // This uses the setter which converts to Data
                        // hasValidTicket is managed elsewhere, not set here
                    )
                    
                    // Determine the password to save: only if changed and not empty
                    let passwordToSave: String? = (passwordChanged && !password.isEmpty) ? password : nil
                                        
                    // Call the adjusted onSave closure
                    onSave(profileToSave, passwordToSave)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                // Adjust disabled logic
                .disabled(profileName.isEmpty || 
                         (useKerberos && kerberosRealm.isEmpty) || 
                         (!useKerberos && username.isEmpty && existingProfile == nil) || // Require username for new non-Kerberos profiles
                         (!useKerberos && username.isEmpty && password.isEmpty && existingProfile != nil && !existingProfile!.requiresPasswordInKeychain) // Allow saving existing profile without username/password if not needed
                         // Add more sophisticated validation if needed
                         )
            }
        }
        .padding(20)
        .frame(width: 440, height: 500)
    }
}

#Preview {
    AuthenticationView()
} 
