//
//  ProfileRowView.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 10.08.25.
//  Copyright © 2026 RRZE. All rights reserved.
//

import SwiftUI
import OSLog
import dogeADAuth // For KlistUtil - Assuming it's here

// MARK: - Profile Row View

/// View for displaying a single row in the profile list.
struct ProfileRowView: View {
    // Dependencies
    @ObservedObject var profileManager: AuthProfileManager
    let profileId: String
    
    // State to hold the result of the Kerberos ticket check
    @State private var ticketStatus: TicketStatus = .unknown

    // Logger
    private static var logger = Logger.authenticationView // Assuming this logger is accessible
    
    var body: some View {
        if let profile = profileManager.getProfile(by: profileId) {
            rowContent(for: profile)
        }
    }

    @ViewBuilder
    private func rowContent(for profile: AuthProfile) -> some View {
        HStack(spacing: 10) {
            Image(systemName: profile.symbolName ?? "person.circle")
                .foregroundColor(.white)
                .padding(6)
                .background(
                    Circle()
                        .fill(profile.symbolColor)
                        .frame(width: 28, height: 28)
                )

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(profile.displayName)
                        .font(.headline)

                    if profileManager.isDefaultRealmProfile(profile) {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .help("Default Kerberos profile (not deletable)")
                    }
                }

                if profile.useKerberos {
                    HStack(spacing: 4) {
                        Text("Kerberos:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(profile.kerberosRealm ?? "N/A")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(.ultraThinMaterial)
                            .cornerRadius(3)
                    }
                } else {
                    Text(profile.username ?? "N/A")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if profile.useKerberos {
                Circle()
                    .fill(ticketStatus.color)
                    .frame(width: 10, height: 10)
                    .help(ticketStatus.helpText)
            }
        }
        .padding(.vertical, 6)
        .task(id: profile.id) {
            await checkTicketStatus(for: profile)
        }
    }

    private func checkTicketStatus(for profile: AuthProfile) async {
        let status = await checkKerberosTicketStatus(for: profile)
        await MainActor.run {
            ticketStatus = status
        }
        Self.logger.debug("(RowView) Ticket status for profile '\(profile.displayName)': \(status.displayText)")
    }
}

// MARK: - Preview

struct ProfileRowView_Previews: PreviewProvider {
    static let mockProfileManager = AuthProfileManager.shared
    static let profile1 = AuthProfile(displayName: "Test Profile 1", username: "test1")
    static let profile2 = AuthProfile(displayName: "Test Profile 2", username: "test2", useKerberos: true, kerberosRealm: "EXAMPLE.COM")
    
    static var previews: some View {
        // Preview for non-Kerberos profile
        ProfileRowView(profileManager: mockProfileManager, profileId: profile1.id)
            .padding()
            .previewDisplayName("Standard Profile")
            .onAppear {
                mockProfileManager.profiles = [profile1]
            }

        // Preview for Kerberos profile
        ProfileRowView(profileManager: mockProfileManager, profileId: profile2.id)
            .padding()
            .previewDisplayName("Kerberos Profile")
            .onAppear {
                mockProfileManager.profiles = [profile2]
            }
    }
}

