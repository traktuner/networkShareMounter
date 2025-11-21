import XCTest
@testable import Network_Share_Mounter

/**
 Tests for the ShareManager actor
 
 These tests verify the core functionality of the ShareManager, which is responsible
 for managing network shares including adding, updating, and removing shares,
 as well as processing configuration settings.
 
 Important implementation notes:
 
 1. Since ShareManager is an actor, all interactions with it must use await.
 2. All test methods are marked as async throws to properly handle async actor methods.
 3. Each test follows the Given-When-Then pattern for clarity.
 4. We're using the actual ShareManager implementation rather than mocking it, as this
    provides more realistic testing of the actor's behavior.
 
 The test suite covers:
 - Basic share management (adding, removing, updating shares)
 - Configuration processing (MDM, legacy, and user share configurations)
 - Other functionality (checking if shares exist, retrieving all shares)
 */
final class ShareManagerTests: XCTestCase {
    
    // MARK: - Properties
    
    /// The system under test
    var sut: ShareManager!
    
    // Test constants
    let testShare1 = "smb://testserver.example.com/testshare1"
    let testShare2 = "smb://testserver.example.com/testshare2"
    let testUsername = "testuser"
    let testPassword = "testpassword"
    
    // MARK: - Setup & Teardown
    
    override func setUpWithError() throws {
        // Create a fresh instance of ShareManager for each test
        sut = ShareManager()
    }
    
    override func tearDownWithError() throws {
        // Clean up
        sut = nil
    }
    
    // MARK: - Helper Methods
    
    /// Creates a test share with the given parameters
    /// - Parameters:
    ///   - networkShare: The network share URL
    ///   - authType: The authentication type
    ///   - username: Optional username
    ///   - password: Optional password
    ///   - managed: Whether the share is managed
    ///   - shareDisplayName: Optional display name for the share
    /// - Returns: A Share object for testing
    private func createTestShare(
        networkShare: String = "smb://testserver.example.com/testshare",
        authType: AuthType = .krb,
        username: String? = "testuser",
        password: String? = nil,
        managed: Bool = false,
        shareDisplayName: String? = nil
    ) -> Share {
        return Share.createShare(
            networkShare: networkShare,
            authType: authType,
            mountStatus: .unmounted,
            username: username,
            password: password,
            managed: managed,
            shareDisplayName: shareDisplayName
        )
    }
    
    // MARK: - Tests: Basic Share Management
    
    /// Test: Adding a share
    func testAddShare() async throws {
        // Given
        let testShare = createTestShare()
        
        // When
        await sut.addShare(testShare)
        
        // Then
        let shares = await sut.allShares
        XCTAssertEqual(shares.count, 1, "ShareManager should contain one share")
        XCTAssertEqual(shares[0].networkShare, testShare.networkShare, "The added share should match the test share")
    }
    
    /// Test: Adding a duplicate share
    func testAddDuplicateShare() async throws {
        // Given
        let testShare = createTestShare()
        
        // When
        await sut.addShare(testShare)
        await sut.addShare(testShare) // Add the same share again
        
        // Then
        let shares = await sut.allShares
        XCTAssertEqual(shares.count, 1, "ShareManager should still contain only one share")
    }
    
    /// Test: Removing a share
    func testRemoveShare() async throws {
        // Given
        let testShare = createTestShare()
        await sut.addShare(testShare)
        let shares = await sut.allShares
        XCTAssertEqual(shares.count, 1, "Setup: ShareManager should contain one share")
        
        // When
        await sut.removeShare(at: 0)
        
        // Then
        let updatedShares = await sut.allShares
        XCTAssertEqual(updatedShares.count, 0, "ShareManager should be empty after removal")
    }
    
    /// Test: Updating a share's mount status
    func testUpdateMountStatus() async throws {
        // Given
        let testShare = createTestShare()
        await sut.addShare(testShare)
        
        // When
        try await sut.updateMountStatus(at: 0, to: .mounted)
        
        // Then
        let shares = await sut.allShares
        XCTAssertEqual(shares[0].mountStatus, .mounted, "Share's mount status should be updated")
    }
    
    /// Test: Updating a share's mount point
    func testUpdateMountPoint() async throws {
        // Given
        let testShare = createTestShare()
        await sut.addShare(testShare)
        let newMountPoint = "/Volumes/TestMount"
        
        // When
        try await sut.updateMountPoint(at: 0, to: newMountPoint)
        
        // Then
        let shares = await sut.allShares
        XCTAssertEqual(shares[0].mountPoint, newMountPoint, "Share's mount point should be updated")
    }
    
