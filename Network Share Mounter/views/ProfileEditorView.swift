import SwiftUI
import OSLog

// MARK: - Profile Editor View

struct ProfileEditorView: View {
    // Environment or passed-in objects
    // We need the mounter to access the ShareManager
    let mounter: Mounter
    
    // Bindings and State
    @Binding var isPresented: Bool
    var existingProfile: AuthProfile?
    var onSave: (AuthProfile, String?) -> Void // (Profile Metadata, Optional Password)
    
    @State private var profileName: String
    @State private var username: String
    @State private var password: String // Keep password state for UI only
    @State private var useKerberos: Bool
    @State private var kerberosRealm: String
    @State private var selectedSymbol: String
    @State private var selectedColor: Color
    
    // State for managing associated shares during editing
    @State private var editingAssociatedShares: [String] = []
    @State private var allAvailableShares: [Share] = [] // To populate selection later
    
    // To track if password field was actually edited
    @State private var passwordChanged: Bool = false
    
    // To indicate loading state for shares
    @State private var isLoadingShares: Bool = false
    
    // State to control the presentation of the share selection sheet
    @State private var isShowingShareSelection = false
    
    // Add preference manager for accessing MDM settings
    private let prefs = PreferenceManager()
    
    /// Loads the Kerberos realm from available sources
    private func loadKerberosRealm() -> String {
        // First try to get realm from MDM preferences
        if let mdmRealm = prefs.string(for: .kerberosRealm), !mdmRealm.isEmpty {
            Logger.dataModel.debug("Using Kerberos realm from MDM: \(mdmRealm)")
            return mdmRealm
        }
        
        // If no MDM realm, use FAU realm if configured
        if prefs.string(for: .kerberosRealm)?.lowercased() == FAU.kerberosRealm.lowercased() {
            Logger.dataModel.debug("Using FAU Kerberos realm: \(FAU.kerberosRealm)")
            return FAU.kerberosRealm
        }
        
        // Return empty string if no realm found
        return ""
    }
    
    /// Checks if this is an MDM-configured Kerberos profile
    private var isMDMKerberosProfile: Bool {
        // Check if MDM has configured a Kerberos realm
        if let mdmRealm = prefs.string(for: .kerberosRealm), !mdmRealm.isEmpty {
            return true
        }
        return false
    }
    
    // Computed binding to handle password changes
    private var passwordBinding: Binding<String> {
        Binding<String>(
            get: { self.password },
            set: { newValue in
                self.password = newValue
                // Set the flag whenever the binding is used to set a new value
                self.passwordChanged = true 
            }
        )
    }
    
    // Initialization
    init(mounter: Mounter, isPresented: Binding<Bool>, existingProfile: AuthProfile? = nil, onSave: @escaping (AuthProfile, String?) -> Void) {
        self.mounter = mounter
        self._isPresented = isPresented
        self.existingProfile = existingProfile
        self.onSave = onSave
        
        // Initialize state from existing profile or with defaults
        if let profile = existingProfile {
            self._profileName = State(initialValue: profile.displayName)
            self._username = State(initialValue: profile.username ?? "")
            self._password = State(initialValue: "") // Start with empty password field for existing profiles
            self._useKerberos = State(initialValue: profile.useKerberos)
            // Use existing realm or load from preferences if empty
            self._kerberosRealm = State(initialValue: profile.kerberosRealm ?? PreferenceManager().string(for: .kerberosRealm) ?? "")
            self._selectedSymbol = State(initialValue: profile.symbolName ?? "person.circle")
            self._selectedColor = State(initialValue: profile.symbolColor)
            // Initialize associated shares for editing
            self._editingAssociatedShares = State(initialValue: profile.associatedNetworkShares ?? [])
        } else {
            // Defaults for new profile
            let prefs = PreferenceManager()
            let hasMDMKerberos = prefs.string(for: .kerberosRealm) != nil && !prefs.string(for: .kerberosRealm)!.isEmpty
            
            self._profileName = State(initialValue: "")
            self._username = State(initialValue: "")
            self._password = State(initialValue: "")
            self._useKerberos = State(initialValue: hasMDMKerberos) // Auto-enable if MDM configured
            // Load Kerberos realm from preferences for new profiles
            self._kerberosRealm = State(initialValue: prefs.string(for: .kerberosRealm) ?? "")
            self._selectedSymbol = State(initialValue: "person.circle")
            self._selectedColor = State(initialValue: .blue)
            self._editingAssociatedShares = State(initialValue: []) // Start empty for new profile
        }
    }
    
