//
//  AutomaticSignIn.swift
//  Network Share Mounter
//
//  Created by Longariva, Gregor (RRZE) on 15.12.23.
//  Copyright © 2020 Orchard & Grove, Inc. All rights reserved.
//  Copyright © 2024 RRZE. All rights reserved.
//

import Foundation
import OSLog
import dogeADAuth

/// Mögliche Fehler bei der automatischen Anmeldung
public enum AutoSignInError: Error, LocalizedError {
    case noSRVRecords(String)
    case noActiveTickets
    case keychainAccessFailed(Error)
    case authenticationFailed(String)
    case networkError(String)
    
    public var errorDescription: String? {
        switch self {
        case .noSRVRecords(let domain):
            return "Keine SRV-Einträge gefunden für Domäne: \(domain)"
        case .noActiveTickets:
            return "Keine aktiven Kerberos-Tickets vorhanden"
        case .keychainAccessFailed(let error):
            return "Zugriff auf Keychain fehlgeschlagen: \(error.localizedDescription)"
        case .authenticationFailed(let message):
            return "Authentifizierung fehlgeschlagen: \(message)"
        case .networkError(let message):
            return "Netzwerkfehler: \(message)"
        }
    }
}

/// Benutzer-Sitzungsobjekt mit Informationen zur Authentifizierung
public struct Doge_SessionUserObject {
    /// Benutzerprincipal (z.B. user@DOMAIN.COM)
    var userPrincipal: String
    /// Active Directory Sitzung
    var session: dogeADSession
    /// Gibt an, ob Passwort-Aging aktiviert ist
    var aging: Bool
    /// Ablaufdatum des Passworts, falls vorhanden
    var expiration: Date?
    /// Verbleibende Tage bis zum Ablauf des Passworts
    var daysToGo: Int?
    /// Benutzerinformationen aus Active Directory
    var userInfo: ADUserRecord?
}

/// Actor für die automatische Anmeldung an Active Directory
/// 
/// Verwaltet automatische Anmeldungen für mehrere Konten
actor AutomaticSignIn {
    /// Gemeinsame Instanz (Singleton)
    static let shared = AutomaticSignIn()
    
    /// Preference Manager für Einstellungen
    var prefs = PreferenceManager()
    
    /// Accounts Manager für Benutzerkontenverwaltung
    let accountsManager = AccountsManager.shared
    
    /// Private Initialisierung für Singleton-Pattern
    private init() {}
    
    /// Meldet alle relevanten Konten automatisch an
    /// 
    /// Basierend auf Einstellungen werden entweder alle Konten oder nur das Standard-Konto angemeldet.
    func signInAllAccounts() async {
        Logger.automaticSignIn.info("Starte automatischen Anmeldeprozess")
        
        let klist = KlistUtil()
        // Alle verfügbaren Kerberos-Principals abrufen
        let principals = await klist.klist().map({ $0.principal })
        let defaultPrinc = await klist.defaultPrincipal
        
        Logger.automaticSignIn.debug("Gefundene Principals: \(principals.joined(separator: ", "))")
        Logger.automaticSignIn.debug("Standard-Principal: \(defaultPrinc ?? "Keiner")")
        
        // Konten abrufen und Anmeldestrategie bestimmen:
        // - Wenn Single-User-Modus aktiv ist, nur Standard-Konto anmelden
        // - Ansonsten alle Konten anmelden
        let accounts = await accountsManager.accounts
        let accountsCount = accounts.count
        
        for account in accounts {
            if !prefs.bool(for: .singleUserMode) || account.upn == defaultPrinc || accountsCount == 1 {
                Logger.automaticSignIn.info("Automatische Anmeldung für Konto: \(account.upn)")
                let worker = AutomaticSignInWorker(account: account)
                await worker.checkUser()
            }
        }
        
        // Standard-Principal wiederherstellen
        if let defPrinc = defaultPrinc {
            do {
                let output = try await cliTaskAsync("kswitch -p \(defPrinc)")
                Logger.automaticSignIn.debug("kswitch Ausgabe: \(output)")
            } catch {
                Logger.automaticSignIn.error("Fehler beim Umschalten auf Standard-Principal: \(error.localizedDescription)")
            }
        }
    }
}

