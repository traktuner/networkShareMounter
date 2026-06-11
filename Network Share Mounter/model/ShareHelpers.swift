//
//  ShareHelpers.swift
//  Network Share Mounter
//
//  Created for configurable mount point names feature
//  Copyright © 2024 Regionales Rechenzentrum Erlangen. All rights reserved.
//

import Foundation

extension String {
    var isValidMountPointName: Bool {
        guard !self.isEmpty, self.trimmingCharacters(in: .whitespaces) == self else {
            return false
        }

        guard self.count <= 200 else {
            return false
        }

        var invalidCharacters = CharacterSet(charactersIn: "/")
        invalidCharacters.formUnion(.newlines)
        invalidCharacters.formUnion(.illegalCharacters)
        invalidCharacters.formUnion(.controlCharacters)

        return self.rangeOfCharacter(from: invalidCharacters) == nil
    }
}

func extractShareName(from urlString: String) -> String {
    guard let url = URL(string: urlString) else {
        return "share"
    }

    let lastComponent = url.lastPathComponent

    guard !lastComponent.isEmpty else {
        return "share"
    }

    return lastComponent
}
