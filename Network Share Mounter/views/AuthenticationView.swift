//
//  GeneralSettingsView.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 10.04.25.
//  Copyright © 2024 RRZE. All rights reserved.
//

import SwiftUI

/// Simple model for auth profiles (design only)
struct AuthProfile: Identifiable {
    var id = UUID()
    var name: String
    var username: String
    var password: String
    var useKerberos: Bool
    var kerberosRealm: String
    var symbolName: String
    var symbolColor: Color
    var hasValidTicket: Bool
}

/// Simple model for shares (design only)
struct ShareItem: Identifiable {
    var id = UUID()
    var name: String
    var url: String
    var isMounted: Bool
}

/// View for configuring authentication settings
struct AuthenticationView: View {
    // Beispiel-Daten für das Design
    @State private var profiles = [
        AuthProfile(
            name: "Büro", 
            username: "musterfrau", 
            password: "••••••••", 
            useKerberos: true, 
            kerberosRealm: "UNI-ERLANGEN.DE", 
            symbolName: "building.2", 
            symbolColor: .blue, 
            hasValidTicket: true
        ),
        AuthProfile(
            name: "Home-Office", 
            username: "homeuser", 
            password: "••••••••", 
            useKerberos: false, 
            kerberosRealm: "", 
            symbolName: "house", 
            symbolColor: .green, 
            hasValidTicket: false
        )
    ]
    
    @State private var shares = [
        ShareItem(name: "Dokumente", url: "smb://server.example.com/documents", isMounted: true),
        ShareItem(name: "Projekte", url: "smb://server.example.com/projects", isMounted: false)
    ]
    
    @State private var selectedProfileID: UUID?
    @State private var isAddingProfile = false
    @State private var isEditingProfile = false
    @State private var profileToEdit: AuthProfile?
    
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
        
