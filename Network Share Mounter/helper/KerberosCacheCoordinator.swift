//
//  KerberosCacheCoordinator.swift
//  Network Share Mounter
//
//  Copyright © 2026 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation
import OSLog
import dogeADAuth

/// Serializes all changes of the default Kerberos credential cache.
///
/// NetFS authenticates Kerberos mounts with whatever cache is the default at mount time.
/// With several caches (e.g. Platform SSO plus an on-prem realm) the cache of the share's
/// realm must be made the default for the duration of the mount, and nobody else
/// (e.g. `AutomaticSignIn`) may switch the default in the meantime.
actor KerberosCacheCoordinator {
    static let shared = KerberosCacheCoordinator()

    /// Returned by `activateCache` and handed back to `finish` after the mount
    struct Lease: Sendable {
        fileprivate let cacheToRestore: String?
    }

    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Waits until no one else holds exclusive access to the default cache
    func acquire() async {
        guard isBusy else {
            isBusy = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
    }

    /// Hands exclusive access to the next waiter, or frees it
    func release() {
        if waiters.isEmpty {
            isBusy = false
        } else {
            waiters.removeFirst().resume()
        }
    }

    /// Acquires exclusive access and makes the best matching cache for the realm the default.
    /// Every call must be balanced by `finish(_:)`.
    func activateCache(forRealm realm: String, principal: String?) async -> Lease {
        await acquire()

        let klist = KlistUtil()
        let caches = await klist.listCaches()
        guard let target = Self.bestCache(in: caches, realm: realm, principal: principal) else {
            Logger.kerberos.warning("⚠️ No valid Kerberos credential cache for realm \(realm, privacy: .public) (\(caches.count, privacy: .public) cache(s) present)")
            return Lease(cacheToRestore: nil)
        }
        guard !target.isDefault else {
            return Lease(cacheToRestore: nil)
        }

        let previousDefault = caches.first(where: \.isDefault)?.cacheName
        Logger.kerberos.info("🔀 Switching default Kerberos cache to \(target.principal, privacy: .public) for realm \(realm, privacy: .public)")
        guard await klist.switchDefaultCache(to: target.cacheName) else {
            return Lease(cacheToRestore: nil)
        }
        return Lease(cacheToRestore: previousDefault)
    }

    /// Restores the previous default cache (if it was switched) and releases exclusive access
    func finish(_ lease: Lease) async {
        if let cacheName = lease.cacheToRestore {
            Logger.kerberos.debug("🔀 Restoring previous default Kerberos cache")
            await KlistUtil().switchDefaultCache(to: cacheName)
        }
        release()
    }

    /// Picks the valid cache for a realm: exact principal match first, then the current
    /// default cache, then the cache that is valid the longest.
    static func bestCache(in caches: [CredentialCache], realm: String, principal: String?) -> CredentialCache? {
        let candidates = caches.filter {
            !$0.isExpired && $0.realm.caseInsensitiveCompare(realm) == .orderedSame
        }
        if let principal,
           let exactMatch = candidates.first(where: { $0.principal.caseInsensitiveCompare(principal) == .orderedSame }) {
            return exactMatch
        }
        return candidates.first(where: \.isDefault) ?? candidates.max(by: { $0.expires < $1.expires })
    }

    /// Builds the Kerberos principal for a username (with or without domain part) and realm
    static func principal(forUsername username: String, realm: String) -> String {
        let localPart = username.split(separator: "@").first.map(String.init) ?? username
        return "\(localPart)@\(realm.uppercased())"
    }
}
