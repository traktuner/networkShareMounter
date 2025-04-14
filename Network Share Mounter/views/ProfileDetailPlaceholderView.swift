import SwiftUI

// MARK: - Profile Detail Placeholder View

// Placeholder view shown when no profile is selected in the detail column
struct ProfileDetailPlaceholderView: View {
    var body: some View {
        VStack(alignment: .center) { 
            Text("Wählen Sie ein Profil aus oder erstellen Sie ein neues Profil")
                .foregroundColor(.secondary)
                // Optional: Center placeholder text vertically if needed
                // .frame(maxHeight: .infinity, alignment: .center)
        }
        // Give the placeholder some padding and make it fill width
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(20) 
    }
}

// MARK: - Preview

#Preview {
    ProfileDetailPlaceholderView()
        .frame(width: 300, height: 300)
}