    /// Test: Updating a share's actual mount point
    func testUpdateActualMountPoint() async throws {
        // Given
        let testShare = createTestShare()
        await sut.addShare(testShare)
        let newActualMountPoint = "/Volumes/TestMount"
        
        // When
        try await sut.updateActualMountPoint(at: 0, to: newActualMountPoint)
        
        // Then
        let shares = await sut.allShares
        XCTAssertEqual(shares[0].actualMountPoint, newActualMountPoint, "Share's actual mount point should be updated")
    }
    
    /// Test: Updating a share with new values
    func testUpdateShare() async throws {
        // Given
        let originalShare = createTestShare(networkShare: testShare1)
        await sut.addShare(originalShare)
        
        let updatedShare = createTestShare(
            networkShare: testShare1,
            authType: .pwd,
            username: "newuser",
            password: "newpassword",
            managed: true,
            shareDisplayName: "Updated Share"
        )
        
        // When
        try await sut.updateShare(at: 0, withUpdatedShare: updatedShare)
        
        // Then
        let shares = await sut.allShares
        XCTAssertEqual(shares[0].authType, .pwd, "Share's auth type should be updated")
        XCTAssertEqual(shares[0].username, "newuser", "Share's username should be updated")
        XCTAssertEqual(shares[0].managed, true, "Share's managed status should be updated")
        XCTAssertEqual(shares[0].shareDisplayName, "Updated Share", "Share's display name should be updated")
    }
    
