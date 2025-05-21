import SwiftUI

// MARK: - Authentication Header View

/// Header View for Authentication Settings Tab
struct AuthenticationHeaderView: View {
    var body: some View {
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
        .padding(10) // Changed to 10 to match other header views
        .background(.quaternary.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        // Removed external padding as this will be handled by the parent view
    }
}

// MARK: - Preview
#Preview {
    AuthenticationHeaderView()
        .padding()
}
