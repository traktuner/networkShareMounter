import AppIntents
import SwiftUI

struct UnmountAllSharesIntent: AppIntent {
    // Titel/Beschreibung aus eurem String-Katalog (Table: "Localizable")
    static var title: LocalizedStringResource = LocalizedStringResource("UnmountAllShares.Title", table: "Localizable")
    static var description = IntentDescription(LocalizedStringResource("UnmountAllShares.Description", table: "Localizable"))

    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        // Triggert euren bestehenden Unmount-Flow
        NotificationCenter.default.post(name: Defaults.nsmUnmountTriggerNotification, object: nil)

        // Optional direkt unmounten, falls App bereits läuft
        if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
            await appDelegate.mounter?.unmountAllMountedShares(userTriggered: true)
        }
        return .result()
    }
}
