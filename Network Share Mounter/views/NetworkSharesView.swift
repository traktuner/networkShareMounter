//
//  GeneralSettingsView.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 10.04.25.
//  Copyright © 2024 RRZE. All rights reserved.
//

import SwiftUI
import OSLog

/// Delegate to access AppDelegate methods and properties
let appDelegate = NSApplication.shared.delegate as! AppDelegate

/// View for configuring network shares
struct NetworkSharesView: View {
    // Replace static demo data with state for real data
    @State private var shares: [Share] = []
    @State private var selectedShareID: String?
    @State private var showAddSheet = false
    // @State private var showProfileSelector = false // Deactivated for now
    // @State private var shareToAssignProfile: Share? // Deactivated for now
    
    // Access the Mounter to interact with shares
    private let mounter = appDelegate.mounter!

    var body: some View {
        VStack(alignment: .leading) {
            
            // Header Section
            HStack(spacing: 12) {
                Image(systemName: "externaldrive.connected.to.line.below") // Icon for Network Shares
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20) // Smaller icon size
                    .foregroundColor(.white)
                    .padding(6) // Slightly reduced padding
                    .background(Color.blue) // Background color for Network Shares
                    .cornerRadius(6) // Slightly smaller corner radius
                    .frame(width: 32, height: 32) // Overall smaller icon frame
                    
                VStack(alignment: .leading) {
                    Text("Network Shares") // Title
                        .font(.headline) // Smaller title font
                        .fontWeight(.medium) // Adjusted weight
                    Text("Konfigurieren Sie hier die Netzwerk-Shares und deren Verbindungseinstellungen.") // Description
                        .font(.subheadline) // Explicitly set subheadline font
                        .foregroundColor(.secondary)
                }
                Spacer() // Pushes content to the left
            }
            .padding(10)
            // Apply background and clip shape
            .background(.quaternary.opacity(0.4)) // Subtle background
            .clipShape(RoundedRectangle(cornerRadius: 10))
            
            // List of shares with simple layout
            VStack(spacing: 0) {
                ForEach(shares) { share in
                    HStack {
                        HStack(spacing: 6) {
                            // TODO: Integrate profile data later
//                            // Show associated profile icon if a profile is linked
//                            if let profileSymbol = share.profileSymbol,
//                               let profileColor = share.profileColor {
//                                Image(systemName: profileSymbol)
//                                    .foregroundColor(.white)
//                                    .background(
//                                        Circle()
//                                            .fill(profileColor)
//                                            .frame(width: 24, height: 24)
//                                    )
//                                    .help(share.profileName ?? "")
//                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                // Use shareDisplayName if available, otherwise networkShare
                                Text(share.shareDisplayName ?? share.networkShare)
                                    .font(.headline)
                                Text(share.networkShare)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        // TODO: Integrate profile data later
//                        // Associated profile name
//                        if let profileName = share.profileName {
//                            Text(profileName)
//                                .font(.caption)
//                                .foregroundColor(.secondary)
//                                .padding(.horizontal, 8)
//                        }
                        
                        // Status indicator based on real mountStatus
                        Circle()
                            .fill(mountStatusColor(for: share.mountStatus))
                            .frame(width: 10, height: 10)
                            .help(share.mountStatus.rawValue) // Show status rawValue on hover
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedShareID = share.id
                    }
                    .contextMenu {
                        // Button to Mount/Unmount the selected share
                        Button(share.mountStatus == .mounted ? "Trennen" : "Verbinden") {
                            Task {
                                if share.mountStatus == .mounted {
                                    await mounter.unmountShare(for: share)
                                } else {
                                    await mounter.mountGivenShares(userTriggered: true, forShare: share.id)
                                }
                                // Reload shares after action
                                await loadShares()
                            }
                        }
                        
                        // TODO: Integrate profile actions later
//                        Button(share.profileName == nil ? "Profil zuweisen..." : "Profil ändern...") {
//                            shareToAssignProfile = share
//                            showProfileSelector = true
//                        }
//                        
//                        if share.profileName != nil {
//                            Button("Profilzuweisung aufheben") {
//                                if let index = shares.firstIndex(where: { $0.id == share.id }) {
//                                    // TODO: Implement profile removal logic
//                                }
//                            }
//                        }
//                        
//                        Divider()
                        
                        // Button to delete the share (only if not managed)
                        if !share.managed {
                            Divider() // Add divider only if delete is possible
                            Button("Löschen") {
                                Task {
                                    await mounter.removeShare(for: share)
                                    if selectedShareID == share.id {
                                        selectedShareID = nil
                                    }
                                    // Reload shares after deletion
                                    await loadShares()
                                }
                            }
                        }
                    }
                    .background(selectedShareID == share.id ? Color.accentColor.opacity(0.1) : Color.clear)
                    
                    if share.id != shares.last?.id {
                        Divider()
                    }
                }
                
                if shares.isEmpty {
                    VStack(spacing: 8) {
                        Text("Keine Netzwerk-Shares konfiguriert")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("Klicken Sie auf '+', um einen neuen Share hinzuzufügen")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .padding()
                }
            }
            .background(Color(.controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
            
            // Bottom toolbar with action buttons
            HStack {
                Button(action: { showAddSheet = true }) {
                    Image(systemName: "plus")
                }
                .help("Hinzufügen")
                
                Button(action: {
                    Task {
                        if let selectedID = selectedShareID,
                           let shareToRemove = shares.first(where: { $0.id == selectedID }),
                           !shareToRemove.managed { // Only allow removing unmanaged shares
                                await mounter.removeShare(for: shareToRemove)
                                selectedShareID = nil
                                await loadShares() // Reload after removal
                        }
                    }
                }) {
                    Image(systemName: "minus")
                }
                .help("Entfernen")
                // Disable if no share is selected or if the selected share is managed
                .disabled(selectedShareID == nil || shares.first(where: { $0.id == selectedShareID })?.managed ?? true)
                
                // TODO: Re-enable profile assignment later
//                Button(action: {
//                    if let selectedID = selectedShareID,
//                       let share = shares.first(where: { $0.id == selectedID }) {
//                        shareToAssignProfile = share
//                        showProfileSelector = true
//                    }
//                }) {
//                    Image(systemName: "person.badge.key")
//                }
//                .help("Profil zuweisen")
//                .disabled(selectedShareID == nil)
                
                Spacer()
                
                // Mount/Unmount button
                Button(action: {
                    Task {
                        if let selectedID = selectedShareID,
                           let share = shares.first(where: { $0.id == selectedID }) {
                            if share.mountStatus == .mounted {
                                await mounter.unmountShare(for: share)
                            } else {
                                await mounter.mountGivenShares(userTriggered: true, forShare: share.id)
                            }
                            await loadShares() // Reload after action
                        }
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.up.arrow.down")
                        if let selectedID = selectedShareID,
                           let share = shares.first(where: { $0.id == selectedID }) {
                            Text(share.mountStatus == .mounted ? "Trennen" : "Verbinden")
                        } else {
                            Text("Verbinden/Trennen")
                        }
                    }
                }
                .disabled(selectedShareID == nil)
            }
            .padding(.top, 8)
        }
        // Apply padding only to horizontal and bottom edges
//        .padding([.horizontal, .bottom], 20)
        .padding(20)
        // Load shares when the view appears
        .onAppear {
            Task {
                await loadShares()
            }
        }
        .sheet(isPresented: $showAddSheet) {
            // Present the new AddShareView, passing dependencies
            AddShareView(
                isPresented: $showAddSheet,
                mounter: mounter,
                profileManager: AuthProfileManager.shared, // Assuming singleton access is ok here
                onSave: { 
                    // Reload shares after the sheet is dismissed and save is potentially complete
                    Task {
                        await loadShares()
                    } 
                }
            )
        }
//        .sheet(isPresented: $showProfileSelector) { // Deactivated for now
//            if let share = shareToAssignProfile {
//                ProfileSelectorView(
//                    isPresented: $showProfileSelector,
//                    onProfileSelected: { profileName, profileSymbol, profileColor in
//                        if let index = shares.firstIndex(where: { $0.id == share.id }) {
//                            // TODO: Implement profile assignment logic
//                        }
//                    }
//                )
//            }
//        }
    }
    
    /// Asynchronously loads shares from the ShareManager.
    private func loadShares() async {
        self.shares = await mounter.shareManager.allShares
        // If the selected share no longer exists, deselect it
        if let selectedID = selectedShareID, !shares.contains(where: { $0.id == selectedID }) {
            selectedShareID = nil
        }
    }
    
    /// Returns the appropriate color for the mount status indicator.
    private func mountStatusColor(for status: MountStatus) -> Color {
        switch status {
        case .mounted:
            return .green
        case .unmounted, .queued, .userUnmounted, .toBeMounted:
            return .gray
        case .missingPassword, .invalidCredentials, .errorOnMount, .obstructingDirectory, .unreachable:
            return .red
        case .unknown, .undefined:
            return .orange
        }
    }
}

#Preview {
    NetworkSharesView()
} 
