//
//  NetworkSharesView.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 10.04.25.
//  Copyright © 2024 RRZE. All rights reserved.
//

import SwiftUI
import AppKit
import OSLog

/// View for configuring and interacting with network shares.
///
/// Supports multi-selection via Cmd-click or Shift-click (both toggle individual items,
/// no range selection). Toolbar actions (Connect/Disconnect, Delete) operate on all
/// selected shares simultaneously.
struct NetworkSharesView: View {

    @State private var shares: [Share] = []
    /// UUIDs of currently selected shares. Using Share.id (UUID) rather than networkShare
    /// URL strings avoids issues when two shares point to the same server path.
    @State private var selectedShares: Set<String> = []
    @State private var showAddSheet = false
    @State private var shareToEdit: Share? = nil
    @State private var isDataLoaded = false

    @EnvironmentObject private var mounter: Mounter
    @ObservedObject private var profileManager = AuthProfileManager.shared

    // MARK: - Computed Properties

    private var selectedShareObjects: [Share] {
        shares.filter { selectedShares.contains($0.id) }
    }

    /// True when at least one selected share can be deleted (i.e. is not MDM-managed).
    private var canDelete: Bool {
        !selectedShares.isEmpty && selectedShareObjects.contains(where: { !$0.managed })
    }

    /// True when exactly one non-managed share is selected (editing multiple simultaneously
    /// is not supported).
    private var canEdit: Bool {
        selectedShares.count == 1 && selectedShareObjects.first.map { !$0.managed } ?? false
    }

    /// Label for the Connect/Disconnect toolbar button, derived from the mount states of
    /// all selected shares.
    private var connectButtonLabel: LocalizedStringKey {
        guard !selectedShares.isEmpty else { return "Connect/Disconnect" }
        let selected = selectedShareObjects
        if selected.allSatisfy({ $0.mountStatus == .mounting }) { return "Connecting…" }
        if selected.allSatisfy({ $0.mountStatus == .mounted }) { return "Disconnect" }
        if selected.allSatisfy({ $0.mountStatus != .mounted && $0.mountStatus != .mounting }) { return "Connect" }
        return "Connect/Disconnect"
    }

