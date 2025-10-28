//
//  Notifications.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 28.10.25.
//  Copyright © 2025 RRZE. All rights reserved.
//

import Foundation

/// Namespaced notification identifiers used for interprocess communication
/// between the App Intents extension and the main application.
///
/// These notification names are posted via ``DistributedNotificationCenter``
/// from intents like ``MountAllSharesIntent`` and ``UnmountAllSharesIntent``.
/// The main app observes them (see ``ActivityController/startMonitoring()``)
/// to perform the corresponding mount/unmount operations.
///
/// - Important: Use `DistributedNotificationCenter` (not `NotificationCenter`)
///   when posting or observing these notifications, as the intents extension
///   runs in a separate process from the host app.
extension NSNotification.Name {
    /// Triggers an unmount of all currently mounted shares in the main app.
    ///
    /// Posted by the App Intents extension (see ``UnmountAllSharesIntent``),
    /// and observed by the main app to initiate the unmount workflow.
    static let nsmDistributedUnmountTrigger = NSNotification.Name("nsmDistributedUnmountTrigger")

    /// Triggers a mount of all configured shares in the main app.
    ///
    /// Posted by the App Intents extension (see ``MountAllSharesIntent``),
    /// and observed by the main app to initiate the mount workflow.
    static let nsmDistributedMountTrigger = NSNotification.Name("nsmDistributedMountTrigger")
}

