//
//  RenewKerberosTicketIntent.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 04.02.26.
//  Copyright © 2026 RRZE. All rights reserved.
//

import AppIntents
import Foundation

/// An App Intent that triggers renewal of Kerberos tickets.
///
/// This intent initiates a soft reset of Kerberos authentication, similar to
/// what happens after system wake. It posts a distributed notification that
/// the main app observes to perform the actual ticket renewal via AutomaticSignIn.
///
/// The app is brought to the foreground to provide immediate feedback about
/// the ticket renewal process.
struct RenewKerberosTicketIntent: AppIntent {
    
    /// The localized display title shown in Shortcuts, Siri, and other system surfaces.
    static var title: LocalizedStringResource = LocalizedStringResource("RenewKerberosTicket.Title", table: "Localizable")
    
    /// The localized, user-facing description explaining what this intent does.
    static var description = IntentDescription(LocalizedStringResource("RenewKerberosTicket.Description", table: "Localizable"))
    
    /// Indicates whether the host app should open when the intent is executed.
    static var openAppWhenRun: Bool = true
    
    /// Performs the intent by notifying the main application to renew Kerberos tickets.
    ///
    /// This method posts a distributed notification with the name
    /// `nsmDistributedRenewKerberosTrigger` so that the main app can initiate
    /// the ticket renewal process via `AutomaticSignIn.softReset()`.
    ///
    /// - Returns: An intent result with a success message.
    /// - Throws: Never currently throws. Reserved for future error propagation if needed.
    func perform() async throws -> some IntentResult & ProvidesDialog {
        DistributedNotificationCenter.default().post(
            name: .nsmDistributedRenewKerberosTrigger,
            object: nil
        )
        
        return .result(
            dialog: IntentDialog(LocalizedStringResource("RenewKerberosTicket.Success", table: "Localizable"))
        )
    }
}
