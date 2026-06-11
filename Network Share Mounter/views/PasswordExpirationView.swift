//
//  PasswordExpirationView.swift
//  Network Share Mounter
//
//  Copyright © 2025 RRZE. All rights reserved.
//

import SwiftUI
import AppKit

/// Dialog shown when the user's AD password is about to expire or has already expired.
///
/// The available actions depend on configuration:
/// - `passwordChangeURL` set → "Change Password" button opens the URL in the default browser
/// - `onChangePassword` set  → "Change Password" button presents an in-app kpasswd sheet
/// - Neither configured      → informational text only with an "OK" button
///
/// This design mirrors Apple's Kerberos SSO Extension and Jamf Connect behaviour.
struct PasswordExpirationView: View {
    let daysRemaining: Int
    let userPrincipal: String
    let passwordChangeURL: URL?
    /// Closure for in-app password change (kpasswd). Only set when `passwordChangeURL` is nil
    /// and the Kerberos session supports changing the password directly.
    let onChangePassword: ((String, String) async throws -> Void)?
    let onDismiss: () -> Void

    @State private var showingChangePassword = false

    private var changeActionAvailable: Bool { passwordChangeURL != nil || onChangePassword != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerRow
            Text(bodyText)
                .fixedSize(horizontal: false, vertical: true)
            actionRow
        }
        .padding(20)
        .frame(width: 380)
        .sheet(isPresented: $showingChangePassword) {
            ChangePasswordView(
                userPrincipal: userPrincipal,
                onChangePassword: onChangePassword ?? { _, _ in },
                onDismiss: { showingChangePassword = false }
            )
        }
    }

    // MARK: - Sub-views

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: daysRemaining <= 0 ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(daysRemaining <= 0 ? Color.red : Color.orange)
                .frame(width: 44)

            VStack(alignment: .leading, spacing: 4) {
                Text(titleText)
                    .font(.headline)
                Text(userPrincipal)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)
        }
    }

    private var actionRow: some View {
        HStack {
            Spacer()
            if daysRemaining > 0 {
                Button(NSLocalizedString("Later", comment: "Dismiss password expiration warning")) {
                    onDismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            if let url = passwordChangeURL {
                Button(NSLocalizedString("Change Password\u{2026}", comment: "Open URL to change AD password")) {
                    NSWorkspace.shared.open(url)
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            } else if onChangePassword != nil {
                Button(NSLocalizedString("Change Password\u{2026}", comment: "Open in-app kpasswd sheet")) {
                    showingChangePassword = true
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            } else {
                Button(NSLocalizedString("OK", comment: "Dismiss informational password expiration dialog")) {
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Computed text

    private var titleText: String {
        if daysRemaining <= 0 {
            return NSLocalizedString("Password Expired", comment: "Password expiration title - already expired")
        } else if daysRemaining == 1 {
            return NSLocalizedString("Password Expires Tomorrow", comment: "Password expiration title - expires in one day")
        } else {
            return String(format: NSLocalizedString("Password Expires in %d Days", comment: "Password expiration title - expires in N days"), daysRemaining)
        }
    }

    private var bodyText: String {
        if daysRemaining <= 0 {
            if changeActionAvailable {
                return NSLocalizedString(
                    "Your Active Directory password has expired. Please change it immediately to regain access.",
                    comment: "Body text - password expired, change action available"
                )
            } else {
                return NSLocalizedString(
                    "Your Active Directory password has expired. Please contact your IT administrator to reset it.",
                    comment: "Body text - password expired, no change action"
                )
            }
        } else {
            let daysWord = daysRemaining == 1
                ? NSLocalizedString("tomorrow", comment: "Used in: 'your password expires tomorrow'")
                : String(format: NSLocalizedString("in %d days", comment: "Used in: 'your password expires in N days'"), daysRemaining)
            if changeActionAvailable {
                return String(
                    format: NSLocalizedString(
                        "Your Active Directory password expires %@. Please change it now to avoid being locked out.",
                        comment: "Body text - password expiring soon, change action available"
                    ),
                    daysWord
                )
            } else {
                return String(
                    format: NSLocalizedString(
                        "Your Active Directory password expires %@. Please contact your IT administrator to change it in time.",
                        comment: "Body text - password expiring soon, no change action"
                    ),
                    daysWord
                )
            }
        }
    }
}

// MARK: - Preview

#Preview("Expires in 7 days, with URL") {
    PasswordExpirationView(
        daysRemaining: 7,
        userPrincipal: "jdoe@EXAMPLE.COM",
        passwordChangeURL: URL(string: "https://selfservice.example.com/change-password"),
        onChangePassword: nil,
        onDismiss: {}
    )
}

#Preview("Expires tomorrow, in-app change") {
    PasswordExpirationView(
        daysRemaining: 1,
        userPrincipal: "jdoe@EXAMPLE.COM",
        passwordChangeURL: nil,
        onChangePassword: { _, _ in },
        onDismiss: {}
    )
}

#Preview("Already expired, no change action") {
    PasswordExpirationView(
        daysRemaining: -3,
        userPrincipal: "jdoe@EXAMPLE.COM",
        passwordChangeURL: nil,
        onChangePassword: nil,
        onDismiss: {}
    )
}
