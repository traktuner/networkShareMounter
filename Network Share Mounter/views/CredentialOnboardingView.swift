import SwiftUI
import OSLog

/// One-time credential setup sheet shown when NSM detects missing credentials for a
/// configured Kerberos realm or MDM password shares.
///
/// On save: creates the necessary AuthProfiles and links MDM password shares.
/// On "Not Now": sets a 7-day snooze so the sheet stays out of the way.
struct CredentialOnboardingView: View {
    let info: CredentialOnboardingInfo
    let mounter: Mounter
    let onComplete: () -> Void
    let onSnooze: () -> Void

    @State private var username: String
    @State private var password = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private let logger = Logger.app

    init(info: CredentialOnboardingInfo, mounter: Mounter, onComplete: @escaping () -> Void, onSnooze: @escaping () -> Void) {
        self.info = info
        self.mounter = mounter
        self.onComplete = onComplete
        self.onSnooze = onSnooze
        _username = State(initialValue: info.suggestedUsername)
    }

    private var canSave: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.isEmpty &&
        !isSaving
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Label(NSLocalizedString("Network Credentials Required", comment: "Credential onboarding title"), systemImage: "person.badge.key")
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text(subtitleText)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // Credential fields
                    GroupBox {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Text(NSLocalizedString("Username:", comment: "Credential onboarding username label"))
                                    .frame(width: 80, alignment: .trailing)
                                TextField(NSLocalizedString("username", comment: "Username placeholder"), text: $username)
                                    .textFieldStyle(.roundedBorder)
                                    .autocorrectionDisabled()
                            }

                            HStack {
                                Text(NSLocalizedString("Password:", comment: "Credential onboarding password label"))
                                    .frame(width: 80, alignment: .trailing)
                                SecureField(NSLocalizedString("password", comment: "Password placeholder"), text: $password)
                                    .textFieldStyle(.roundedBorder)
                            }

                            if let error = errorMessage {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(16)
                    } label: {
                        Label(NSLocalizedString("Credentials", comment: "Credential onboarding section label"), systemImage: "key")
                            .font(.headline)
                    }

                    // Context: what these credentials will be used for
                    if info.kerberosRealm != nil || !info.unassignedPasswordShares.isEmpty {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 8) {
                                if let realm = info.kerberosRealm {
                                    Label(String(format: NSLocalizedString("Kerberos authentication for realm: %@", comment: "Kerberos realm context"), realm), systemImage: "checkmark.shield")
                                        .font(.caption)
                                }
                                if !info.unassignedPasswordShares.isEmpty {
                                    Label(String(format: NSLocalizedString("%d network share(s) requiring a password profile", comment: "Password shares context"), info.unassignedPasswordShares.count), systemImage: "externaldrive.connected.to.line.below")
                                        .font(.caption)
                                    ForEach(info.unassignedPasswordShares.prefix(5), id: \.id) { share in
                                        Text("  • \(share.effectiveMountPoint)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    if info.unassignedPasswordShares.count > 5 {
                                        Text(String(format: NSLocalizedString("  … and %d more", comment: "More shares truncation"), info.unassignedPasswordShares.count - 5))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .padding(12)
                        } label: {
                            Text(NSLocalizedString("These credentials will be used for:", comment: "Credential onboarding usage context header"))
                                .font(.headline)
                        }
                    }
                }
                .padding(24)
            }

            Divider()

            HStack {
                Button(NSLocalizedString("Not Now", comment: "Credential onboarding snooze button")) {
                    onSnooze()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                if isSaving {
                    ProgressView()
                        .scaleEffect(0.8)
                        .padding(.trailing, 8)
                }

                Button(NSLocalizedString("Set Up", comment: "Credential onboarding save button")) {
                    Task { await save() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(minWidth: 480, minHeight: 400)
    }

    private var subtitleText: String {
        if info.kerberosRealm != nil && !info.unassignedPasswordShares.isEmpty {
            return NSLocalizedString("Enter your network credentials to set up Kerberos authentication and mount your network shares.", comment: "Credential onboarding subtitle – both")
        } else if info.kerberosRealm != nil {
            return NSLocalizedString("Enter your network credentials to set up Kerberos authentication.", comment: "Credential onboarding subtitle – Kerberos only")
        } else {
            return NSLocalizedString("Enter your network credentials to mount your network shares.", comment: "Credential onboarding subtitle – password only")
        }
    }

    @MainActor
    private func save() async {
        isSaving = true
        errorMessage = nil
        let trimmedUser = username.trimmingCharacters(in: .whitespaces)

        do {
            try await AuthProfileManager.shared.createOnboardingProfiles(
                username: trimmedUser,
                password: password,
                info: info,
                shareManager: mounter.shareManager
            )
            logger.info("✅ Credential onboarding completed for user: \(trimmedUser, privacy: .public)")
            onComplete()
        } catch {
            logger.error("❌ Credential onboarding failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }
}
