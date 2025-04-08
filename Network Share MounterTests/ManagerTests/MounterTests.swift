import XCTest
@testable import Network_Share_Mounter

/**
 Tests für die Mounter-Klasse
 
 Diese Tests verifizieren die Kernfunktionalität der Mounter-Klasse, die für das
 Mounten und Unmounten von Netzwerk-Shares verantwortlich ist.
 
 Hinweise:
 - Dies sind hauptsächlich Integrationstests, die mit der tatsächlichen Mounter-Klasse arbeiten
 - Alle Testmethoden sind als async markiert, da Mounter mit async/await arbeitet
 - Wir fokussieren uns auf testbare Funktionalitäten ohne die Originalklasse zu ändern
 */
final class MounterTests: XCTestCase {
    
    // MARK: - Properties
    
    /// Das zu testende System
    var sut: Mounter!
    
    // Testkonstanten
    let testShare1URL = "smb://testserver.example.com/testshare1"
    let testShare2URL = "smb://testserver.example.com/testshare2"
    let testUsername = "testuser"
    let testPassword = "testpassword"
    let testMountPoint = "/Users/testuser/Network"
    
    // MARK: - Setup & Teardown
    
    override func setUpWithError() throws {
        // Mounter initialisieren
        sut = Mounter()
        
        // FakeURLProtocol für Netzwerk-Mocking (falls benötigt)
        URLProtocol.registerClass(FakeURLProtocol.self)
    }
    
    override func tearDownWithError() throws {
        // Aufräumen
        sut = nil
        URLProtocol.unregisterClass(FakeURLProtocol.self)
    }
    
    // MARK: - Hilfsmethoden
    
    /// Erstellt einen Test-Share zum Testen
    private func createTestShare(
        networkShare: String = "smb://testserver.example.com/testshare",
        authType: AuthType = .krb,
        username: String? = "testuser",
        password: String? = nil,
        mountStatus: MountStatus = .unmounted,
        mountPoint: String? = nil,
        managed: Bool = false
    ) -> Share {
        return Share.createShare(
            networkShare: networkShare,
            authType: authType,
            mountStatus: mountStatus,
            username: username,
            password: password,
            mountPoint: mountPoint,
            managed: managed
        )
    }
    
    /// Fügt dem ShareManager einen Testshare hinzu
    private func addTestShareToManager() async -> Share {
        let testShare = createTestShare()
        await sut.shareManager.addShare(testShare)
        return testShare
    }
    
    // MARK: - Tests: Grundfunktionen
    
    /// Test: Initialisierung des Mounter
    func testInit() async throws {
        // Given/When: Der Mounter wurde im Setup erstellt
        
        // Then: Der Mounter sollte existieren und ShareManager enthalten
        XCTAssertNotNil(sut, "Mounter sollte initialisiert werden")
        XCTAssertNotNil(sut.shareManager, "Mounter sollte einen ShareManager haben")
        XCTAssertEqual(sut.defaultMountPath, Defaults.defaultMountPath, "Standardpfad sollte gesetzt sein")
    }
    
    /// Test: AsyncInit-Methode
    func testAsyncInit() async throws {
        // Given
        let prefs = PreferenceManager()
        let useLocalized = false
        let useNewLocation = true
        
        // Setzen der Präferenzen im UserDefaults
        let defaults = UserDefaults.standard
        defaults.set(useLocalized, forKey: PreferenceKeys.useLocalizedMountDirectories.rawValue)
        defaults.set(useNewLocation, forKey: PreferenceKeys.useNewDefaultLocation.rawValue)
        
        // When
        await sut.asyncInit()
        
        // Then
        // Standardpfad sollte bei useNewDefaultLocation = true auf /Volumes gesetzt sein
        XCTAssertEqual(sut.defaultMountPath, Defaults.defaultMountPath, "defaultMountPath sollte auf Defaults.defaultMountPath gesetzt sein")
        
        // Aufräumen
        defaults.removeObject(forKey: PreferenceKeys.useLocalizedMountDirectories.rawValue)
        defaults.removeObject(forKey: PreferenceKeys.useNewDefaultLocation.rawValue)
    }
    
