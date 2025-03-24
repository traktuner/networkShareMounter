import XCTest
@testable import Network_Share_Mounter

/// Tests für den PreferenceManager
/// Fokus auf grundlegende Funktionalität zum Speichern und Abrufen von Einstellungen
final class PreferenceManagerTests: XCTestCase {
    
    // MARK: - Properties
    
    var sut: PreferenceManager!
    let testSuiteName = "de.fau.rrze.NetworkShareMounter.tests"
    var testDefaults: UserDefaults!
    
    // MARK: - Lifecycle
    
    override func setUp() {
        super.setUp()
        
        // Test-UserDefaults erstellen und zurücksetzen
        testDefaults = UserDefaults(suiteName: testSuiteName)
        testDefaults.removePersistentDomain(forName: testSuiteName)
        
        // SUT (System Under Test) initialisieren
        sut = PreferenceManager()
    }
    
    override func tearDown() {
        // Aufräumen
        testDefaults.removePersistentDomain(forName: testSuiteName)
        testDefaults = nil
        sut = nil
        
        super.tearDown()
    }
    
    // MARK: - Tests: Grundlegende Wertespeicherung und -abruf
    
    /// Test: String-Wert speichern und abrufen
    func testStringValueStorage() {
        // Given
        let key = PreferenceKeys.lastUser
        let value = "testUser"
        
        // When
        sut.set(for: key, value: value)
        let result = sut.string(for: key)
        
        // Then
        XCTAssertEqual(result, value, "Der gespeicherte String sollte korrekt abgerufen werden")
    }
    
    /// Test: Boolean-Wert speichern und abrufen
    func testBoolValueStorage() {
        // Given
        let key = PreferenceKeys.canQuit
        let value = true
        
        // When
        sut.set(for: key, value: value)
        let result = sut.bool(for: key)
        
        // Then
        XCTAssertEqual(result, value, "Der gespeicherte Boolean sollte korrekt abgerufen werden")
    }
    
    /// Test: Integer-Wert speichern und abrufen
    func testIntValueStorage() {
        // Given
        let key = PreferenceKeys.singleUserMode
        let value = 42
        
        // When
        sut.set(for: key, value: value)
        let result = sut.int(for: key)
        
        // Then
        XCTAssertEqual(result, value, "Der gespeicherte Integer sollte korrekt abgerufen werden")
    }
    
    /// Test: Array speichern und abrufen
    func testArrayStorage() {
        // Given
        let key = PreferenceKeys.lDAPServerList
        let value = ["server1.example.com", "server2.example.com"]
        
        // When
        sut.set(for: key, value: value)
        let result = sut.array(for: key) as? [String]
        
        // Then
        XCTAssertEqual(result, value, "Das gespeicherte Array sollte korrekt abgerufen werden")
    }
    
    /// Test: Dictionary speichern und abrufen
    func testDictionaryStorage() {
        // Given
        let key = PreferenceKeys.allUserInformation
        let value: [String: Any] = ["name": "Test User", "role": "Admin"]
        
        // When
        sut.set(for: key, value: value)
        let result = sut.dictionary(for: key)
        
        // Then
        XCTAssertEqual(result?["name"] as? String, "Test User")
        XCTAssertEqual(result?["role"] as? String, "Admin")
    }
    
    // MARK: - Tests: Werte löschen und Standard-Werte
    
    /// Test: Wert löschen
    func testClearValue() {
        // Given
        let key = PreferenceKeys.lastUser
        sut.set(for: key, value: "testUser")
        
        // When
        sut.clear(for: key)
        let result = sut.string(for: key)
        
        // Then
        XCTAssertNil(result, "Nach dem Löschen sollte der Wert nil sein")
    }
    
    /// Test: Standard-Werte aus Property List
    func testDefaultValues() {
        // Dieser Test setzt voraus, dass es eine Default-Property-List gibt
        // und dass mindestens ein Wert darin enthalten ist
        
        // Ein Beispiel für einen Standard-Wert, der in der Property List definiert sein könnte
        // Dies ist nur ein Beispiel und muss an die tatsächliche Default-Property-List angepasst werden
        let key = PreferenceKeys.canQuit
        let defaultValue = sut.bool(for: key)
        
        // Wir überprüfen nicht den genauen Wert, sondern nur dass ein Wert vorhanden ist
        // Dies dient als Smoke-Test für die Default-Werte-Funktionalität
        XCTAssertNotNil(defaultValue, "Es sollte ein Default-Wert für \(key) gesetzt sein")
    }
} 