    /// Test: Trying to update a share at an invalid index
    func testUpdateShareInvalidIndex() async throws {
        // Given
        let originalShare = createTestShare()
        await sut.addShare(originalShare)
        
        let updatedShare = createTestShare(authType: .pwd)
        
        // When/Then
        do {
            try await sut.updateShare(at: 999, withUpdatedShare: updatedShare)
            XCTFail("Should have thrown an error for invalid index")
        } catch let error as ShareError {
            if case .invalidIndex(let index) = error {
                XCTAssertEqual(index, 999, "Error should contain the invalid index")
            } else {
                XCTFail("Unexpected error type")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Tests: Configuration Processing
    
    /// Test: Processing MDM share configuration
    func testGetMDMShareConfig() async throws {
        // Given
        let shareConfig: [String: String] = [
            Defaults.networkShare: testShare1,
            Defaults.authType: AuthType.krb.rawValue,
            Defaults.username: testUsername,
            Defaults.mountPoint: "/Volumes/Test",
            Defaults.shareDisplayNameKey: "MDM Test Share"
        ]
        
        // When
        let resultShare = await sut.getMDMShareConfig(forShare: shareConfig)
        
        // Then
        XCTAssertNotNil(resultShare, "Should return a valid share")
        XCTAssertEqual(resultShare?.networkShare, testShare1, "Network share URL should match")
        XCTAssertEqual(resultShare?.authType, .krb, "Auth type should match")
        XCTAssertEqual(resultShare?.username, testUsername, "Username should match")
        XCTAssertEqual(resultShare?.mountPoint, "/Volumes/Test", "Mount point should match")
        XCTAssertEqual(resultShare?.managed, true, "Share should be marked as managed")
        XCTAssertEqual(resultShare?.shareDisplayName, "MDM Test Share", "Display name should match")
    }
    
    /// Test: Processing legacy share configuration
    func testGetLegacyShareConfig() async throws {
        // Given
        let legacySharePath = testShare1
        
        // When
        let resultShare = await sut.getLegacyShareConfig(forShare: legacySharePath)
        
        // Then
        XCTAssertNotNil(resultShare, "Should return a valid share")
        XCTAssertEqual(resultShare?.networkShare, testShare1, "Network share URL should match")
        XCTAssertEqual(resultShare?.authType, .krb, "Auth type should be Kerberos by default")
        XCTAssertEqual(resultShare?.managed, true, "Share should be marked as managed")
        XCTAssertNil(resultShare?.shareDisplayName, "Legacy shares should have nil display name")
    }
    
    /// Test: Processing user share configuration
    func testGetUserShareConfigs() async throws {
        // Given
        let shareConfig: [String: String] = [
            Defaults.networkShare: testShare1,
            Defaults.authType: AuthType.pwd.rawValue,
            Defaults.username: testUsername,
            Defaults.shareDisplayNameKey: "User Test Share"
        ]
        
        // When
        let resultShare = await sut.getUserShareConfigs(forShare: shareConfig)
        
        // Then
        XCTAssertNotNil(resultShare, "Should return a valid share")
        XCTAssertEqual(resultShare?.networkShare, testShare1, "Network share URL should match")
        XCTAssertEqual(resultShare?.authType, .pwd, "Auth type should match")
        XCTAssertEqual(resultShare?.username, testUsername, "Username should match")
        XCTAssertEqual(resultShare?.managed, false, "Share should be marked as unmanaged")
        XCTAssertEqual(resultShare?.shareDisplayName, "User Test Share", "Display name should match")
    }
    
    /// Test: Processing user share configuration with invalid URL
    func testGetUserShareConfigsWithInvalidURL() async throws {
        // Given
        let shareConfig: [String: String] = [
            Defaults.networkShare: "invalid://url",
            Defaults.authType: AuthType.pwd.rawValue,
            Defaults.username: testUsername
        ]
        
        // When
        let resultShare = await sut.getUserShareConfigs(forShare: shareConfig)
        
        // Then
        XCTAssertNotNil(resultShare, "Should still return a share despite invalid URL")
        XCTAssertEqual(resultShare?.networkShare, "invalid://url", "Should keep the invalid URL")
    }
    
    // MARK: - Tests: Other Functionality
    
    /// Test: HasShares returns correct value
    func testHasShares() async throws {
        // Given
        let initialHasShares = await sut.hasShares()
        XCTAssertFalse(initialHasShares, "Should initially have no shares")
        
        // When
        let testShare = createTestShare()
        await sut.addShare(testShare)
        
        // Then
        let hasSharesAfterAdd = await sut.hasShares()
        XCTAssertTrue(hasSharesAfterAdd, "Should return true after adding a share")
        
        // When
        await sut.removeShare(at: 0)
        
        // Then
        let hasSharesAfterRemove = await sut.hasShares()
        XCTAssertFalse(hasSharesAfterRemove, "Should return false after removing all shares")
    }
    
    /// Test: GetAllShares returns correct shares
    func testGetAllShares() async throws {
        // Given
        let testShare1 = createTestShare(networkShare: self.testShare1)
        let testShare2 = createTestShare(networkShare: self.testShare2)
        
        // When
        await sut.addShare(testShare1)
        await sut.addShare(testShare2)
        let shares = await sut.getAllShares()
        
        // Then
        XCTAssertEqual(shares.count, 2, "Should return 2 shares")
        XCTAssertEqual(shares[0].networkShare, self.testShare1, "First share should match")
        XCTAssertEqual(shares[1].networkShare, self.testShare2, "Second share should match")
    }
    
    /// Test: RemoveAllShares clears all shares
    func testRemoveAllShares() async throws {
        // Given
        await sut.addShare(createTestShare(networkShare: testShare1))
        await sut.addShare(createTestShare(networkShare: testShare2))
        let initialCount = await sut.allShares.count
        XCTAssertEqual(initialCount, 2, "Setup: Should have 2 shares")

        // When
        await sut.removeAllShares()

        // Then
        let finalCount = await sut.allShares.count
        XCTAssertEqual(finalCount, 0, "Should have no shares after removal")
    }

    // MARK: - Tests: Mount Point Management

    /// Test: isDuplicateMountPoint detects duplicate names (case-insensitive)
    func testIsDuplicateMountPointDetectsDuplicates() async throws {
        // Given
        let share1 = Share.createShare(
            networkShare: "smb://server1/share1",
            authType: .krb,
            mountStatus: .unmounted,
            mountPoint: "MyShare",
            managed: false
        )
        await sut.addShare(share1)

        // When/Then - exact match
        let isDuplicate1 = await sut.isDuplicateMountPoint("MyShare")
        XCTAssertTrue(isDuplicate1, "Should detect exact duplicate mount point")

        // When/Then - case-insensitive match
        let isDuplicate2 = await sut.isDuplicateMountPoint("myshare")
        XCTAssertTrue(isDuplicate2, "Should detect duplicate (case-insensitive)")

        let isDuplicate3 = await sut.isDuplicateMountPoint("MYSHARE")
        XCTAssertTrue(isDuplicate3, "Should detect duplicate (uppercase)")

        // When/Then - no duplicate
        let isDuplicate4 = await sut.isDuplicateMountPoint("DifferentShare")
        XCTAssertFalse(isDuplicate4, "Should not detect non-duplicate")
    }

    /// Test: isDuplicateMountPoint excludes specified share URL
    func testIsDuplicateMountPointExcludesShare() async throws {
        // Given
        let share1 = Share.createShare(
            networkShare: "smb://server1/share1",
            authType: .krb,
            mountStatus: .unmounted,
            mountPoint: "MyShare",
            managed: false
        )
        await sut.addShare(share1)

        // When - check same name but exclude the share itself
        let isDuplicate = await sut.isDuplicateMountPoint("MyShare", excludingShareURL: "smb://server1/share1")

        // Then
        XCTAssertFalse(isDuplicate, "Should not detect duplicate when excluding the share itself")
    }

    /// Test: isDuplicateMountPoint with auto-generated mount points
    func testIsDuplicateMountPointWithAutoGenerated() async throws {
        // Given - share without explicit mountPoint (will auto-generate from URL)
        let share1 = Share.createShare(
            networkShare: "smb://server1/testshare",
            authType: .krb,
            mountStatus: .unmounted,
            mountPoint: nil, // Will auto-generate "testshare"
            managed: false
        )
        await sut.addShare(share1)

        // When/Then - check against auto-generated name
        let isDuplicate1 = await sut.isDuplicateMountPoint("testshare")
        XCTAssertTrue(isDuplicate1, "Should detect duplicate with auto-generated mount point")

        let isDuplicate2 = await sut.isDuplicateMountPoint("TESTSHARE")
        XCTAssertTrue(isDuplicate2, "Should detect duplicate (case-insensitive) with auto-generated")
    }

    /// Test: isDuplicateMountPoint across managed and user shares
    func testIsDuplicateMountPointAcrossManagedAndUser() async throws {
        // Given
        let managedShare = Share.createShare(
            networkShare: "smb://mdm-server/share",
            authType: .krb,
            mountStatus: .unmounted,
            mountPoint: "ManagedShare",
            managed: true
        )
        let userShare = Share.createShare(
            networkShare: "smb://user-server/share",
            authType: .krb,
            mountStatus: .unmounted,
            mountPoint: "UserShare",
            managed: false
        )

        await sut.addShare(managedShare)
        await sut.addShare(userShare)

        // When/Then - check duplicates across both types
        XCTAssertTrue(await sut.isDuplicateMountPoint("ManagedShare"), "Should detect managed share")
        XCTAssertTrue(await sut.isDuplicateMountPoint("UserShare"), "Should detect user share")
        XCTAssertTrue(await sut.isDuplicateMountPoint("managedshare"), "Should be case-insensitive")
    }

    // MARK: - Tests: Share.effectiveMountPoint

    /// Test: effectiveMountPoint uses explicit mountPoint when set
    func testEffectiveMountPointWithExplicitMountPoint() {
        // Given
        let share = Share.createShare(
            networkShare: "smb://server.com/original",
            authType: .krb,
            mountStatus: .unmounted,
            mountPoint: "CustomName",
            managed: false
        )

        // When/Then
        XCTAssertEqual(share.effectiveMountPoint, "CustomName", "Should use explicit mountPoint")
    }

    /// Test: effectiveMountPoint auto-generates from URL when mountPoint is nil
    func testEffectiveMountPointAutoGeneratesFromURL() {
        // Given
        let share = Share.createShare(
            networkShare: "smb://server.com/testshare",
            authType: .krb,
            mountStatus: .unmounted,
            mountPoint: nil,
            managed: false
        )

        // When/Then
        XCTAssertEqual(share.effectiveMountPoint, "testshare", "Should auto-generate from URL")
    }

    /// Test: effectiveMountPoint auto-generates when mountPoint is empty
    func testEffectiveMountPointAutoGeneratesWhenEmpty() {
        // Given
        let share = Share.createShare(
            networkShare: "smb://server.com/myshare",
            authType: .krb,
            mountStatus: .unmounted,
            mountPoint: "",
            managed: false
        )

        // When/Then
        XCTAssertEqual(share.effectiveMountPoint, "myshare", "Should auto-generate when empty")
    }

    /// Test: effectiveMountPoint with nested path
    func testEffectiveMountPointWithNestedPath() {
        // Given
        let share = Share.createShare(
            networkShare: "smb://server.com/path/to/share",
            authType: .krb,
            mountStatus: .unmounted,
            mountPoint: nil,
            managed: false
        )

        // When/Then
        XCTAssertEqual(share.effectiveMountPoint, "share", "Should extract last component from nested path")
    }
} 