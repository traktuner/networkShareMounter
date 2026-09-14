//
//  ProfileEditor.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 10.04.25.
//  Copyright © 2026 RRZE. All rights reserved.
//

import SwiftUI
import OSLog

// MARK: - Profile Editor View

struct ProfileEditorView: View {
    // Dependencies
    let mounter: Mounter
    
    // Presentation
    @Binding var isPresented: Bool
    
    // Editing context
    var existingProfile: AuthProfile?
    var onSave: (AuthProfile, String?) -> Void
    
    // Optional MDM realm
    let mdmRealm: String?
    
    // Form state
    @State private var profileName: String
    @State private var username: String
    @State private var password: String
    @State private var useKerberos: Bool
    @State private var kerberosRealm: String
    @State private var selectedSymbol: String
    @State private var selectedColor: Color
    
    // Associated shares
    @State private var editingAssociatedShares: [String] = []
    @State private var allAvailableShares: [Share] = []
    @State private var isLoadingShares: Bool = false
    @State private var isShowingShareSelection = false
    
    // Password change tracking
    @State private var passwordChanged: Bool = false
    
    // UPN state
    @State private var usernamePart: String = ""
    @State private var realmPart: String = ""
    
    // Realm conflict handling
    @State private var showRealmConflictDialog = false
    @State private var conflictingProfile: AuthProfile?
    
    // Preferences
    private let prefs = PreferenceManager()
    
    // Symbols for the icon picker
    private let availableSymbols = [
        "person", "building.2", "house", "briefcase", "desktopcomputer",
        "laptopcomputer", "server.rack", "network", "folder", "graduationcap", "popcorn"
    ]
    
