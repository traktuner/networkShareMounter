//
//  Notifications.swift
//
//  Created by Longariva, Gregor (RRZE) on 15.12.23.
//  Copyright © 2020 Orchard & Grove, Inc. All rights reserved.
//  Copyright © 2023 RRZE. All rights reserved.
//


import Foundation

let kUpdateNotificationName = "de.fau.rrze.nomad.update"
let updateNotification = Notification(name: Notification.Name(rawValue: "de.fau.rrze.nomad.update"))

func createNotification(name: String) {

    let notification = Notification(name: Notification.Name(rawValue: name))
    NotificationQueue.default.enqueue(notification, postingStyle: .now)
}
