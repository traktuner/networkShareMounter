//
//  GeneralSettingsView.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 10.04.25.
//  Copyright © 2024 RRZE. All rights reserved.
//

import SwiftUI
import OSLog

/// View for configuring network shares
struct NetworkSharesView: View {
    // Replace static demo data with state for real data
    @State private var shares: [Share] = []
    @State private var selectedNetworkShare: String?
    @State private var showAddSheet = false
    @State private var shareToEdit: Share? = nil
    @State private var isDataLoaded = false

    // Access the Mounter via SwiftUI Environment
    @EnvironmentObject private var mounter: Mounter
    
    // Access the ProfileManager for share-profile associations
    @ObservedObject private var profileManager = AuthProfileManager.shared

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
                    Text("Network Shares")
                        .font(.headline) // Smaller title font
                        .fontWeight(.medium) // Adjusted weight
                    Text("Configure network shares and their connection settings here.")
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
                            VStack(alignment: .leading, spacing: 4) {
                                // Use effectiveMountPoint for display
                                Text(share.effectiveMountPoint)
                                    .font(.headline)
                                Text(share.networkShare)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
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
                        selectedNetworkShare = share.networkShare
                    }
                    .contextMenu {
                        // Button to Mount/Unmount the selected share
                        Button(share.mountStatus == .mounted ? "Disconnect" : "Connect") {
                            Task {
                                if share.mountStatus == .mounted {
                                    await mounter.unmountShare(for: share, userTriggered: true)
                                } else {
                                    await mounter.mountGivenShares(userTriggered: true, forShare: share.id)
                                }
                                // Reload shares after action
                                await loadShares()
                            }
                        }
                        
                        // Add edit button for non-managed shares
                        if !share.managed {
                            Divider()
                            Button("Edit...") {
                                handleEditShare(share)
                            }
                        }
                        
                        // Button to delete the share (only if not managed)
                        if !share.managed {
                            Divider() // Add divider only if delete is possible
                            Button("Delete") {
                                Task {
                                    await mounter.removeShare(for: share)
                                    if selectedNetworkShare == share.networkShare {
                                        selectedNetworkShare = nil
                                    }
                                    // Reload shares after deletion
                                    await loadShares()
                                }
                            }
                        }
                    }
                    .background(selectedNetworkShare == share.networkShare ? Color.accentColor.opacity(0.1) : Color.clear)
                    
                    if share.networkShare != shares.last?.networkShare {
                        Divider()
                    }
                }
                
                if shares.isEmpty {
                    VStack(alignment: .center, spacing: 12) {
                        // Add icon for better visual appeal
                        Image(systemName: "externaldrive.connected.to.line.below.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary.opacity(0.6))
                            .padding(.bottom, 8)
                            
                        Text("No network shares configured")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("Click '+' to add a new share")
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.8))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 100)
                    .padding(.vertical, 20) // Increase vertical padding for better centering
                }
            }
            .padding(.top, 8)
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
                        .frame(width: 16, height: 16)
                }
//                .frame(width: 28, height: 20)
                .help("Add")
                
                Button(action: {
                    Task {
                        if let currentSelection = selectedNetworkShare,
                           let shareToRemove = shares.first(where: { $0.networkShare == currentSelection }),
                           !shareToRemove.managed {
                                await mounter.removeShare(for: shareToRemove)
                                selectedNetworkShare = nil
                                await loadShares()
                        }
                    }
                }) {
                    Image(systemName: "minus")
                        .frame(width: 16, height: 16)
                }
//                .frame(width: 28, height: 20)
                .help("Remove")
                .disabled(selectedNetworkShare == nil || shares.first(where: { $0.networkShare == selectedNetworkShare })?.managed ?? true)
                
                Button(action: handleToolbarEdit) {
                    Image(systemName: "square.and.pencil")
                        .frame(width: 16, height: 16)
                }
