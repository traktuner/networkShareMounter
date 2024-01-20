//
//  URL.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 15.12.23.
//  Copyright © 2023 RRZE. All rights reserved.
//  Copyright © 2020 Orchard & Grove, Inc. All rights reserved.
//

import Foundation

extension URL {
    func checkFileExist() -> Bool {
        let path = self.path
        if (FileManager.default.fileExists(atPath: path)) {
            return true
        } else {
            return false
        }
    }
}