    // Constants for pickers
    let availableSymbols = ["person", "building.2", "house", "briefcase", "desktopcomputer",
                            "laptopcomputer", "server.rack", "network", "folder", "graduationcap", "popcorn"]

    // Body
    var body: some View {
        VStack(spacing: 0) {
            // Scrollable content area
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text(existingProfile == nil ? "Neues Profil erstellen" : "Profil bearbeiten")
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Erstellen Sie ein Authentifizierungsprofil für Ihre Netzwerk-Shares.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Basic Information Section
                    GroupBox {
                        VStack(alignment: .leading, spacing: 16) {
                            basicInfoFields
                            
                            Divider()
                            
                            kerberosToggleSection
                            
                            if useKerberos {
                                kerberosRealmField
                            }
                        }
                        .padding(16)
                    } label: {
                        Label("Anmeldedaten", systemImage: "person.circle")
                            .font(.headline)
                    }
                    
                    // Associated Shares Section
                    GroupBox {
                        VStack(alignment: .leading, spacing: 16) {
                            if isLoadingShares {
                                HStack {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Lade verfügbare Shares...")
                                        .foregroundColor(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical)
                            } else {
                                associatedSharesList
                            }
                        }
                        .padding(16)
                    } label: {
                        Label("Zugeordnete Shares (\(editingAssociatedShares.count))", systemImage: "externaldrive")
                            .font(.headline)
                    }
                    
                    // Profile Appearance Section
                    GroupBox {
                        VStack(alignment: .leading, spacing: 16) {
                            profileAppearanceSection
                        }
                        .padding(16)
                    } label: {
                        Label("Profilbild", systemImage: "paintbrush")
                            .font(.headline)
                    }
                }
                .padding(24)
            }
            
            // Bottom buttons bar
            Divider()
            
            HStack {
                Button("Abbrechen") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Speichern") {
                    saveChanges()
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaveDisabled)
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(minWidth: 600, minHeight: 700) // Ensure buttons are always visible
        .onAppear {
            loadAllShares() // Load shares when view appears
            loadExistingPassword() // Load password for existing profiles
        }
        // Add the sheet modifier for share selection
        .sheet(isPresented: $isShowingShareSelection) {
            // Pass available shares, already associated shares, and the callback
            ShareSelectionSheet(
                allAvailableShares: allAvailableShares,
                alreadyAssociatedShares: editingAssociatedShares,
                onAddShares: { selectedShareURLs in
                    // Add the newly selected URLs to our editing state,
                    // ensuring no duplicates
                    for url in selectedShareURLs {
                        if !editingAssociatedShares.contains(url) {
                            editingAssociatedShares.append(url)
                        }
                    }
                }
            )
        }
    } // End of body

    // MARK: - UI Components
    