    // Init
    init(
        mounter: Mounter,
        isPresented: Binding<Bool>,
        existingProfile: AuthProfile? = nil,
        mdmRealm: String? = nil,
        onSave: @escaping (AuthProfile, String?) -> Void
    ) {
        self.mounter = mounter
        self._isPresented = isPresented
        self.existingProfile = existingProfile
        self.mdmRealm = mdmRealm
        self.onSave = onSave
        
        if let profile = existingProfile {
            self._profileName = State(initialValue: profile.displayName)
            self._username = State(initialValue: profile.username ?? "")
            self._password = State(initialValue: "")
            self._useKerberos = State(initialValue: profile.useKerberos)
            self._kerberosRealm = State(initialValue: profile.kerberosRealm ?? "")
            self._selectedSymbol = State(initialValue: profile.symbolName ?? "person.circle")
            self._selectedColor = State(initialValue: profile.symbolColor)
            self._editingAssociatedShares = State(initialValue: profile.associatedNetworkShares ?? [])
            
            let existingUsername = profile.username ?? ""
            if existingUsername.contains("@") {
                let parts = existingUsername.split(separator: "@", maxSplits: 1)
                self._usernamePart = State(initialValue: String(parts.first ?? ""))
                self._realmPart = State(initialValue: String(parts.last ?? ""))
            } else {
                self._usernamePart = State(initialValue: existingUsername)
                self._realmPart = State(initialValue: profile.kerberosRealm ?? "")
            }
        } else {
            let prefs = PreferenceManager()
            let mdmRealm = mdmRealm ?? prefs.string(for: .kerberosRealm) ?? ""
            let shouldUseMDMRealm = !mdmRealm.isEmpty && AuthProfileManager.shared.needsMDMKerberosSetup() != nil
            let effectiveRealm = shouldUseMDMRealm ? mdmRealm : ""
            
            self._profileName = State(initialValue: "")
            self._username = State(initialValue: "")
            self._password = State(initialValue: "")
            self._useKerberos = State(initialValue: shouldUseMDMRealm)
            self._kerberosRealm = State(initialValue: effectiveRealm)
            self._selectedSymbol = State(initialValue: shouldUseMDMRealm ? "ticket" : "person.circle")
            self._selectedColor = State(initialValue: shouldUseMDMRealm ? .orange : .blue)
            self._editingAssociatedShares = State(initialValue: [])
            self._usernamePart = State(initialValue: "")
            self._realmPart = State(initialValue: effectiveRealm)
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        VStack(spacing: 0) {
            // Title
            header
            
            Divider()
                .padding(.bottom, 8)
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    basicInfoSection
                    kerberosSection
                    sharesSection
                    appearanceSection
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
            
            Divider()
            
            // Actions
            bottomBar
        }
        .frame(minWidth: 600, minHeight: 620)
        .onAppear {
            loadAllShares()
            loadExistingPassword()
        }
        .sheet(isPresented: $isShowingShareSelection) {
            modernShareSelectionSheet
        }
        .alert("A profile for this domain already exists", isPresented: $showRealmConflictDialog) {
            Button("Cancel", role: .cancel) { conflictingProfile = nil }
            Button("Replace", role: .destructive) { handleConfirmedReplacement() }
        } message: {
            if let existing = conflictingProfile {
                Text("There is already a Kerberos profile for the domain '\(existing.kerberosRealm ?? "")' named '\(existing.displayName)'. Only one Kerberos profile per domain is recommended. Do you want to replace the existing profile?")
            }
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack(spacing: 16) {
            Image(systemName: selectedSymbol)
                .foregroundStyle(.white)
                .font(.title2.weight(.medium))
                .frame(width: 48, height: 48)
                .background(Circle().fill(selectedColor.gradient))
                .shadow(color: selectedColor.opacity(0.3), radius: 6, x: 0, y: 3)

            VStack(alignment: .leading, spacing: 4) {
                Text(existingProfile == nil ? "Add Profile" : "Edit Profile")
                    .font(.title2.weight(.semibold))
                Text("Configure credentials and associated network shares.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(20)
    }
    
    // MARK: - Sections
    
    private var basicInfoSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Name") {
                    TextField("Profile name", text: $profileName)
                        .textFieldStyle(.roundedBorder)
                }
                
                LabeledContent("Username") {
                    if useKerberos && !realmPart.isEmpty {
                        HStack(spacing: 0) {
                            TextField("username", text: $usernamePart)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.body, design: .monospaced))
                            Text("@\(realmPart)")
                                .font(.body.monospaced())
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 6)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                )
                        }
                        .onChange(of: usernamePart) { _ in updateFullUsername() }
                    } else {
                        TextField("Username", text: $username)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: username) { newValue in parseUsernameInput(newValue) }
                    }
                }
                
                LabeledContent(passwordLabelText) {
                    SecureField("Password", text: passwordBinding)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(12)
        } label: {
            Label("Credentials", systemImage: "person.circle.fill")
                .foregroundStyle(.blue)
        }
    }
    
    private var kerberosSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Kerberos Authentication (Single Sign-On)", isOn: $useKerberos)
                    .onChange(of: useKerberos) { enabled in handleKerberosToggleChange(enabled) }
                    .disabled(shouldDisableKerberosToggle)
                
                if useKerberos {
                    LabeledContent("Kerberos Realm") {
                        TextField("REALM.EXAMPLE", text: $kerberosRealm)
                            .textFieldStyle(.roundedBorder)
                            .font(.body.monospaced())
                            .disabled(isMDMKerberosProfile)
                            .onChange(of: kerberosRealm) { newValue in
                                let normalized = newValue.uppercased()
                                if kerberosRealm != normalized {
                                    kerberosRealm = normalized
                                    return
                                }
                                guard realmPart != normalized else { return }
                                realmPart = normalized
                                updateFullUsername()
                            }
                    }
                    
                    if isRealmLocked || isMDMKerberosProfile {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(.secondary)
                            Text("Defined by MDM policy")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, -4)
                    }
                }
            }
            .padding(12)
        } label: {
            Label("Kerberos", systemImage: useKerberos ? "ticket.fill" : "ticket")
                .foregroundStyle(useKerberos ? .orange : .secondary)
        }
    }
    
    private var sharesSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                if isLoadingShares {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Loading available shares…")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                
                if editingAssociatedShares.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("No shares assigned")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("Add network shares to be authenticated with this profile.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                } else {
                    VStack(spacing: 8) {
                        ForEach(editingAssociatedShares, id: \.self) { shareURL in
                            HStack(spacing: 8) {
                                Image(systemName: "externaldrive")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(shareDisplayName(for: shareURL))
                                        .font(.subheadline)
                                    Text(shareURL)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button(role: .destructive) {
                                    removeAssociatedShare(url: shareURL)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                                .help("Remove share")
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                
                HStack {
                    Spacer()
                    Button {
                        isShowingShareSelection = true
                    } label: {
                        Label("Add share…", systemImage: "plus")
                    }
                }
                .padding(.top, 4)
            }
            .padding(12)
        } label: {
            Label("Associated Shares (\(editingAssociatedShares.count))", systemImage: "externaldrive.fill")
                .foregroundStyle(.green)
        }
    }
    
    private var appearanceSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Symbol") {
                    Picker("Symbol", selection: $selectedSymbol) {
                        ForEach(availableSymbols, id: \.self) { symbol in
                            HStack {
                                Image(systemName: symbol)
                                Text(symbolDisplayName(for: symbol))
                            }
                            .tag(symbol)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }
                
                LabeledContent("Color") {
                    ColorPicker("", selection: $selectedColor, supportsOpacity: false)
                        .labelsHidden()
                        .frame(width: 44, height: 24)
                }
            }
            .padding(12)
        } label: {
            Label("Appearance", systemImage: "paintpalette.fill")
                .foregroundStyle(.purple)
        }
    }
    
    // MARK: - Bottom Bar
    
    private var bottomBar: some View {
        HStack(spacing: 16) {
            Button("Cancel") { isPresented = false }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)

            Spacer()

            Button("Save") { saveChanges() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(isSaveDisabled)
        }
        .padding(16)
    }
    
    // MARK: - Helpers
    
    private var passwordBinding: Binding<String> {
        Binding(
            get: { password },
            set: { newValue in
                password = newValue
                passwordChanged = true
            }
        )
    }
    
    private var isMDMKerberosProfile: Bool {
        if let mdmRealm = prefs.string(for: .kerberosRealm), !mdmRealm.isEmpty {
            return kerberosRealm.uppercased() == mdmRealm.uppercased()
        }
        return false
    }
    
    private var isRealmLocked: Bool {
        return mdmRealm != nil || AuthProfileManager.shared.isMDMConfiguredRealm(realmPart)
    }
    
    private var shouldDisableKerberosToggle: Bool {
        return mdmRealm != nil && AuthProfileManager.shared.needsMDMKerberosSetup() != nil && existingProfile == nil
    }
    
    private func updateFullUsername() {
        let newUsername = realmPart.isEmpty ? usernamePart : "\(usernamePart)@\(realmPart)"
        guard username != newUsername else { return }
        username = newUsername
    }
    
    // Detect UPN-like input to split username/realm, but do not auto-enable Kerberos.
    private func parseUsernameInput(_ usernameInput: String) {
        guard usernameInput.contains("@") else {
            if usernamePart != usernameInput {
                usernamePart = usernameInput
            }
            return
        }
        let parts = usernameInput.split(separator: "@", maxSplits: 1)
        guard parts.count == 2 else { return }

        let userPart = String(parts[0])
        let newRealm = String(parts[1]).uppercased()

        // Update split parts if changed
        guard usernamePart != userPart || realmPart.uppercased() != newRealm else { return }

        usernamePart = userPart
        realmPart = newRealm

        // Do NOT auto-enable Kerberos here.
        // Only prepare the realm; if Kerberos is already enabled, sync kerberosRealm.
        if useKerberos {
            kerberosRealm = newRealm
        }
    }
    
    private func handleKerberosToggleChange(_ enabled: Bool) {
        if enabled {
            if kerberosRealm.isEmpty && existingProfile == nil {
                let effectiveRealm = mdmRealm ?? prefs.string(for: .kerberosRealm) ?? ""
                let shouldUseMDMRealm = !effectiveRealm.isEmpty && AuthProfileManager.shared.needsMDMKerberosSetup() != nil
                if shouldUseMDMRealm && kerberosRealm != effectiveRealm.uppercased() {
                    kerberosRealm = effectiveRealm.uppercased()
                }
            }
            if realmPart != kerberosRealm {
                realmPart = kerberosRealm
            }
            if selectedSymbol == "person.circle" {
                selectedSymbol = "ticket"
                selectedColor = .orange
            }
            updateFullUsername()
        } else {
            if !realmPart.isEmpty {
                realmPart = ""
            }
            if kerberosRealm == mdmRealm || AuthProfileManager.shared.isMDMConfiguredRealm(kerberosRealm) {
                if username != usernamePart {
                    username = usernamePart
                }
            }
            if selectedSymbol == "ticket" {
                selectedSymbol = "person.circle"
                selectedColor = .blue
            }
        }
    }
    
    private var modernShareSelectionSheet: some View {
        ShareSelectionSheet(
            allAvailableShares: allAvailableShares,
            alreadyAssociatedShares: editingAssociatedShares,
            onAddShares: { selectedShareURLs in
                for url in selectedShareURLs where !editingAssociatedShares.contains(url) {
                    editingAssociatedShares.append(url)
                }
            }
        )
        .frame(minWidth: 500, minHeight: 500)
    }
    
    private func loadAllShares() {
        isLoadingShares = true
        Task {
            allAvailableShares = await mounter.shareManager.allShares
            isLoadingShares = false
        }
    }
    
    private func loadExistingPassword() {
        guard let profile = existingProfile else { return }
        Task {
            do {
                let profileManager = AuthProfileManager.shared
                if let savedPassword = try await profileManager.retrievePassword(for: profile) {
                    await MainActor.run {
                        self.password = savedPassword
                    }
                }
            } catch {
                Logger.authProfile.error("Could not load existing password for profile '\(profile.displayName)': \(error.localizedDescription)")
            }
        }
    }
    
    private func shareDisplayName(for url: String) -> String {
        if let match = allAvailableShares.first(where: { $0.networkShare == url }) {
            return match.effectiveMountPoint
        }
        return extractShareName(from: url)
    }
    
    private func removeAssociatedShare(url: String) {
        editingAssociatedShares.removeAll { $0 == url }
    }
    
    private func buildEffectiveUsername() -> String? {
        if useKerberos && !usernamePart.isEmpty {
            return realmPart.isEmpty ? usernamePart : "\(usernamePart)@\(realmPart)"
        }
        return username.isEmpty ? nil : username
    }

    private func saveChanges() {
        var profileToSave = AuthProfile(
            id: existingProfile?.id ?? UUID().uuidString,
            displayName: profileName,
            username: buildEffectiveUsername(),
            useKerberos: useKerberos,
            kerberosRealm: kerberosRealm.isEmpty ? nil : kerberosRealm.uppercased(),
            associatedNetworkShares: editingAssociatedShares.isEmpty ? nil : editingAssociatedShares,
            symbolName: selectedSymbol
        )
        profileToSave.symbolColor = selectedColor
        
        let passwordToSave: String? = (passwordChanged && !password.isEmpty) ? password : nil
        
        Task {
            let validation = await AuthProfileManager.shared.validateProfile(profileToSave)
            await MainActor.run {
                if let conflict = validation.realmConflict {
                    self.conflictingProfile = conflict
                    self.showRealmConflictDialog = true
                } else {
                    onSave(profileToSave, passwordToSave)
                    isPresented = false
                }
            }
        }
    }
    
    private func handleConfirmedReplacement() {
        guard let conflictingProfile else { return }
        
        var profileToSave = AuthProfile(
            id: existingProfile?.id ?? UUID().uuidString,
            displayName: profileName,
            username: buildEffectiveUsername(),
            useKerberos: useKerberos,
            kerberosRealm: kerberosRealm.isEmpty ? nil : kerberosRealm.uppercased(),
            associatedNetworkShares: editingAssociatedShares.isEmpty ? nil : editingAssociatedShares,
            symbolName: selectedSymbol
        )
        profileToSave.symbolColor = selectedColor
        
        let passwordToSave: String? = (passwordChanged && !password.isEmpty) ? password : nil
        
        Task {
            do {
                try await AuthProfileManager.shared.replaceKerberosProfile(
                    profileToSave,
                    replacing: conflictingProfile,
                    password: passwordToSave
                )
                await MainActor.run { isPresented = false }
            } catch {
                Logger.authProfile.error("Failed to replace profile: \(error.localizedDescription)")
            }
        }
    }
    
    private var isSaveDisabled: Bool {
        profileName.isEmpty ||
        (useKerberos && kerberosRealm.isEmpty && !isMDMKerberosProfile) ||
        (!useKerberos && username.isEmpty && existingProfile == nil)
    }
    
    private var passwordLabelText: String {
        useKerberos ? "Password:" : (existingProfile == nil ? "Password:" : "New Password:")
    }
    
    private func symbolDisplayName(for symbol: String) -> String {
        switch symbol {
        case "person": return "Person"
        case "building.2": return "Building"
        case "house": return "Home"
        case "briefcase": return "Work"
        case "desktopcomputer": return "Desktop"
        case "laptopcomputer": return "Laptop"
        case "server.rack": return "Server"
        case "network": return "Network"
        case "folder": return "Folder"
        case "graduationcap": return "Education"
        case "popcorn": return "Leisure"
        default: return symbol
        }
    }
}