    /// True when any selected share is actively being mounted (prevents interrupting an in-progress attempt).
    private var anyMounting: Bool {
        selectedShareObjects.contains { $0.mountStatus == .mounting }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading) {

            // Header
            HStack(spacing: 12) {
                Image(systemName: "externaldrive.connected.to.line.below")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 20, height: 20)
                    .foregroundColor(.white)
                    .padding(6)
                    .background(Color.blue)
                    .cornerRadius(6)
                    .frame(width: 32, height: 32)

                VStack(alignment: .leading) {
                    Text("Network Shares")
                        .font(.headline)
                        .fontWeight(.medium)
                    Text("Configure network shares and their connection settings here.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(10)
            .background(.quaternary.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 10))

            // Share list
            VStack(spacing: 0) {
                ForEach(shares) { share in
                    shareRow(for: share)

                    if share.id != shares.last?.id {
                        Divider()
                    }
                }

                if shares.isEmpty {
                    VStack(alignment: .center, spacing: 12) {
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
                    .padding(.vertical, 20)
                }
            }
            .padding(.top, 8)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )

            // Bottom toolbar
            HStack {
                Button(action: { showAddSheet = true }) {
                    Image(systemName: "plus")
                        .frame(width: 16, height: 16)
                }
                .help("Add")

                Button(action: deleteSelectedShares) {
                    Image(systemName: "minus")
                        .frame(width: 16, height: 16)
                }
                .help("Remove")
                .disabled(!canDelete)

                Button(action: handleToolbarEdit) {
                    Image(systemName: "square.and.pencil")
                        .frame(width: 16, height: 16)
                }
                .help("Edit")
                .disabled(!canEdit)

                // MDM hint: only when the single selected share is managed
                if selectedShares.count == 1, let share = selectedShareObjects.first, share.managed {
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

                Button(action: toggleSelectedShares) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.arrow.down")
                        Text(connectButtonLabel)
                            .frame(height: 16)
                    }
                }
                .disabled(selectedShares.isEmpty || anyMounting)
            }
            .padding(8)
            .background(Color(.controlBackgroundColor))
            .padding(.top, 8)
        }
        .padding(20)
        .onAppear {
            Task {
                Logger.networkSharesView.info("📱 NetworkSharesView appearing")
                await loadAllData()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Defaults.nsmReconstructMenuTriggerNotification)) { _ in
            Task { await loadShares() }
        }
        .sheet(isPresented: $showAddSheet) {
            addShareSheet
        }
        .sheet(item: $shareToEdit) { editingShare in
            AddShareView(
                isPresented: Binding(
                    get: { shareToEdit != nil },
                    set: { if !$0 { shareToEdit = nil } }
                ),
                mounter: mounter,
                profileManager: profileManager,
                existingShare: editingShare,
                onSave: handleEditSave
            )
            .onAppear {
                Logger.networkSharesView.info("📋 Edit sheet opening for share: \(editingShare.networkShare)")
            }
        }
    }

    // MARK: - Row View

    @ViewBuilder
    private func shareRow(for share: Share) -> some View {
        let resolvedUsername = share.effectiveUsername(from: profileManager.profiles)

        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(share.resolvedEffectiveMountPoint(username: resolvedUsername))
                    .font(.headline)
                Text(share.resolvedNetworkShare(username: resolvedUsername))
                    .font(.caption)
                    .foregroundColor(.secondary)
                if share.mountStatus == .mounting {
                    Text("Connecting…")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if share.mountStatus == .mounting {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            } else {
                Circle()
                    .fill(mountStatusColor(for: share.mountStatus))
                    .frame(width: 10, height: 10)
                    .help(share.mountStatus.rawValue)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            handleTap(on: share)
        }
        .contextMenu {
            contextMenuItems(for: share)
        }
        .background(selectedShares.contains(share.id) ? Color.accentColor.opacity(0.1) : Color.clear)
    }

    // MARK: - Selection

    /// Handles a tap on a share row with modifier-key awareness:
    /// - Plain tap: replaces the selection with only this share.
    /// - Cmd or Shift: toggles this share in the existing selection without range-selecting
    ///   intermediate items.
    private func handleTap(on share: Share) {
        let flags = NSEvent.modifierFlags
        let isAdditive = flags.contains(.command) || flags.contains(.shift)
        if isAdditive {
            if selectedShares.contains(share.id) {
                selectedShares.remove(share.id)
            } else {
                selectedShares.insert(share.id)
            }
        } else {
            selectedShares = [share.id]
        }
    }

    // MARK: - Toolbar Actions

    /// Mounts or unmounts each selected share based on its current state.
    /// Shares are processed sequentially; the Mounter handles internal parallelism.
    private func toggleSelectedShares() {
        Task {
            for share in selectedShareObjects {
                if share.mountStatus == .mounted {
                    await mounter.unmountShare(for: share, userTriggered: true)
                } else {
                    await mounter.mountGivenShares(userTriggered: true, forShare: share.id)
                }
            }
            await loadShares()
        }
    }

    /// Deletes all selected shares that are not MDM-managed. Managed shares in the
    /// selection are silently skipped.
    private func deleteSelectedShares() {
        Task {
            for share in selectedShareObjects where !share.managed {
                await mounter.removeShare(for: share)
            }
            await loadShares()
        }
    }

    // MARK: - Context Menu

    /// Context menu for a single share row. Always acts on the right-clicked item only,
    /// independent of the current multi-selection.
    @ViewBuilder
    private func contextMenuItems(for share: Share) -> some View {
        Button(share.mountStatus == .mounted ? "Disconnect" : (share.mountStatus == .mounting ? "Connecting…" : "Connect")) {
            Task {
                if share.mountStatus == .mounted {
                    await mounter.unmountShare(for: share, userTriggered: true)
                } else {
                    await mounter.mountGivenShares(userTriggered: true, forShare: share.id)
                }
                await loadShares()
            }
        }
        .disabled(share.mountStatus == .mounting)

        if !share.managed {
            Divider()
            Button("Edit...") {
                handleEditShare(share)
            }
            Divider()
            Button("Delete") {
                Task {
                    await mounter.removeShare(for: share)
                    selectedShares.remove(share.id)
                    await loadShares()
                }
            }
        }
    }

    // MARK: - Data Loading

    private func loadAllData() async {
        Logger.networkSharesView.info("🔄 Loading all data for NetworkSharesView")
        await loadShares()
        Logger.networkSharesView.debug("🔄 ProfileManager has \(profileManager.profiles.count) profiles")
        await MainActor.run {
            isDataLoaded = true
            Logger.networkSharesView.info("✅ All data loaded — shares: \(shares.count), profiles: \(profileManager.profiles.count)")
        }
    }

    private func loadShares() async {
        Logger.networkSharesView.debug("🔄 Loading shares from ShareManager")
        self.shares = await mounter.shareManager.allShares
        Logger.networkSharesView.debug("✅ Loaded \(shares.count) shares")
        // Prune stale selection IDs after the share list changes
        let validIDs = Set(shares.map(\.id))
        selectedShares = selectedShares.intersection(validIDs)
    }

    // MARK: - Mount Status Color

    private func mountStatusColor(for status: MountStatus) -> Color {
        switch status {
        case .mounted:
            return .green
        case .unmounted, .queued, .userUnmounted, .toBeMounted:
            return .gray
        case .missingPassword, .invalidCredentials, .errorOnMount, .obstructingDirectory, .unreachable, .unassignedProfile:
            return .red
        case .mounting, .unknown, .undefined:
            return .orange
        }
    }

    // MARK: - Sheet Views

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

    private func handleAddSave() {
        Logger.networkSharesView.info("💾 Add sheet saved — reloading data")
        Task { await loadShares() }
    }

    private func handleEditSave() {
        Logger.networkSharesView.info("💾 Edit sheet saved — reloading data")
        Task { await loadShares() }
    }

    private func handleEditShare(_ share: Share) {
        Logger.networkSharesView.info("🔧 Starting edit for share: \(share.networkShare)")
        shareToEdit = share
    }

    private func handleToolbarEdit() {
        guard canEdit, let share = selectedShareObjects.first else { return }
        handleEditShare(share)
    }
}

#Preview {
    NetworkSharesView()
}