    @ViewBuilder
    private var basicInfoFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Bezeichnung:")
                    .frame(width: 100, alignment: .trailing)
                TextField("Profil Name", text: $profileName)
                    .textFieldStyle(.roundedBorder)
            }
            
            HStack {
                Text("Benutzername:")
                    .frame(width: 100, alignment: .trailing)
                TextField("Benutzername", text: $username)
                    .textFieldStyle(.roundedBorder)
            }
            
            HStack {
                Text(passwordLabelText)
                    .frame(width: 100, alignment: .trailing)
                SecureField("Passwort", text: passwordBinding)
                    .textFieldStyle(.roundedBorder)
            }
        }
    }
    
    @ViewBuilder
    private var kerberosToggleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Kerberos-Authentifizierung verwenden", isOn: $useKerberos)
                .disabled(isMDMKerberosProfile)
            
            if isMDMKerberosProfile {
                HStack {
                    Image(systemName: "gearshape.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                    Text("Durch MDM-Richtlinie vorgegeben")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    @ViewBuilder
    private var kerberosRealmField: some View {
        HStack {
            Text("Kerberos Realm:")
                .frame(width: 100, alignment: .trailing)
            VStack(alignment: .leading, spacing: 4) {
                TextField("REALM.COM", text: $kerberosRealm)
                    .textFieldStyle(.roundedBorder)
                    .disabled(isMDMKerberosProfile)
                
                if isMDMKerberosProfile {
                    HStack {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.orange)
                            .font(.caption2)
                        Text("Durch MDM-Richtlinie vorgegeben")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var associatedSharesList: some View {
        if editingAssociatedShares.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "externaldrive")
                    .font(.largeTitle)
                    .foregroundColor(.secondary)
                
                Text("Keine Shares zugeordnet")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                Text("Fügen Sie Netzwerk-Shares hinzu, die mit diesem Profil authentifiziert werden sollen.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(editingAssociatedShares, id: \.self) { shareURL in
                    HStack {
                        Image(systemName: "externaldrive")
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shareDisplayName(for: shareURL))
                                .font(.subheadline)
                            Text(shareURL)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Button {
                            removeAssociatedShare(url: shareURL)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                        .help("Share entfernen")
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                }
            }
        }
        
        HStack {
            Spacer()
            Button("Share hinzufügen...") {
                isShowingShareSelection = true
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 8)
    }
    
    @ViewBuilder
    private var profileAppearanceSection: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Symbol")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Picker("Symbol wählen", selection: $selectedSymbol) {
                    ForEach(availableSymbols, id: \.self) { symbol in
                        Image(systemName: symbol).tag(symbol)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Farbe")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                ColorPicker("Profilfarbe auswählen", selection: $selectedColor, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 120)
                    .help("Wählen Sie eine Farbe für das Profilsymbol")
            }
            
            Spacer()
            
            VStack(alignment: .center, spacing: 8) {
                Text("Vorschau")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Image(systemName: selectedSymbol)
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(
                        Circle()
                            .fill(selectedColor)
                    )
            }
        }
    }

    // --- Helper Functions ---

    /// Loads all available shares from the ShareManager.
    private func loadAllShares() {
        isLoadingShares = true
        Task {
            allAvailableShares = await mounter.shareManager.allShares
            isLoadingShares = false
            // Log or handle potential errors during loading if ShareManager throws
            print("Loaded \(allAvailableShares.count) available shares.")
        }
    }
    
    /// Loads the existing password for profile editing (the Apple way).
    private func loadExistingPassword() {
        guard let profile = existingProfile else { return }
        
        Task {
            do {
                let profileManager = AuthProfileManager.shared
                if let savedPassword = try await profileManager.retrievePassword(for: profile) {
                    await MainActor.run {
                        self.password = savedPassword
                        // Don't set passwordChanged to true - this is the original password
                    }
                }
            } catch {
                print("Could not load existing password for profile '\(profile.displayName)': \(error.localizedDescription)")
                // Leave password empty if we can't load it
            }
        }
    }
    
    /// Finds the display name for a given share URL from the loaded shares.
    private func shareDisplayName(for url: String) -> String {
        // Find the share in allAvailableShares that matches the URL
        if let matchingShare = allAvailableShares.first(where: { $0.networkShare == url }) {
            // Return display name if available, otherwise the URL itself
            return matchingShare.shareDisplayName ?? url
        }
        // If the URL is not found among available shares (e.g., stale entry), return the URL
        return url
    }

    /// Removes a share URL from the editing list.
    private func removeAssociatedShare(url: String) {
        editingAssociatedShares.removeAll { $0 == url }
    }
    
    /// Creates the final AuthProfile object and calls the onSave closure.
    private func saveChanges() {
        // 1. Create the profile metadata object WITHOUT color initially
        var profileToSave = AuthProfile(
            id: existingProfile?.id ?? UUID().uuidString, // Use existing ID or generate new one
            displayName: profileName,
            username: username.isEmpty ? nil : username, // Store nil if empty
            useKerberos: useKerberos,
            kerberosRealm: kerberosRealm.isEmpty ? nil : kerberosRealm, // Store nil if empty
            // Assign the edited list of associated shares
            associatedNetworkShares: editingAssociatedShares.isEmpty ? nil : editingAssociatedShares,
            symbolName: selectedSymbol
            // symbolColorData: selectedColor // REMOVED - Setter converts to Data
            // hasValidTicket is managed elsewhere, not set here
        )
        
        // 2. Set the color using the computed property setter
        profileToSave.symbolColor = selectedColor
        
        // Determine the password to save: only if changed and not empty
        let passwordToSave: String? = (passwordChanged && !password.isEmpty) ? password : nil
                            
        // Call the adjusted onSave closure
        onSave(profileToSave, passwordToSave)
        isPresented = false
    }
    
    /// Computed property to determine if the Save button should be disabled.
    private var isSaveDisabled: Bool {
        // Basic validation: Profile name must not be empty.
        // Kerberos requires realm (but MDM-configured realm is always valid).
        // Non-Kerberos requires username for *new* profiles.
        return profileName.isEmpty ||
               (useKerberos && kerberosRealm.isEmpty && !isMDMKerberosProfile) ||
               (!useKerberos && username.isEmpty && existingProfile == nil)
        // Add more sophisticated validation if needed
    }

    // --- Computed Properties for Labels (Only Password Label needed now) ---
    
    // Keep passwordLabel computed property as its logic is more complex
    private var passwordLabelText: String {
        if useKerberos {
            return "Passwort:"
        } else {
            return existingProfile == nil ? "Passwort:" : "Neues Passwort:"
        }
    }
    

}

// MARK: - Share Selection Sheet

struct ShareSelectionSheet: View {
    // Input Data
    let allAvailableShares: [Share]
    let alreadyAssociatedShares: [String]
    var onAddShares: ([String]) -> Void // Closure to return selected URLs

    // Environment for dismissal
    @Environment(\.dismiss) var dismiss

    // State for managing selections within the sheet
    @State private var selectedShareURLs: Set<String> = []

    // Filtered list of shares that are not already associated
    private var availableSharesToSelect: [Share] {
        allAvailableShares.filter { !alreadyAssociatedShares.contains($0.networkShare) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("Shares auswählen")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Wählen Sie die Netzwerk-Shares aus, die Sie diesem Profil zuordnen möchten.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 16)
            
            Divider()
            
            // Content
            if availableSharesToSelect.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "externaldrive")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    
                    Text("Keine weiteren Shares verfügbar")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    
                    Text("Alle verfügbaren Shares sind bereits diesem oder anderen Profilen zugeordnet.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(availableSharesToSelect, id: \.id) { share in
                            shareSelectionRow(share)
                        }
                    }
                    .padding(24)
                }
            }
            
            // Bottom buttons
            Divider()
            
            HStack {
                Button("Abbrechen") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Hinzufügen (\(selectedShareURLs.count))") {
                    onAddShares(Array(selectedShareURLs))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedShareURLs.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 500, height: 600)
    }
    
    @ViewBuilder
    private func shareSelectionRow(_ share: Share) -> some View {
        let isSelected = selectedShareURLs.contains(share.networkShare)
        
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundColor(isSelected ? .blue : .secondary)
                .font(.title2)
            
            Image(systemName: "externaldrive")
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(share.shareDisplayName ?? "Unbenannt")
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Text(share.networkShare)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            isSelected ? Color.blue.opacity(0.15) : Color(NSColor.controlBackgroundColor)
        )
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture {
            toggleSelection(for: share.networkShare)
        }
    }
    
    private func toggleSelection(for shareURL: String) {
        if selectedShareURLs.contains(shareURL) {
            selectedShareURLs.remove(shareURL)
        } else {
            selectedShareURLs.insert(shareURL)
        }
    }
}