/// Worker-Actor für die Anmeldung eines einzelnen Kontos
/// 
/// Implementiert die Delegate-Methoden für dogeADUserSessionDelegate
actor AutomaticSignInWorker: dogeADUserSessionDelegate {
    
    /// Preference Manager für Einstellungen
    var prefs = PreferenceManager()
    
    /// Das zu verwaltende Benutzerkonto
    var account: DogeAccount
    
    /// Active Directory Sitzung
    var session: dogeADSession
    
    /// DNS-Resolver für SRV-Einträge
    var resolver = SRVResolver()
    
    /// Die Domäne des Benutzerkontos
    let domain: String
    
    /// Initialisiert einen neuen Worker mit einem Benutzerkonto
    /// 
    /// - Parameter account: Das Benutzerkonto für die Anmeldung
    init(account: DogeAccount) {
        self.account = account
        domain = account.upn.userDomain() ?? ""
        self.session = dogeADSession(domain: domain, user: account.upn.user())
        self.session.setupSessionFromPrefs(prefs: prefs)
        
        Logger.automaticSignIn.debug("Worker initialisiert für Benutzer: \(account.upn), Domäne: \(self.domain)")
    }
    
    /// Überprüft den Benutzer und führt die Anmeldung durch
    /// 
    /// Der Prozess umfasst:
    /// 1. Auflösen der SRV-Einträge für LDAP-Server
    /// 2. Überprüfung bestehender Kerberos-Tickets
    /// 3. Abrufen von Benutzerinformationen oder Authentifizierung
    func checkUser() async {
        let klist = KlistUtil()
        let princs = await klist.klist().map({ $0.principal })
        
        // SRV-Einträge für LDAP auflösen
        do {
            let records = try await resolveSRVRecords()
            
            // Wenn SRV-Einträge gefunden wurden und das Konto ein gültiges Ticket hat
            if !records.SRVRecords.isEmpty {
                if princs.contains(where: { $0.lowercased() == self.account.upn }) {
                    Logger.automaticSignIn.info("Gültiges Ticket gefunden für: \(self.account.upn)")
                    await getUserInfo()
                } else {
                    Logger.automaticSignIn.info("Kein gültiges Ticket gefunden, starte Authentifizierung")
                    await auth()
                }
            } else {
                Logger.automaticSignIn.warning("Keine SRV-Einträge gefunden für Domäne: \(self.domain)")
                throw AutoSignInError.noSRVRecords(domain)
            }
        } catch {
            Logger.automaticSignIn.error("Fehler beim Auflösen der SRV-Einträge: \(error.localizedDescription)")
            // Bei Fehlern trotzdem Authentifizierung versuchen
            await auth()
        }
    }
    
    /// Löst SRV-Einträge für die LDAP-Dienste auf
    /// 
    /// - Returns: Die gefundenen SRV-Einträge
    /// - Throws: Fehler, wenn keine Einträge gefunden werden
    private func resolveSRVRecords() async throws -> SRVResult {
        return try await withCheckedThrowingContinuation { continuation in
            let query = "_ldap._tcp." + domain.lowercased()
            Logger.automaticSignIn.debug("Löse SRV-Einträge auf für: \(query)")
            
            resolver.resolve(query: query) { result in
                Logger.automaticSignIn.info("SRV-Antwort für: \(query)")
                switch result {
                case .success(let records):
                    continuation.resume(returning: records)
                case .failure(let error):
                    Logger.automaticSignIn.error("Keine DNS-Ergebnisse für Domäne \(self.domain), automatische Anmeldung nicht möglich. Fehler: \(error)")
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Authentifiziert den Benutzer mit Keychain-Zugangsdaten
    /// 
    /// Ruft das Passwort aus dem Keychain ab und startet den Authentifizierungsprozess
    func auth() async {
        let keyUtil = KeychainManager()
        
        do {
            // Passwort aus Keychain abrufen
            if let pass = try keyUtil.retrievePassword(forUsername: account.upn.lowercaseDomain(), andService: Defaults.keyChainService) {
                Logger.automaticSignIn.debug("Passwort für \(self.account.upn) aus Keychain abgerufen")
                account.hasKeychainEntry = true
                session.userPass = pass
                session.delegate = self
                
                // Authentifizierung starten
                await session.authenticate()
            } else {
                Logger.automaticSignIn.warning("Kein Passwort im Keychain gefunden für: \(self.account.upn)")
                account.hasKeychainEntry = false
                NotificationCenter.default.post(name: .nsmNotification, object: nil, userInfo: ["KrbAuthError": MounterError.authenticationError])
            }
        } catch {
            Logger.automaticSignIn.error("Fehler beim Zugriff auf Keychain: \(error.localizedDescription)")
            account.hasKeychainEntry = false
            NotificationCenter.default.post(name: .nsmNotification, object: nil, userInfo: ["KrbAuthError": MounterError.authenticationError])
        }
    }
    
    /// Ruft Benutzerinformationen vom Active Directory ab
    /// 
    /// Wechselt zum Benutzer-Principal und ruft Detailinformationen ab
    func getUserInfo() async {
        do {
            // Zum Benutzer-Principal wechseln
            let output = try await cliTaskAsync("kswitch -p \(session.userPrincipal)")
            Logger.automaticSignIn.debug("kswitch Ausgabe: \(output)")
            
            // Benutzerdaten abrufen
            session.delegate = self
            await session.userInfo()
        } catch {
            Logger.automaticSignIn.error("Fehler beim Abrufen der Benutzerinformationen: \(error.localizedDescription)")
        }
    }
    
    // MARK: - dogeADUserSessionDelegate Methoden
    
    /// Wird aufgerufen, wenn die Authentifizierung erfolgreich war
    func dogeADAuthenticationSucceded() async {
        Logger.automaticSignIn.info("Authentifizierung erfolgreich für: \(self.account.upn)")
        
        do {
            // Zum authentifizierten Benutzer wechseln
            let output = try await cliTaskAsync("kswitch -p \(session.userPrincipal)")
            Logger.automaticSignIn.debug("kswitch Ausgabe: \(output)")
            
            // Erfolg mitteilen
            NotificationCenter.default.post(name: .nsmNotification, object: nil, userInfo: ["krbAuthenticated": MounterError.krbAuthSuccessful])
            
            // Benutzerinformationen abrufen
            await session.userInfo()
        } catch {
            Logger.automaticSignIn.error("Fehler nach erfolgreicher Authentifizierung: \(error.localizedDescription)")
        }
    }
    
    /// Wird aufgerufen, wenn die Authentifizierung fehlgeschlagen ist
    /// 
    /// - Parameters:
    ///   - error: Fehlertyp
    ///   - description: Fehlerbeschreibung
    func dogeADAuthenticationFailed(error: dogeADSessionError, description: String) {
        Logger.automaticSignIn.info("Authentifizierung fehlgeschlagen für: \(self.account.upn), Fehler: \(description)")
        
        switch error {
        case .AuthenticationFailure, .PasswordExpired:
            // Bei Authentifizierungsfehlern oder abgelaufenen Passwörtern:
            // - Benachrichtigung senden
            // - Falsches Passwort aus Keychain entfernen
            NotificationCenter.default.post(name: .nsmNotification, object: nil, userInfo: ["KrbAuthError": MounterError.krbAuthenticationError])
            Logger.automaticSignIn.info("Entferne ungültiges Passwort aus Keychain")
            
            let keyUtil = KeychainManager()
            do {
                try keyUtil.removeCredential(forUsername: account.upn)
                Logger.automaticSignIn.info("Keychain-Eintrag erfolgreich entfernt")
            } catch {
                Logger.automaticSignIn.error("Fehler beim Entfernen des Keychain-Eintrags für: \(self.account.upn), Fehler: \(error.localizedDescription)")
            }
            
        case .OffDomain:
            // Wenn außerhalb der Kerberos-Domäne
            Logger.automaticSignIn.info("Außerhalb des Kerberos-Realm-Netzwerks")
            NotificationCenter.default.post(name: .nsmNotification, object: nil, userInfo: ["krbOffDomain": MounterError.offDomain])
            
        default:
            Logger.automaticSignIn.warning("Unbehandelter Authentifizierungsfehler: \(error)")
            break
        }
    }
    
    /// Wird aufgerufen, wenn Benutzerinformationen erfolgreich abgerufen wurden
    /// 
    /// - Parameter user: Abgerufene Benutzerinformationen
    func dogeADUserInformation(user: ADUserRecord) {
        Logger.automaticSignIn.debug("Benutzerinformationen erhalten für: \(user.userPrincipal)")
        
        // Benutzerinformationen im PreferenceManager speichern
        prefs.setADUserInfo(user: user)
    }
}
