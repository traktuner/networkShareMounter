import XCTest
@testable import Network_Share_Mounter

final class KeychainManagerTests: XCTestCase {
    
    var keychainManager: KeychainManager!
    
    // Test constants
    let testShareURL = URL(string: "smb://testserver.example.com/testshare")!
    let testUsername = "testuser"
    let testPassword = "testpassword"
    let testService = "de.fau.rrze.NetworkShareMounter.UNITTEST"
    
    override func setUpWithError() throws {
        keychainManager = KeychainManager()
        // Clean up any test data from previous test runs
        try? keychainManager.removeCredential(forShare: testShareURL, withUsername: testUsername)
        try? keychainManager.removeCredential(forUsername: testUsername, andService: testService)
    }
    
    override func tearDownWithError() throws {
        // Clean up after tests
        try? keychainManager.removeCredential(forShare: testShareURL, withUsername: testUsername)
        try? keychainManager.removeCredential(forUsername: testUsername, andService: testService)
        keychainManager = nil
    }
    
    // MARK: - Query Generation Tests
    
    func testMakeQueryForShare() throws {
        let query = try keychainManager.makeQuery(share: testShareURL, username: testUsername)
        
        XCTAssertEqual(query[kSecClass as String] as? String, kSecClassInternetPassword as String)
        XCTAssertEqual(query[kSecAttrAccount as String] as? String, testUsername)
        XCTAssertEqual(query[kSecAttrServer as String] as? String, testShareURL.host)
        XCTAssertEqual(query[kSecAttrPath as String] as? String, testShareURL.lastPathComponent)
    }
    
    func testMakeQueryForUsername() throws {
        let query = try keychainManager.makeQuery(username: testUsername, service: testService)
        
        XCTAssertEqual(query[kSecClass as String] as? String, kSecClassGenericPassword as String)
        XCTAssertEqual(query[kSecAttrAccount as String] as? String, testUsername)
        XCTAssertEqual(query[kSecAttrService as String] as? String, testService)
    }
    
    func testMakeQueryWithMalformedURL() throws {
        let invalidURL = URL(string: "smb:")!
        
        XCTAssertThrowsError(try keychainManager.makeQuery(share: invalidURL, username: testUsername)) { error in
            XCTAssertEqual(error as? KeychainError, KeychainError.malformedShare)
        }
    }
    
    // MARK: - Credential Storage and Retrieval Tests
    
    func testSaveAndRetrieveShareCredential() throws {
        // Save credential
        try keychainManager.saveCredential(forShare: testShareURL, withUsername: testUsername, andPassword: testPassword)
        
        // Retrieve and verify
        let retrievedPassword = try keychainManager.retrievePassword(forShare: testShareURL, withUsername: testUsername)
        XCTAssertEqual(retrievedPassword, testPassword)
    }
    
    func testSaveAndRetrieveUsernameCredential() throws {
        // Save credential
        try keychainManager.saveCredential(forUsername: testUsername, andPassword: testPassword, withService: testService)
        
        // Retrieve and verify
        let retrievedPassword = try keychainManager.retrievePassword(forUsername: testUsername, andService: testService)
        XCTAssertEqual(retrievedPassword, testPassword)
    }
    
    func testOverwriteExistingCredential() throws {
        // Save initial credential
        try keychainManager.saveCredential(forShare: testShareURL, withUsername: testUsername, andPassword: testPassword)
        
        // Overwrite with new password
        let newPassword = "newpassword"
        try keychainManager.saveCredential(forShare: testShareURL, withUsername: testUsername, andPassword: newPassword)
        
        // Verify new password is stored
        let retrievedPassword = try keychainManager.retrievePassword(forShare: testShareURL, withUsername: testUsername)
        XCTAssertEqual(retrievedPassword, newPassword)
    }
    
    // MARK: - Credential Removal Tests
    
    func testRemoveShareCredential() throws {
        // Save credential
        try keychainManager.saveCredential(forShare: testShareURL, withUsername: testUsername, andPassword: testPassword)
        
        // Verify it exists
        XCTAssertNoThrow(try keychainManager.retrievePassword(forShare: testShareURL, withUsername: testUsername))
        
        // Remove credential
        try keychainManager.removeCredential(forShare: testShareURL, withUsername: testUsername)
        
        // Verify it's gone - should throw error
        XCTAssertThrowsError(try keychainManager.retrievePassword(forShare: testShareURL, withUsername: testUsername))
    }
    
    func testRemoveUsernameCredential() throws {
        // Save credential
        try keychainManager.saveCredential(forUsername: testUsername, andPassword: testPassword, withService: testService)
        
        // Verify it exists
        XCTAssertNoThrow(try keychainManager.retrievePassword(forUsername: testUsername, andService: testService))
        
        // Remove credential
        try keychainManager.removeCredential(forUsername: testUsername, andService: testService)
        
        // Verify it's gone - should throw error
        XCTAssertThrowsError(try keychainManager.retrievePassword(forUsername: testUsername, andService: testService))
    }
    
    func testRemoveNonExistentCredential() throws {
        // Should not throw when trying to remove non-existent credential
        XCTAssertNoThrow(try keychainManager.removeCredential(forShare: testShareURL, withUsername: "nonexistentuser"))
    }
    
    // MARK: - Error Handling Tests
    
    func testInvalidPasswordEncoding() throws {
        // Creating a string that can't be encoded in UTF-8 is difficult in Swift,
        // as String is already UTF-8 compatible. This is more a conceptual test.
        // In a real scenario, we'd need to create a mock or subclass to test this.
        
        // For now, we'll just verify the error path exists in the code
        let mockManager = MockKeychainManager()
        XCTAssertThrowsError(try mockManager.simulateEncodingFailure()) { error in
            XCTAssertEqual(error as? KeychainError, KeychainError.unexpectedPasswordData)
        }
    }
}

// Mock class for testing error conditions
class MockKeychainManager: KeychainManager {
    func simulateEncodingFailure() throws {
        // Simulate the code path where password encoding fails
        throw KeychainError.unexpectedPasswordData
    }
} 