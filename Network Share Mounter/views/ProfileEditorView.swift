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
            self._profileName = State(initialValue: "")
            self._username = State(initialValue: "")
            self._password = State(initialValue: "")
            self._useKerberos = State(initialValue: false)
            // Load Kerberos realm from preferences for new profiles
            self._kerberosRealm = State(initialValue: PreferenceManager().string(for: .kerberosRealm) ?? "")
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
        // Wrap Form in a VStack to place buttons outside and at the bottom
        VStack(spacing: 0) { // Use 0 spacing, let Form and Padding handle spacing
            // Use a Form for better structure on macOS sheets
            Form {
                Section {
                    // Replace implicit Form layout with explicit Grid
    //                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10) {
                    Grid {
                        GridRow {
                            Text("Bezeichnung:")
                                .gridColumnAlignment(.trailing) // Align labels to the right
                            TextField("", text: $profileName)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        GridRow {
                            Text("Benutzername:")
                                .gridColumnAlignment(.trailing)
                            TextField("", text: $username)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        GridRow {
                            Text(passwordLabelText)
                                .gridColumnAlignment(.trailing)
                            SecureField("", text: passwordBinding)
                                 .textFieldStyle(.roundedBorder)
                        }
                        
                        GridRow {
                             Toggle("Kerberos-Authentifizierung verwenden", isOn: $useKerberos)
                                .gridCellColumns(2)
                                .padding(.trailing)
                        }

                        // Kerberos Realm Row (always present, but conditionally visible)
                        GridRow {
                            Text("Kerberos Realm:")
                                .gridColumnAlignment(.trailing)
                                .opacity(useKerberos ? 1 : 0) // Hide with opacity
                            TextField("", text: $kerberosRealm)
                                .textFieldStyle(.roundedBorder)
                                .disabled(!useKerberos)
                                .opacity(useKerberos ? 1 : 0)
                        }
                    }
                }
                header: {
                    Text(existingProfile == nil ? "Neues Profil erstellen" : "Profil bearbeiten")
                        .font(.headline)
                        .padding(.bottom, 4) // Add consistent padding to match other views
                }
                .padding(.bottom)

                // Section for Associated Shares
                Section {
                    if isLoadingShares {
                         ProgressView() // Show loading indicator
                             .frame(maxWidth: .infinity, alignment: .center)
                             .padding(.vertical)
                    } else {
                        if editingAssociatedShares.isEmpty {
                             Text("Keine Shares zugeordnet.")
                                 .foregroundColor(.secondary)
                                 .frame(maxWidth: .infinity, alignment: .center)
                                 .padding(.vertical)
                        } else {
                             List {
                                 ForEach(editingAssociatedShares, id: \.self) { shareURL in
                                     HStack {
                                         // Try to find the display name for the URL
                                         Text(shareDisplayName(for: shareURL))
                                         Spacer()
                                         Button {
                                             removeAssociatedShare(url: shareURL)
                                         } label: {
                                             Image(systemName: "minus.circle.fill")
                                                 .foregroundColor(.red)
                                         }
                                         .buttonStyle(.plain) // Use plain to avoid default button background in list
                                     }
                                 }
                             }
                             .frame(height: 100) // Fixed height for List
                        }
                        
                        // TODO: Implement Add Share Button and Sheet
                        HStack {
                             Spacer()
                             Button("Share hinzufügen...") {
                                 // Action to open share selection sheet
                                 isShowingShareSelection = true
                             }
                         }
                    }
                } header: {
                    Text("Zugeordnete Shares")
                        .font(.headline)
                        .padding(.bottom, 4) // Add consistent padding to match other views
                }
                
                Section {
                    Grid {
                        GridRow {
                            Text("Symbol:")
                                .gridColumnAlignment(.leading)
                            Text("Farbe:")
                                .gridColumnAlignment(.leading)
                            Text("Vorschau:")
                                .gridColumnAlignment(.leading)
                        }
                        .padding(.top, 8)
                        GridRow {
                            Picker("Symbol wählen", selection: $selectedSymbol) {
                                ForEach(availableSymbols, id: \.self) { symbol in
                                    Image(systemName: symbol).tag(symbol)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden() // Hide label as we have Text above
                            .frame(width: 120)
                            .padding(.trailing)
                            ColorPicker("Profilfarbe auswählen", selection: $selectedColor, supportsOpacity: false)
                                .labelsHidden()
                                .frame(width: 120)
                                .padding(.trailing)
                                .help("Wählen Sie eine Farbe für das Profilsymbol")
                                .accessibilityLabel("Profilfarbe auswählen")
                            Image(systemName: selectedSymbol)
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .padding(9)
                                .background(
                                    Circle()
                                        .fill(selectedColor)
                                        .frame(width: 40, height: 40)
                                )
                        }
                    }
                }
                header: {
                    Text("Profilbild")
                        .font(.headline)
                        .padding(.bottom, 4) // Add consistent padding to match other views
                }
                
                // Spacer() // Removed Spacer from inside the Form
                
            } // End of Form
            // Add padding around the Form content
            .padding(20) // Use consistent 20pt padding like other views 
            // Remove padding from Form, manage padding in VStack/HStack
            // .padding()
            
            Spacer() // Add Spacer in VStack to push buttons down if form content is short

            // --- Buttons placed outside Form, at the bottom of VStack --- 
            HStack {
                Button("Abbrechen") {
                   isPresented = false
               }
               .keyboardShortcut(.cancelAction)
               // Remove specific bottom padding, handle with HStack padding
               // .padding(.bottom)
               
               Spacer() // Push buttons apart
               
               Button("Speichern") {
                   saveChanges()
               }
               .buttonStyle(.borderedProminent)
               .disabled(isSaveDisabled)
               .keyboardShortcut(.defaultAction)
               // Remove specific bottom padding, handle with HStack padding
               // .padding(.bottom)
            }
            .padding(.horizontal) // Ensure horizontal padding
            .padding(.bottom, 20)   // Explicitly request standard bottom padding
            
        } // End of VStack
        .padding(.bottom)
        .frame(minWidth: 450, minHeight: 500, maxHeight: 500) // Increased dimensions
        .onAppear(perform: loadAllShares) // Load shares when view appears
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
        // Kerberos requires realm.
        // Non-Kerberos requires username for *new* profiles.
        return profileName.isEmpty ||
               (useKerberos && kerberosRealm.isEmpty) ||
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

    // State for managing selections within the sheet - Use Share.ID
    @State private var selections: Set<Share.ID> = []

    // Filtered list of shares that are not already associated
    private var availableSharesToSelect: [Share] {
        allAvailableShares.filter { !alreadyAssociatedShares.contains($0.networkShare) }
    }

    var body: some View {
        NavigationView { // Use NavigationView for title and buttons
            VStack {
                if availableSharesToSelect.isEmpty {
                    Text("Keine weiteren Shares zum Zuordnen verfügbar.")
                        .foregroundColor(.secondary)
                        .padding()
                    Spacer()
                } else {
                    // Use List with multi-selection binding for macOS
                    List(availableSharesToSelect, selection: $selections) {
                         share in
                         HStack {
                             Image(systemName: "externaldrive") // Or a more specific icon?
                                 .foregroundColor(.secondary)
                             Text(share.shareDisplayName ?? share.networkShare)
                             Spacer()
                             // Remove manual checkmark - rely on standard selection highlight
                             /*
                             if selections.contains(share.networkShare) {
                                 Image(systemName: "checkmark")
                                     .foregroundColor(.blue)
                             }
                             */
                         }
                         // Remove .tag and .onTapGesture
                         // .tag(share.networkShare) // Tag for selection
                         // .contentShape(Rectangle())
                         // .onTapGesture {
                         //     toggleSelection(for: share.networkShare)
                         // }
                    }
                    // Remove .environment for editMode
                    // .environment(\.editMode, .constant(.active)) // Enable multi-select UI
                }
            }
            .navigationTitle("Shares auswählen")
            /* // Temporarily comment out the toolbar in the sheet to test ambiguity
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) { // Use confirmationAction here is fine for the sheet's purpose
                    Button("Hinzufügen") {
                        onAddShares(Array(selections))
                        dismiss()
                    }
                    .disabled(selections.isEmpty)
                }
            }
            */
        }
        .frame(width: 400, height: 500) // Adjust size as needed
    }

    // Remove toggleSelection helper function
    /*
    /// Toggles the selection state for a given share URL.
    private func toggleSelection(for shareURL: String) {
        if selections.contains(shareURL) {
            selections.remove(shareURL)
        } else {
            selections.insert(shareURL)
        }
    }
    */
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
