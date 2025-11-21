import XCTest
@testable import Network_Share_Mounter

final class ShareHelpersTests: XCTestCase {

    // MARK: - Tests: String.isValidMountPointName

    func testValidMountPointNames() {
        // Valid names with various allowed characters
        XCTAssertTrue("share".isValidMountPointName, "Simple name should be valid")
        XCTAssertTrue("my-share".isValidMountPointName, "Name with dash should be valid")
        XCTAssertTrue("my_share".isValidMountPointName, "Name with underscore should be valid")
        XCTAssertTrue("share 123".isValidMountPointName, "Name with space should be valid")
        XCTAssertTrue("Ärger".isValidMountPointName, "Name with umlauts should be valid")
        XCTAssertTrue("café".isValidMountPointName, "Name with accented chars should be valid")
        XCTAssertTrue("test:share".isValidMountPointName, "Name with colon should be valid (APFS)")
        XCTAssertTrue("share(1)".isValidMountPointName, "Name with parentheses should be valid")
        XCTAssertTrue("share-123_test".isValidMountPointName, "Complex valid name should be valid")
    }

    func testInvalidMountPointNames() {
        // Empty or whitespace
        XCTAssertFalse("".isValidMountPointName, "Empty string should be invalid")
        XCTAssertFalse(" share".isValidMountPointName, "Leading whitespace should be invalid")
        XCTAssertFalse("share ".isValidMountPointName, "Trailing whitespace should be invalid")
        XCTAssertFalse("  ".isValidMountPointName, "Only whitespace should be invalid")

        // Forbidden characters
        XCTAssertFalse("share/test".isValidMountPointName, "Forward slash should be invalid")
        XCTAssertFalse("share\ntest".isValidMountPointName, "Newline should be invalid")
        XCTAssertFalse("share\ttest".isValidMountPointName, "Tab should be invalid")
        XCTAssertFalse("share\0test".isValidMountPointName, "Null byte should be invalid")

        // Too long
        let longName = String(repeating: "a", count: 201)
        XCTAssertFalse(longName.isValidMountPointName, "Name > 200 chars should be invalid")
    }

    func testBoundaryMountPointNameLength() {
        let maxValidLength = String(repeating: "a", count: 200)
        let justTooLong = String(repeating: "a", count: 201)

        XCTAssertTrue(maxValidLength.isValidMountPointName, "200 char name should be valid")
        XCTAssertFalse(justTooLong.isValidMountPointName, "201 char name should be invalid")
    }

    // MARK: - Tests: extractShareName(from:)

    func testExtractShareNameFromSimpleURL() {
        // Simple SMB share
        let result = extractShareName(from: "smb://server.example.com/share")
        XCTAssertEqual(result, "share", "Should extract 'share' from simple URL")
    }

    func testExtractShareNameFromNestedPath() {
        // SMB share with nested path
        let result = extractShareName(from: "smb://server.example.com/path/to/share")
        XCTAssertEqual(result, "share", "Should extract last component from nested path")
    }

    func testExtractShareNameFromAFP() {
        // AFP share
        let result = extractShareName(from: "afp://server.local/documents")
        XCTAssertEqual(result, "documents", "Should extract share name from AFP URL")
    }

    func testExtractShareNameFromWebDAV() {
        // WebDAV share
        let result = extractShareName(from: "https://webdav.example.com/share")
        XCTAssertEqual(result, "share", "Should extract share name from WebDAV URL")
    }

    func testExtractShareNameWithSpecialCharacters() {
        // Share name with special characters
        let result = extractShareName(from: "smb://server.com/my-share_123")
        XCTAssertEqual(result, "my-share_123", "Should preserve special characters")
    }

    func testExtractShareNameWithSpaces() {
        // Share name with spaces (URL encoded)
        let result = extractShareName(from: "smb://server.com/my%20share")
        XCTAssertEqual(result, "my%20share", "Should handle URL-encoded spaces")
    }

    func testExtractShareNameFromInvalidURL() {
        // Invalid URL should return fallback
        let result = extractShareName(from: "not-a-valid-url")
        XCTAssertEqual(result, "share", "Should return fallback 'share' for invalid URL")
    }

    func testExtractShareNameFromEmptyPath() {
        // URL with no path component
        let result = extractShareName(from: "smb://server.com/")
        XCTAssertEqual(result, "share", "Should return fallback for empty path")
    }

    func testExtractShareNameFromServerOnly() {
        // URL with only server, no share
        let result = extractShareName(from: "smb://server.com")
        XCTAssertEqual(result, "share", "Should return fallback when no share specified")
    }

    func testExtractShareNameRealWorldExamples() {
        // Real-world FAU examples
        XCTAssertEqual(
            extractShareName(from: "smb://fs.rrze.uni-erlangen.de/projects"),
            "projects",
            "Should extract from FAU RRZE server"
        )

        XCTAssertEqual(
            extractShareName(from: "smb://fileserver.domain.de/franco"),
            "franco",
            "Should extract from user's example"
        )
    }
}
