import SwiftUI

// MARK: - Profile Detail Placeholder View

// Placeholder view shown when no profile is selected in the detail column
struct ProfileDetailPlaceholderView: View {
    var body: some View {
        VStack(alignment: .center, spacing: 12) { 
            // Add icon for better visual appeal
            Image(systemName: "person.badge.key.fill")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.6))
                .padding(.bottom, 8)
                
            Text("Wählen Sie ein Profil aus oder erstellen Sie ein neues Profil")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        // Center content both horizontally and vertically
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

// MARK: - Preview

#Preview {
    ProfileDetailPlaceholderView()
        .frame(width: 300, height: 300)
}
