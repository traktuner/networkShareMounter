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
        .padding(12) // Internal padding
        .background(.quaternary.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(10) // External padding
    }
}

// MARK: - Preview
#Preview {
    AuthenticationHeaderView()
        .padding()
}
