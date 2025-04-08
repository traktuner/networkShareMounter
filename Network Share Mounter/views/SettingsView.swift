import SwiftUI

/// The main settings view that provides a sidebar navigation for different setting categories
struct SettingsView: View {
    /// The currently selected settings tab
    @State private var selection: SettingsTab = .networkShares
    
    /// Enum representing the available settings tabs
    enum SettingsTab: String, CaseIterable, Identifiable {
        case networkShares = "Network Shares"
        case authentication = "Authentifizierung"
        case general = "Allgemein"
        
        var id: String { self.rawValue }
        
        /// Returns the SF Symbol name for each tab
        var icon: String {
            switch self {
            case .networkShares:
                return "network"
            case .authentication:
                return "key.fill"
            case .general:
                return "gearshape"
            }
        }
    }
    
    var body: some View {
        NavigationSplitView {
            // Sidebar with icons and labels
            List(selection: $selection) {
                ForEach(SettingsTab.allCases) { tab in
                    NavigationLink(value: tab) {
                        Label {
                            Text(tab.rawValue)
                        } icon: {
                            Image(systemName: tab.icon)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .listStyle(.sidebar)
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: {}) {
                        Image(systemName: "sidebar.left")
                    }
                }
            }
        } detail: {
            // Content view that changes based on selection
            switch selection {
            case .networkShares:
                NetworkSharesView()
            case .authentication:
                AuthenticationView()
            case .general:
                GeneralSettingsView()
            }
        }
        .navigationTitle("Einstellungen")
        .frame(minWidth: 800, minHeight: 500)
    }
}

#Preview {
    SettingsView()
} 