//                .frame(width: 28, height: 20)
                .help("Edit")
                .disabled(selectedNetworkShare == nil || shares.first(where: { $0.networkShare == selectedNetworkShare })?.managed ?? true)
                
                // MDM hint for managed shares
                if let selectedNetworkShare = selectedNetworkShare,
                   let selectedShare = shares.first(where: { $0.networkShare == selectedNetworkShare }),
                   selectedShare.managed {
                    HStack {
                        Image(systemName: "gearshape.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        Text("Defined by MDM policy")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                // Mount/Unmount button
                Button(action: {
                    Task {
                        if let selectedNetworkShare = selectedNetworkShare,
                           let share = shares.first(where: { $0.networkShare == selectedNetworkShare }) {
                            if share.mountStatus == .mounted {
                                await mounter.unmountShare(for: share)
                            } else {
                                await mounter.mountGivenShares(userTriggered: true, forShare: share.id)
                            }
                            await loadShares() // Reload after action
                        }
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.arrow.down")
                        if let selectedNetworkShare = selectedNetworkShare,
                           let share = shares.first(where: { $0.networkShare == selectedNetworkShare }) {
                            Text(share.mountStatus == .mounted ? "Disconnect" : "Connect")
                                .frame(height: 16)
                        } else {
                            Text("Connect/Disconnect")
                                .frame(height: 16)
                        }
                    }
                }
                .disabled(selectedNetworkShare == nil)
            }
            .padding(8) // Make toolbar padding consistent with other views
            .background(Color(.controlBackgroundColor)) // Add a subtle background to match other toolbars
            .padding(.top, 8)
        }
        // Apply consistent outer padding to the entire view (20pt on all sides)
        .padding(20)
        // Load all data when the view appears
        .onAppear {
            Task {
                Logger.networkSharesView.info("📱 NetworkSharesView appearing - mounter available via Environment")
                await loadAllData()
            }
        }
        // Live-Update: Reload shares when Mounter posts a reconstruct notification
        .onReceive(NotificationCenter.default.publisher(for: Defaults.nsmReconstructMenuTriggerNotification)) { _ in
            Task { await loadShares() }
        }
        .sheet(isPresented: $showAddSheet) {
            addShareSheet
        }
        .sheet(item: $shareToEdit, content: { editingShare in
            AddShareView(
                isPresented: Binding(
                    get: { shareToEdit != nil },
                    set: { newValue in if !newValue { shareToEdit = nil } }
                ),
                mounter: mounter,
                profileManager: profileManager,
                existingShare: editingShare,
                onSave: handleEditSave
            )
            .onAppear {
                Logger.networkSharesView.info("📋 Edit sheet opening for share: \(editingShare.networkShare)")
            }
        })
    }
    
    /// Loads all required data including shares and ensures profile manager is ready
    private func loadAllData() async {
        Logger.networkSharesView.info("🔄 Loading all data for NetworkSharesView")
        
        // Load shares first
        await loadShares()
        
        // Ensure profile manager data is available
        Logger.networkSharesView.debug("🔄 ProfileManager has \(profileManager.profiles.count) profiles")
        
        // Mark data as loaded
        await MainActor.run {
            isDataLoaded = true
            Logger.networkSharesView.info("✅ All data loaded - shares: \(shares.count), profiles: \(profileManager.profiles.count)")
        }
    }
    
    /// Asynchronously loads shares from the ShareManager.
    private func loadShares() async {
        Logger.networkSharesView.debug("🔄 Loading shares from ShareManager")
        self.shares = await mounter.shareManager.allShares
        Logger.networkSharesView.debug("✅ Loaded \(shares.count) shares")

        // If the selected share no longer exists, deselect it
        if let currentSelection = selectedNetworkShare, !shares.contains(where: { $0.networkShare == currentSelection }) {
            selectedNetworkShare = nil
            Logger.networkSharesView.debug("🔄 Deselected share \(currentSelection) as it no longer exists")
        }
    }
    
    /// Returns the appropriate color for the mount status indicator.
    private func mountStatusColor(for status: MountStatus) -> Color {
        switch status {
        case .mounted:
            return .green
        case .unmounted, .queued, .userUnmounted, .toBeMounted:
            return .gray
        case .missingPassword, .invalidCredentials, .errorOnMount, .obstructingDirectory, .unreachable, .unassignedProfile:
            return .red
        case .unknown, .undefined:
            return .orange
        }
    }
    
    // MARK: - Sheet Views
    
    /// Sheet for adding new shares
    @ViewBuilder
    private var addShareSheet: some View {
        AddShareView(
            isPresented: $showAddSheet,
            mounter: mounter,
            profileManager: profileManager,
            onSave: handleAddSave
        )
        .onAppear {
            Logger.networkSharesView.info("➕ Add sheet opening")
        }
    }
    
    /// Handles save action from add sheet
    private func handleAddSave() {
        Logger.networkSharesView.info("💾 Add sheet saved - reloading data")
        Task {
            await loadShares()
        }
    }
    
    /// Handles save action from edit sheet
    private func handleEditSave() {
        Logger.networkSharesView.info("💾 Edit sheet saved - reloading data")
        Task {
            await loadShares()
        }
    }
    
    /// Handles edit share action
    private func handleEditShare(_ share: Share) {
        Logger.networkSharesView.info("🔧 Starting edit for share: \(share.networkShare)")
        Logger.networkSharesView.debug("🔧 Current shareToEdit state: \(shareToEdit?.networkShare ?? "nil")")
        Logger.networkSharesView.debug("🔧 Data loaded state: \(isDataLoaded)")
        Logger.networkSharesView.debug("🔧 ProfileManager profiles count: \(profileManager.profiles.count)")
        
        // Store the Share object directly to avoid race conditions
        shareToEdit = share
    }
    
    /// Handles toolbar edit button
    private func handleToolbarEdit() {
        if let networkShare = selectedNetworkShare,
           let selectedShare = shares.first(where: { $0.networkShare == networkShare }),
           !selectedShare.managed {
            handleEditShare(selectedShare)
        }
    }
}

#Preview {
    NetworkSharesView()
} 
