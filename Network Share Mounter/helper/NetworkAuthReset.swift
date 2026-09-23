//
//  NetworkAuthReset.swift
//  Network Share Mounter
//
//  Copyright © 2026 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation
import OSLog

/// Terminates a stuck NetAuthSysAgent so that launchd restarts it for the next mount attempt.
enum NetworkAuthReset {
    /// - Returns: true if a running NetAuthSysAgent was terminated, false if none was running
    static func perform() async -> Bool {
        Logger.app.info("🔄 Resetting network authentication agent (NetAuthSysAgent)...")

        // killall exits with code 1 when no matching process exists, which cliTask reports as an error
        let agentKilled = (try? await cliTask("/usr/bin/killall", arguments: ["NetAuthSysAgent"])) != nil

        // Allow launchd time to restart the agent before any new mount attempt
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        Logger.app.info("✅ Network authentication reset complete (agentKilled: \(agentKilled, privacy: .public))")
        return agentKilled
    }
}