    /// Test: AsyncInit mit benutzerdefinierten lokalen Ordnern
    func testAsyncInitWithLocalizedFolders() async throws {
        // Given
        let useLocalized = true
        let useNewLocation = false
        
        // Setzen der Präferenzen im UserDefaults
        let defaults = UserDefaults.standard
        defaults.set(useLocalized, forKey: PreferenceKeys.useLocalizedMountDirectories.rawValue)
        defaults.set(useNewLocation, forKey: PreferenceKeys.useNewDefaultLocation.rawValue)
        
        // Speichere den ursprünglichen Sprachcode, um ihn später wiederherzustellen
        let originalLanguageCode = Locale.current.languageCode
        
        // When
        await sut.asyncInit()
        
        // Then
        if useNewLocation {
            XCTAssertEqual(sut.defaultMountPath, Defaults.defaultMountPath, "defaultMountPath sollte auf Defaults.defaultMountPath gesetzt sein")
        } else {
            let expectedLocalizedFolder = Defaults.translation[Locale.current.languageCode ?? "en"] ?? Defaults.translation["en"]!
            let expectedPath = NSString(string: "~/\(expectedLocalizedFolder)").expandingTildeInPath
            XCTAssertEqual(sut.defaultMountPath, expectedPath, "defaultMountPath sollte auf den lokalisierten Pfad gesetzt sein")
        }
        
        // Aufräumen
        defaults.removeObject(forKey: PreferenceKeys.useLocalizedMountDirectories.rawValue)
        defaults.removeObject(forKey: PreferenceKeys.useNewDefaultLocation.rawValue)
    }
    
    /// Test: Hinzufügen eines Shares
    func testAddShare() async throws {
        // Given
        let testShare = createTestShare()
        
        // When
        await sut.addShare(testShare)
        
        // Then
        let shares = await sut.shareManager.allShares
        XCTAssertEqual(shares.count, 1, "Ein Share sollte hinzugefügt worden sein")
        XCTAssertEqual(shares[0].networkShare, testShare.networkShare, "Der hinzugefügte Share sollte im ShareManager sein")
    }
    
    /// Test: Entfernen eines Shares
    func testRemoveShare() async throws {
        // Given
        let testShare = await addTestShareToManager()
        let shares = await sut.shareManager.allShares
        XCTAssertEqual(shares.count, 1, "Setup: Ein Share sollte hinzugefügt worden sein")
        
        // When
        await sut.removeShare(for: testShare)
        
        // Then
        let updatedShares = await sut.shareManager.allShares
        XCTAssertEqual(updatedShares.count, 0, "Der Share sollte entfernt worden sein")
    }
    
    /// Test: Aktualisieren des Mount-Status eines Shares
    func testUpdateShareMountStatus() async throws {
        // Given
        let testShare = await addTestShareToManager()
        
        // When
        await sut.updateShare(mountStatus: .mounted, for: testShare)
        
        // Then
        let shares = await sut.shareManager.allShares
        if let index = shares.firstIndex(where: { $0.id == testShare.id }) {
            XCTAssertEqual(shares[index].mountStatus, .mounted, "Der Mount-Status sollte auf 'mounted' gesetzt sein")
        } else {
            XCTFail("Der Share sollte im ShareManager sein")
        }
    }
    
    /// Test: Aktualisieren des Mount-Punkts eines Shares
    func testUpdateShareMountPoint() async throws {
        // Given
        let testShare = await addTestShareToManager()
        let newMountPoint = "/Volumes/TestShare"
        
        // When
        await sut.updateShare(actualMountPoint: newMountPoint, for: testShare)
        
        // Then
        let shares = await sut.shareManager.allShares
        if let index = shares.firstIndex(where: { $0.id == testShare.id }) {
            XCTAssertEqual(shares[index].actualMountPoint, newMountPoint, "Der Mount-Punkt sollte aktualisiert werden")
        } else {
            XCTFail("Der Share sollte im ShareManager sein")
        }
    }
    
    /// Test: Erstellen eines Verzeichnisses für Shares
    func testCreateMountFolder() throws {
        // Given
        let tempDirectoryURL = FileManager.default.temporaryDirectory
        let testDirURL = tempDirectoryURL.appendingPathComponent(UUID().uuidString)
        let testDirPath = testDirURL.path
        
        // Sicherstellen, dass das Verzeichnis nicht existiert
        try? FileManager.default.removeItem(at: testDirURL)
        
        // When
        sut.createMountFolder(atPath: testDirPath)
        
        // Then
        XCTAssertTrue(FileManager.default.fileExists(atPath: testDirPath), "Verzeichnis sollte erstellt worden sein")
        
        // Aufräumen
        try? FileManager.default.removeItem(at: testDirURL)
    }
    