            // Main structure is the HStack splitting left and right panes
            HStack(spacing: 0) {
                // Profile list column 
                VStack {
                    List(selection: $selectedProfileID) {
                        ForEach(profiles) { profile in
                            HStack {
                                Image(systemName: profile.symbolName)
                                    .foregroundColor(.white)
                                    .padding(6)
                                    .background(
                                        Circle()
                                            .fill(profile.symbolColor)
                                            .frame(width: 28, height: 28)
                                    )
                                
                                VStack(alignment: .leading) {
                                    Text(profile.name)
                                        .font(.headline)
                                    
                                    Text(profile.useKerberos ? "Kerberos: \(profile.kerberosRealm)" : profile.username)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if profile.useKerberos {
                                    HStack {
                                        Circle()
                                            .fill(profile.hasValidTicket ? .green : .red)
                                            .frame(width: 8, height: 8)
                                        Text(profile.hasValidTicket ? "Ticket aktiv" : "Kein Ticket")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .tag(profile.id)
                            .contextMenu {
                                Button("Bearbeiten") {
                                    profileToEdit = profile
                                    isEditingProfile = true
                                }
                                Button("Löschen") {
                                    if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
                                        profiles.remove(at: index)
                                        if selectedProfileID == profile.id {
                                            selectedProfileID = profiles.first?.id
                                        }
                                    }
                                }
                                Divider()
                                Button("Shares anzeigen") {
                                    // Design-Platzhalter
                                }
                                if profile.useKerberos {
                                    Divider()
                                    Button("Ticket aktualisieren") {
                                        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
                                            profiles[index].hasValidTicket = true
                                        }
                                    }
                                }
                            }
                        }
                    }
                    
                    HStack {
                        Button(action: { isAddingProfile = true }) {
                            Image(systemName: "plus")
                        }
                        .help("Neues Profil hinzufügen")
                        
                        Button(action: {
                            if let selectedID = selectedProfileID,
                               let index = profiles.firstIndex(where: { $0.id == selectedID }) {
                                profiles.remove(at: index)
                                selectedProfileID = profiles.first?.id
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
                .frame(width: 300)
                
                // Divider between columns
                Divider()
                
                // Right Detail Column - Now only contains the ScrollView
                // VStack(alignment: .leading, spacing: 0) { // Original VStack removed/merged
                    
                    // Header Section removed from here 

                    // Profile details column (inside ScrollView)
                    ScrollView {
                        if let selectedID = selectedProfileID,
                           let profile = profiles.first(where: { $0.id == selectedID }) {
                            ProfileDetailView(
                                profile: profile,
                                associatedShares: shares,
                                onEditProfile: {
                                    profileToEdit = profile
                                    isEditingProfile = true
                                },
                                onRefreshTicket: {
                                    if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
                                        profiles[index].hasValidTicket = true
                                    }
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
                // } // End of original Right VStack
                // .padding(20) // Padding removed from here

            } // End of Main HStack
        } // End of Outer VStack
        .sheet(isPresented: $isAddingProfile) {
            ProfileEditorView(isPresented: $isAddingProfile, onSave: { newProfile in
                profiles.append(newProfile)
                selectedProfileID = newProfile.id
            })
        }
        .sheet(isPresented: $isEditingProfile) {
            if let profile = profileToEdit {
                ProfileEditorView(
                    isPresented: $isEditingProfile,
                    existingProfile: profile,
                    onSave: { updatedProfile in
                        if let index = profiles.firstIndex(where: { $0.id == updatedProfile.id }) {
                            profiles[index] = updatedProfile
                        }
                    }
                )
            }
        }
    }
}

struct ProfileDetailView: View {
    let profile: AuthProfile
    let associatedShares: [ShareItem]
    let onEditProfile: () -> Void
    let onRefreshTicket: () -> Void
    
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
                    Text("Verknüpfte Network Shares")
                        .font(.headline)
                    
                    Spacer()
                    
                    Button("Verknüpfen...") {
                        // Design-Platzhalter
                    }
                    .font(.caption)
                }
                
                if associatedShares.isEmpty {
                    Text("Keine verknüpften Shares")
                        .foregroundColor(.secondary)
                        .italic()
                        .padding(.top, 4)
                } else {
                    ForEach(associatedShares) { share in
                        HStack {
                            Image(systemName: "folder")
                                .foregroundColor(.secondary)
                            Text(share.name)
                            Spacer()
                            Button {
                                // Design-Platzhalter
                            } label: {
                                Image(systemName: "xmark")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 4)
                    }
                    
                    HStack {
                        Spacer()
                        Button("Alle verbinden") {
                            // Design-Platzhalter
                        }
                        
                        Button("Alle trennen") {
                            // Design-Platzhalter
                        }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ProfileEditorView: View {
    @Binding var isPresented: Bool
    var existingProfile: AuthProfile?
    var onSave: (AuthProfile) -> Void
    
    @State private var profileName: String
    @State private var username: String
    @State private var password: String
    @State private var useKerberos: Bool
    @State private var kerberosRealm: String
    @State private var selectedSymbol: String
    @State private var selectedColor: Color
    
    init(isPresented: Binding<Bool>, existingProfile: AuthProfile? = nil, onSave: @escaping (AuthProfile) -> Void) {
        self._isPresented = isPresented
        self.existingProfile = existingProfile
        self.onSave = onSave
        
        // Initialize state from existing profile or with defaults
        if let profile = existingProfile {
            self._profileName = State(initialValue: profile.name)
            self._username = State(initialValue: profile.username)
            self._password = State(initialValue: profile.password)
            self._useKerberos = State(initialValue: profile.useKerberos)
            self._kerberosRealm = State(initialValue: profile.kerberosRealm)
            self._selectedSymbol = State(initialValue: profile.symbolName)
            self._selectedColor = State(initialValue: profile.symbolColor)
        } else {
            self._profileName = State(initialValue: "")
            self._username = State(initialValue: "")
            self._password = State(initialValue: "")
            self._useKerberos = State(initialValue: false)
            self._kerberosRealm = State(initialValue: "")
            self._selectedSymbol = State(initialValue: "person")
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
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Benutzername:")
                        TextField("Benutzername eingeben", text: $username)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Passwort:")
                        SecureField("Passwort eingeben", text: $password)
                            .textFieldStyle(.roundedBorder)
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
                    let profile = AuthProfile(
                        id: existingProfile?.id ?? UUID(),
                        name: profileName,
                        username: username,
                        password: password,
                        useKerberos: useKerberos,
                        kerberosRealm: kerberosRealm,
                        symbolName: selectedSymbol,
                        symbolColor: selectedColor,
                        hasValidTicket: existingProfile?.hasValidTicket ?? false
                    )
                    
                    onSave(profile)
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(profileName.isEmpty || 
                         (useKerberos && kerberosRealm.isEmpty) ||
                         (!useKerberos && username.isEmpty))
            }
        }
        .padding(20)
        .frame(width: 440, height: 500)
    }
}

#Preview {
    AuthenticationView()
} 
