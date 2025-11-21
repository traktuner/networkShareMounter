import XCTest
@testable import Network_Share_Mounter

final class KeychainManagerMockTests: XCTestCase {
    
    // Test with mocked KeychainManager to avoid real keychain access
    class KeychainManagerMock: KeychainManager {
        var savedCredentials: [String: [String: String]] = [:]
        var makeQueryCalled = false
        var shouldThrowOnMakeQuery = false
        var shouldThrowOnSave = false
        var shouldThrowOnRetrieve = false
        
        override func makeQuery(share shareURL: URL, username: String, service: String? = nil, accessGroup: String? = nil, comment: String? = nil, label: String? = nil) throws -> [String: Any] {
            makeQueryCalled = true
            
            if shouldThrowOnMakeQuery {
                throw KeychainError.malformedShare
            }
            
            return ["mockKey": "mockValue"]
        }
        
        override func makeQuery(username: String, service: String = Defaults.keyChainService, accessGroup: String? = nil, label: String? = nil, comment: String? = nil) throws -> [String: Any] {
            makeQueryCalled = true
            
            if shouldThrowOnMakeQuery {
                throw KeychainError.malformedShare
            }
            
            return ["mockKey": "mockValue"]
        }
        
        override func saveCredential(forShare share: URL, withUsername username: String, andPassword password: String, withLabel label: String? = Defaults.keyChainService, accessGroup: String? = Defaults.keyChainAccessGroup, comment: String? = nil) throws {
            if shouldThrowOnSave {
                throw KeychainError.undefinedError
            }
            
            let key = "\(share.absoluteString)|\(username)"
            savedCredentials[key] = ["username": username, "password": password]
        }
        
        override func saveCredential(forUsername username: String, andPassword password: String, withService service: String = Defaults.keyChainService, andLabel label: String? = nil, accessGroup: String? = nil, comment: String? = nil) throws {
            if shouldThrowOnSave {
                throw KeychainError.undefinedError
            }
            
            let key = "\(service)|\(username)"
            savedCredentials[key] = ["username": username, "password": password]
        }
        
        override func retrievePassword(forShare share: URL, withUsername username: String) throws -> String? {
            if shouldThrowOnRetrieve {
                throw KeychainError.errorRetrievingPassword
            }
            
            let key = "\(share.absoluteString)|\(username)"
            return savedCredentials[key]?["password"]
        }
        
        override func retrievePassword(forUsername username: String, andService service: String = Defaults.keyChainService, accessGroup: String? = nil) throws -> String? {
            if shouldThrowOnRetrieve {
                throw KeychainError.errorRetrievingPassword
            }
            
            let key = "\(service)|\(username)"
            return savedCredentials[key]?["password"]
        }
        
        override func removeCredential(forShare share: URL, withUsername username: String) throws {
            let key = "\(share.absoluteString)|\(username)"
            savedCredentials.removeValue(forKey: key)
        }
        
        override func removeCredential(forUsername username: String, andService service: String = Defaults.keyChainService, accessGroup: String? = Defaults.keyChainAccessGroup) throws {
            let key = "\(service)|\(username)"
            savedCredentials.removeValue(forKey: key)
        }
    }
    
    var mockKeychainManager: KeychainManagerMock!
    
    override func setUpWithError() throws {
        mockKeychainManager = KeychainManagerMock()
    }
    
    override func tearDownWithError() throws {
        mockKeychainManager = nil
    }
    
    // MARK: - Tests with Mocks
    
    func testSaveAndRetrieveWithMock() throws {
        let testURL = URL(string: "smb://testserver.example.com/testshare")!
        let testUsername = "testuser"
        let testPassword = "testpassword"
        
        // Save credential
        try mockKeychainManager.saveCredential(forShare: testURL, withUsername: testUsername, andPassword: testPassword)
        
        // Retrieve and verify
        let retrievedPassword = try mockKeychainManager.retrievePassword(forShare: testURL, withUsername: testUsername)
        XCTAssertEqual(retrievedPassword, testPassword)
    }
    
    func testErrorHandlingWithMock() throws {
        let testURL = URL(string: "smb://testserver.example.com/testshare")!
        let testUsername = "testuser"
        
        // Set mock to throw on retrieve
        mockKeychainManager.shouldThrowOnRetrieve = true
        
        XCTAssertThrowsError(try mockKeychainManager.retrievePassword(forShare: testURL, withUsername: testUsername)) { error in
            XCTAssertEqual(error as? KeychainError, KeychainError.errorRetrievingPassword)
        }
    }
    
    func testRemoveCredentialWithMock() throws {
        let testURL = URL(string: "smb://testserver.example.com/testshare")!
        let testUsername = "testuser"
        let testPassword = "testpassword"
        
        // Save credential
        try mockKeychainManager.saveCredential(forShare: testURL, withUsername: testUsername, andPassword: testPassword)
        
        // Verify it exists
        XCTAssertNotNil(try mockKeychainManager.retrievePassword(forShare: testURL, withUsername: testUsername))
        
        // Remove credential
        try mockKeychainManager.removeCredential(forShare: testURL, withUsername: testUsername)
        
        // Verify it's gone
        XCTAssertNil(try mockKeychainManager.retrievePassword(forShare: testURL, withUsername: testUsername))
    }
    
    func testMultipleCredentialsWithMock() throws {
        let testURL1 = URL(string: "smb://server1.example.com/share1")!
        let testURL2 = URL(string: "smb://server2.example.com/share2")!
        let testUsername = "testuser"
        let testPassword1 = "password1"
        let testPassword2 = "password2"
        
        // Save credentials
        try mockKeychainManager.saveCredential(forShare: testURL1, withUsername: testUsername, andPassword: testPassword1)
        try mockKeychainManager.saveCredential(forShare: testURL2, withUsername: testUsername, andPassword: testPassword2)
        
        // Verify both exist with correct values
        XCTAssertEqual(try mockKeychainManager.retrievePassword(forShare: testURL1, withUsername: testUsername), testPassword1)
        XCTAssertEqual(try mockKeychainManager.retrievePassword(forShare: testURL2, withUsername: testUsername), testPassword2)
    }
} 

