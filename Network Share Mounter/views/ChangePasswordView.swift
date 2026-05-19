//
//  ChangePasswordView.swift
//  Network Share Mounter
//
//  Copyright © 2025 RRZE. All rights reserved.
//

import SwiftUI

/// Sheet that lets the user change their Active Directory password in-app via kpasswd.
///
/// Shown from `PasswordExpirationView` when no `passwordChangeURL` is configured but the
/// Kerberos session supports an in-app password change.
struct ChangePasswordView: View {
    let userPrincipal: String
    let onChangePassword: (String, String) async throws -> Void
    let onDismiss: () -> Void

    @State private var oldPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var isChanging = false
    @State private var errorMessage: String?

    private var passwordsMatch: Bool { newPassword == confirmPassword }
    private var canSubmit: Bool {
        !oldPassword.isEmpty && !newPassword.isEmpty && passwordsMatch && !isChanging
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(NSLocalizedString("Change Password", comment: "Change password sheet title"))
                    .font(.headline)
                Text(userPrincipal)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                SecureField(NSLocalizedString("Current Password", comment: "Old password field label"), text: $oldPassword)
                    .textFieldStyle(.roundedBorder)
                SecureField(NSLocalizedString("New Password", comment: "New password field label"), text: $newPassword)
                    .textFieldStyle(.roundedBorder)
                SecureField(NSLocalizedString("Confirm New Password", comment: "Confirm new password field label"), text: $confirmPassword)
                    .textFieldStyle(.roundedBorder)
            }

            if !confirmPassword.isEmpty && !passwordsMatch {
                Text(NSLocalizedString("Passwords do not match.", comment: "Password mismatch validation message"))
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Spacer()
                Button(NSLocalizedString("Cancel", comment: "Cancel password change")) {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(isChanging)

                Button(NSLocalizedString("Change Password", comment: "Confirm in-app password change")) {
                    Task {
                        isChanging = true
                        errorMessage = nil
                        do {
                            try await onChangePassword(oldPassword, newPassword)
                        } catch {
                            errorMessage = error.localizedDescription
                            isChanging = false
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)
            }
        }
        .padding(20)
        .frame(width: 340)
        .overlay {
            if isChanging {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.ultraThinMaterial)
            }
        }
    }
}

// MARK: - Preview

#Preview("Change Password") {
    ChangePasswordView(
        userPrincipal: "jdoe@EXAMPLE.COM",
        onChangePassword: { _, _ in try await Task.sleep(for: .seconds(1)) },
        onDismiss: {}
    )
}