// MARK: - Share Selection Sheet

struct ShareSelectionSheet: View {
    let allAvailableShares: [Share]
    let alreadyAssociatedShares: [String]
    var onAddShares: ([String]) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedShareURLs: Set<String> = []
    
    private var availableSharesToSelect: [Share] {
        allAvailableShares.filter { !alreadyAssociatedShares.contains($0.networkShare) }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Select Shares").font(.title2.weight(.semibold))
                Text("Select the network shares you want to associate with this profile.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            
            Divider()
            
            if availableSharesToSelect.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "externaldrive")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("No more shares available")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("All available shares are already assigned.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(20)
            } else {
                List(availableSharesToSelect, id: \.id) { share in
                    let isSelected = selectedShareURLs.contains(share.networkShare)
                    HStack {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(share.effectiveMountPoint)
                            Text(share.networkShare)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if isSelected {
                            selectedShareURLs.remove(share.networkShare)
                        } else {
                            selectedShareURLs.insert(share.networkShare)
                        }
                    }
                }
                .listStyle(.inset)
            }
            
            Divider()
            
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add (\(selectedShareURLs.count))") {
                    onAddShares(Array(selectedShareURLs))
                    dismiss()
                }
                .disabled(selectedShareURLs.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 520, height: 520)
    }
}

// MARK: - Preview

struct ProfileEditorView_Previews: PreviewProvider {
    static let previewMounter = Mounter()
    static var exampleProfile: AuthProfile {
        var p = AuthProfile(
            displayName: "Work Server",
            username: "gregor",
            useKerberos: true,
            kerberosRealm: "EXAMPLE.COM",
            associatedNetworkShares: ["smb://server1/data"],
            symbolName: "ticket"
        )
        p.symbolColor = .orange
        return p
    }
    
    static var previews: some View {
        ProfileEditorView(
            mounter: previewMounter,
            isPresented: .constant(true),
            onSave: { _,_  in }
        )
        .previewDisplayName("New Profile")
        
        ProfileEditorView(
            mounter: previewMounter,
            isPresented: .constant(true),
            existingProfile: exampleProfile,
            onSave: { _,_ in }
        )
        .previewDisplayName("Edit Profile")
    }
}

