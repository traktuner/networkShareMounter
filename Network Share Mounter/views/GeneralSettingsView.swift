import SwiftUI

/// View for configuring general application settings
struct GeneralSettingsView: View {
    // Example state - would be connected to real data in a functional implementation
    @State private var startAtLogin = true
    @State private var sendDiagnosticData = false
    @State private var enableAutoUpdate = true
    @State private var checkForUpdatesAutomatically = true
    @State private var installUpdatesAutomatically = false
    @State private var selectedUpdateChannel = UpdateChannel.stable
    
    /// Enum for update channels
    enum UpdateChannel: String, CaseIterable, Identifiable {
        case stable = "Stabil"
        case beta = "Beta"
        
        var id: String { self.rawValue }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                
                // Header Section
                HStack(spacing: 12) {
                    Image(systemName: "gearshape") // Icon for General
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 20, height: 20)
                        .foregroundColor(.white)
                        .padding(6)
                        .background(Color.gray) // Background color for General
                        .cornerRadius(6)
                        .frame(width: 32, height: 32)
                        
                    VStack(alignment: .leading) {
                        Text("Allgemein") // Title
                            .font(.headline)
                            .fontWeight(.medium)
                        Text("Passen Sie hier allgemeine Einstellungen der Anwendung an.") // Description
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(12)
                .background(.quaternary.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(.bottom, 20)
                
                // Startup section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Programmstart")
                        .font(.headline)
                    
                    Toggle("Beim Anmelden starten", isOn: $startAtLogin)
                }
                
                // Diagnostic data section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Diagnosedaten")
                        .font(.headline)
                    
                    Toggle("Anonyme Diagnosedaten senden", isOn: $sendDiagnosticData)
                }
                
                // Update section
                VStack(alignment: .leading, spacing: 14) {
                    Text("Software-Aktualisierung")
                        .font(.headline)
                    
                    Toggle("Automatische Updates aktivieren", isOn: $enableAutoUpdate)
                    
                    if enableAutoUpdate {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Automatisch nach Updates suchen", isOn: $checkForUpdatesAutomatically)
                                .padding(.leading, 20)
                            
                            Toggle("Updates automatisch installieren", isOn: $installUpdatesAutomatically)
                                .disabled(!checkForUpdatesAutomatically)
                                .padding(.leading, 20)
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Update-Kanal")
                                
                                Picker("", selection: $selectedUpdateChannel) {
                                    ForEach(UpdateChannel.allCases) { channel in
                                        Text(channel.rawValue).tag(channel)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 240)
                            }
                            .padding(.leading, 20)
                            .padding(.top, 4)
                            
                            HStack {
                                Button {
                                    // Would check for updates in actual implementation
                                } label: {
                                    HStack {
                                        Image(systemName: "arrow.clockwise")
                                        Text("Jetzt nach Updates suchen")
                                    }
                                }
                            }
                            .padding(.leading, 20)
                            .padding(.top, 4)
                        }
                    }
                }
                
                // Version info section
                VStack(alignment: .leading, spacing: 14) {
                    Text("Über")
                        .font(.headline)
                    
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0 (123)")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Build-Datum")
                        Spacer()
                        Text("08.04.2024")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .animation(.easeInOut(duration: 0.2), value: enableAutoUpdate)
        .animation(.easeInOut(duration: 0.2), value: sendDiagnosticData)
    }
}

#Preview {
    GeneralSettingsView()
} 
