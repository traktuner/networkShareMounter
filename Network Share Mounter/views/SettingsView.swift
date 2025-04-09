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
                return "externaldrive.connected.to.line.below"
            case .authentication:
                return "person.badge.key"
            case .general:
                return "gearshape"
            }
        }
        
        /// Returns the background color for the icon
        var iconBackgroundColor: Color {
            switch self {
            case .networkShares:
                return .blue
            case .authentication:
                return .orange
            case .general:
                return .gray
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
                                .padding(.leading, 8)
                        } icon: {
                            // Create the colored square icon view
                            Image(systemName: tab.icon)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 18, height: 18) // Adjust symbol size
                                .foregroundColor(.white)
                                .padding(5) // Adjust padding inside the square
                                .background(tab.iconBackgroundColor) // Use defined background color
                                .cornerRadius(6) // Adjust corner radius
                                .frame(width: 28, height: 28) // Set overall icon size
                        }
                    }
                    .padding(4)
                }
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200)
            .listStyle(.sidebar)
        } detail: {
            // Wrap the content in a VStack and add a Spacer at the bottom
            VStack(spacing: 0) { 
                // Content view that changes based on selection
                switch selection {
                case .networkShares:
                    NetworkSharesView()
                case .authentication:
                    AuthenticationView()
                case .general:
                    GeneralSettingsView()
                }
                
                Spacer() // Pushes the content above it to the top
            }
        }
        .navigationTitle("Einstellungen")
        .frame(minWidth: 850, minHeight: 500)
    }
}

#Preview {
    SettingsView()
} 
