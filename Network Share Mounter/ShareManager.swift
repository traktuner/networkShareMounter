//
//  ShareManager.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 10.08.23.
//  Copyright © 2023 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation

/// class `ShareManager` to manage the shares (array fo Share)
class ShareManager {
    private var sharesLock = os_unfair_lock()
    private var _shares: [Share] = []
    
    /// Add a share
    func addShare(_ share: Share) {
        os_unfair_lock_lock(&sharesLock)
        if !allShares.contains(where: { $0.networkShare == share.networkShare }) {
            _shares.append(share)
        }
        os_unfair_lock_unlock(&sharesLock)
    }
    
    /// Remove a share at a specific index
    func removeShare(at index: Int) {
        os_unfair_lock_lock(&sharesLock)
        _shares.remove(at: index)
        os_unfair_lock_unlock(&sharesLock)
    }
    
    /// Get all shares
    var allShares: [Share] {
        os_unfair_lock_lock(&sharesLock)
        defer { os_unfair_lock_unlock(&sharesLock) }
        return _shares
    }
    
    /// Update a share at a specific index
    func updateShare(at index: Int, withUpdatedShare updatedShare: Share) {
        os_unfair_lock_lock(&sharesLock)
        guard index >= 0 && index < _shares.count else {
            os_unfair_lock_unlock(&sharesLock)
            return
        }
        _shares[index] = updatedShare
        os_unfair_lock_unlock(&sharesLock)
    }
    
    /// Update the mount status of a share at a specific index
    /// - Parameters:
    ///   - index: The index of the share to update
    ///   - newMountStatus: The new mount status to set
    func updateMountStatus(at index: Int, to newMountStatus: MountStatus) {
        os_unfair_lock_lock(&sharesLock)
        defer { os_unfair_lock_unlock(&sharesLock) }
        
        guard index >= 0 && index < _shares.count else {
            return
        }
        _shares[index].updateMountStatus(to: newMountStatus)
    }
}