    /// Test: Abrufen eines Shares anhand der Netzwerk-URL
    func testGetShareForNetworkShare() async throws {
        // Given
        let testShare = await addTestShareToManager()
        
        // When
        let foundShare = await sut.getShare(forNetworkShare: testShare.networkShare)
        
        // Then
        XCTAssertNotNil(foundShare, "Ein Share sollte gefunden werden")
        XCTAssertEqual(foundShare?.networkShare, testShare.networkShare, "Der gefundene Share sollte korrekt sein")
    }
    
    /// Test: Setzen des Mount-Status für alle Shares
    func testSetAllMountStatus() async throws {
        // Given
        let testShare1 = createTestShare(networkShare: testShare1URL)
        let testShare2 = createTestShare(networkShare: testShare2URL)
        await sut.shareManager.addShare(testShare1)
        await sut.shareManager.addShare(testShare2)
        
        // When
        await sut.setAllMountStatus(to: .mounted)
        
        // Then
        let shares = await sut.shareManager.allShares
        for share in shares {
            XCTAssertEqual(share.mountStatus, .mounted, "Alle Shares sollten den Status 'mounted' haben")
        }
    }
    
    /// Test: Aktualisieren eines Shares
    func testUpdateShare() async throws {
        // Given
        let originalShare = createTestShare(networkShare: testShare1URL)
        await sut.shareManager.addShare(originalShare)
        
        let updatedShare = createTestShare(
            networkShare: testShare1URL,
            authType: .pwd,
            username: "newuser",
            password: "newpassword"
        )
        
        // When
        await sut.updateShare(for: updatedShare)
        
        // Then
        let shares = await sut.shareManager.allShares
        XCTAssertEqual(shares[0].authType, .pwd, "Die Authentifizierungsart sollte aktualisiert sein")
        XCTAssertEqual(shares[0].username, "newuser", "Der Benutzername sollte aktualisiert sein")
    }
    
    /// Test: Path-Escaping-Funktion (indirekt)
    func testEscapePath() async throws {
        // Da die Methode private ist, testen wir sie indirekt durch eine andere Methode
        // Wir erstellen temporär ein Verzeichnis, das Sonderzeichen enthält
        
        // Given
        let tempDirectoryURL = FileManager.default.temporaryDirectory
        let specialDirName = "test'dir with spaces"
        let testDirURL = tempDirectoryURL.appendingPathComponent(specialDirName)
        let testDirPath = testDirURL.path
        
        // Sicherstellen, dass das Verzeichnis existiert
        try? FileManager.default.createDirectory(at: testDirURL, withIntermediateDirectories: true, attributes: nil)
        
        // Zum Testen: Wir können nicht direkt testen, aber wir können überprüfen, ob ein Verzeichnis
        // mit Sonderzeichen ohne Fehler entfernt werden kann
        XCTAssertNoThrow(sut.removeDirectory(atPath: testDirPath), "Das Verzeichnis mit Sonderzeichen sollte ohne Fehler entfernt werden können")
        
        // Aufräumen - für den Fall, dass etwas schiefgeht
        try? FileManager.default.removeItem(at: testDirURL)
    }
    
    /// Test: Entfernen eines Verzeichnisses in /Volumes
    func testRemoveDirectoryInVolumes() async throws {
        // Given
        let testDirPath = "/Volumes/TestDir"  // Diese sollte nicht entfernt werden
        
        // When/Then - die rmdir-Operation sollte keine Auswirkungen haben
        // Da wir nicht tatsächlich ein Verzeichnis in /Volumes erstellen können, testen wir nur,
        // dass die Funktion keine Exception wirft
        XCTAssertNoThrow(sut.removeDirectory(atPath: testDirPath))
    }
}

// MARK: - Hilfsklassen

/// Fake URLProtocol für Netzwerktests
class FakeURLProtocol: URLProtocol {
    static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?
    
    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    override func startLoading() {
        guard let handler = FakeURLProtocol.requestHandler else {
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    
    override func stopLoading() {}
} 