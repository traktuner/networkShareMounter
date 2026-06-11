//
//  ActiveDirectoryProbe.swift
//  networkShareMounter
//
//  Created by Gregor Longariva on 25.11.25.
//  Copyright © 2025 FAU - Regionales Rechenzentrum Erlangen. All rights reserved.
//
import OpenDirectory

enum ActiveDirectoryProbe {
    static func isBound() -> Bool {
        guard
            let session = ODSession.default(),
            let nodeNames = try? session.nodeNames() as? [String]
        else {
            return false
        }
        return nodeNames.contains { $0.hasPrefix("/Active Directory/") }
    }
}

func isActiveDirectoryBound() async -> Bool {
    await Task.detached(priority: .userInitiated) {
        ActiveDirectoryProbe.isBound()
    }.value
}
