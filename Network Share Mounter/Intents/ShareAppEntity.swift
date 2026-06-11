//
//  ShareAppEntity.swift
//  Network Share Mounter
//
//  Copyright © 2026 RRZE. All rights reserved.
//

import AppIntents
import Foundation

/// An App Entity representing a single configured network share.
/// Used by MountShareIntent and UnmountShareIntent to allow Siri and
/// Shortcuts to address individual shares by name.
struct ShareAppEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: LocalizedStringResource("ShareAppEntity.TypeName", table: "Localizable"))
    }
    static var defaultQuery = ShareEntityQuery()

    /// The network share URL — used as stable identifier (e.g. "smb://server/share").
    var id: String
    /// Human-readable display name shown in Shortcuts and Siri.
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

/// Reads configured network shares from UserDefaults for Siri and Shortcuts.
///
/// App Intents run in a separate process without access to the live ShareManager,
/// so this query reads share configurations directly from UserDefaults.
struct ShareEntityQuery: EntityQuery {
    func entities(for ids: [String]) async throws -> [ShareAppEntity] {
        readAllShares().filter { ids.contains($0.id) }
    }

    func suggestedEntities() async throws -> [ShareAppEntity] {
        readAllShares()
    }

    // MARK: - Private helpers

    private func readAllShares() -> [ShareAppEntity] {
        var entities: [ShareAppEntity] = []
        let ud = UserDefaults.standard

        // User-defined shares
        if let userShares = ud.array(forKey: Defaults.userNetworkShares) as? [[String: String]] {
            for dict in userShares {
                if let entity = makeEntity(from: dict) { entities.append(entity) }
            }
        }

        // MDM-managed shares (current format)
        if let mdmShares = ud.array(forKey: Defaults.managedNetworkSharesKey) as? [[String: String]] {
            for dict in mdmShares {
                if let entity = makeEntity(from: dict), !entities.contains(where: { $0.id == entity.id }) {
                    entities.append(entity)
                }
            }
        }

        // MDM-managed shares (legacy string-array format)
        if let legacyShares = ud.array(forKey: Defaults.networkSharesKey) as? [String] {
            for url in legacyShares where !entities.contains(where: { $0.id == url }) {
                entities.append(ShareAppEntity(id: url, name: extractName(from: url)))
            }
        }

        return entities
    }

    private func makeEntity(from dict: [String: String]) -> ShareAppEntity? {
        guard let url = dict[Defaults.networkShare] else { return nil }
        let name = dict[Defaults.shareDisplayNameKey] ?? extractName(from: url)
        return ShareAppEntity(id: url, name: name)
    }

    private func extractName(from url: String) -> String {
        let stripped = url
            .replacingOccurrences(of: "smb://", with: "")
            .replacingOccurrences(of: "afp://", with: "")
            .replacingOccurrences(of: "nfs://", with: "")
        return stripped.split(separator: "/").last.map(String.init) ?? url
    }
}