// MARK: - Preview

// Add a preview provider for easier design iteration
struct ProfileEditorView_Previews: PreviewProvider {
    // Mock Mounter and Managers for preview
    // Note: This requires creating mock versions or simple instances.
    // For now, let's assume a basic Mounter instance can be created.
    // This might need adjustment based on Mounter's initializer.
    static let previewMounter = Mounter() // Placeholder - adjust as needed

    // Example Profile for editing preview - make it var to modify
    static var exampleProfile: AuthProfile {
        var profile = AuthProfile(
            displayName: "Work Server",
            username: "gregor",
            useKerberos: false,
            associatedNetworkShares: ["smb://server1/data", "smb://server2/archive"],
            symbolName: "briefcase"
            // symbolColorData: .blue // REMOVED
        )
        // Set color using computed property
        profile.symbolColor = .blue 
        return profile
    }

    static var previews: some View {
        // Preview for creating a new profile
        ProfileEditorView(
            mounter: previewMounter,
            isPresented: .constant(true),
            onSave: { profile, password in
                print("Preview Save New: \(profile), Password Provided: \(password != nil)")
            }
        )
        .previewDisplayName("New Profile")

        // Preview for editing an existing profile
        ProfileEditorView(
            mounter: previewMounter,
            isPresented: .constant(true),
            existingProfile: exampleProfile,
            onSave: { profile, password in
                print("Preview Save Edit: \(profile), Password Provided: \(password != nil)")
            }
        )
        .previewDisplayName("Edit Profile")
    }
}
