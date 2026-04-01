//
//  AppcastValidationTests.swift
//  Network Share MounterTests
//
//  Integration tests that validate the Sparkle appcast feed is reachable and
//  contains all required fields for update distribution.
//
//  NOTE: These tests require network access to https://faumac.rrze.fau.de
//  They will fail in environments without internet connectivity.
//

import XCTest

// MARK: - Appcast Data Models

private struct AppcastItem {
    var title: String?
    var version: String?                // sparkle:version (build number)
    var shortVersionString: String?     // sparkle:shortVersionString (marketing version)
    var downloadURL: URL?               // <enclosure url="...">
    var fileLength: Int?                // <enclosure length="...">
    var edSignature: String?            // sparkle:edSignature
    var releaseNotesURL: URL?           // <sparkle:releaseNotesLink>
    var releaseNotesHTML: String?       // <description> inline HTML
    var pubDate: String?
    var minimumSystemVersion: String?   // sparkle:minimumSystemVersion
}

private struct ParsedAppcast {
    var channelTitle: String?
    var items: [AppcastItem] = []
}

// MARK: - Appcast XML Parser

private final class AppcastXMLParser: NSObject, XMLParserDelegate {

    private(set) var appcast = ParsedAppcast()
    private var currentItem: AppcastItem?
    private var currentValue = ""

    static func parse(data: Data) throws -> ParsedAppcast {
        let delegate = AppcastXMLParser()
        let xmlParser = XMLParser(data: data)
        xmlParser.delegate = delegate
        guard xmlParser.parse() else {
            throw xmlParser.parserError ?? NSError(
                domain: "AppcastXMLParser", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Unknown XML parse error"]
            )
        }
        return delegate.appcast
    }

    func parser(
        _ parser: XMLParser,
        didStartElement element: String,
        namespaceURI: String?,
        qualifiedName _: String?,
        attributes: [String: String]
    ) {
        currentValue = ""

        switch element {
        case "item":
            currentItem = AppcastItem()
        case "enclosure" where currentItem != nil:
            if let urlString = attributes["url"], let url = URL(string: urlString) {
                currentItem?.downloadURL = url
            }
            if let lengthString = attributes["length"], let length = Int(lengthString) {
                currentItem?.fileLength = length
            }
            // Sparkle namespace attributes appear with "sparkle:" prefix when
            // XMLParser runs without namespace processing (default behavior)
            currentItem?.version = attributes["sparkle:version"]
            currentItem?.shortVersionString = attributes["sparkle:shortVersionString"]
            currentItem?.edSignature = attributes["sparkle:edSignature"]
            currentItem?.minimumSystemVersion = attributes["sparkle:minimumSystemVersion"]
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentValue += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement element: String,
        namespaceURI: String?,
        qualifiedName _: String?
    ) {
        let value = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { currentValue = "" }

        if element == "item" {
            if let item = currentItem {
                appcast.items.append(item)
            }
            currentItem = nil
            return
        }

        if var item = currentItem {
            switch element {
            case "title":
                item.title = value
            case "pubDate":
                item.pubDate = value
            case "sparkle:releaseNotesLink":
                item.releaseNotesURL = URL(string: value)
            case "description":
                item.releaseNotesHTML = value.isEmpty ? nil : value
            case "sparkle:minimumSystemVersion":
                item.minimumSystemVersion = value
            default:
                break
            }
            currentItem = item
        } else if element == "title", appcast.channelTitle == nil {
            appcast.channelTitle = value
        }
    }
}

// MARK: - Tests

final class AppcastValidationTests: XCTestCase {

    // Must match SUFeedURL in Network-Share-Mounter-Info.plist
    private let appcastURL = URL(string: "https://faumac.rrze.fau.de/nsm-appcast")!

    // Shared appcast result – fetched once per test run via setUp
    private var appcast: ParsedAppcast?

    override func setUp() async throws {
        try await super.setUp()
        do {
            let (data, response) = try await URLSession.shared.data(from: appcastURL)
            let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
            guard httpResponse.statusCode == 200 else {
                throw XCTSkip("Appcast URL returned HTTP \(httpResponse.statusCode) – skipping tests")
            }
            appcast = try AppcastXMLParser.parse(data: data)
        } catch let urlError as URLError {
            throw XCTSkip("Network unavailable (\(urlError.localizedDescription)) – skipping appcast tests")
        }
    }

    // MARK: - Connectivity

    func testAppcastURLReturnsHTTP200() async throws {
        let (_, response) = try await URLSession.shared.data(from: appcastURL)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(httpResponse.statusCode, 200, "Appcast URL must return HTTP 200")
    }

    // MARK: - Feed Structure

    func testAppcastContainsAtLeastOneItem() throws {
        let feed = try XCTUnwrap(appcast)
        XCTAssertFalse(feed.items.isEmpty, "Appcast must contain at least one release item")
    }

    // MARK: - Latest Item: Required Fields

    func testLatestItemHasTitle() throws {
        let latest = try latestItem()
        let title = try XCTUnwrap(latest.title, "Latest item must have a <title>")
        XCTAssertFalse(title.isEmpty, "<title> must not be empty")
    }

    func testLatestItemHasBuildVersion() throws {
        let latest = try latestItem()
        let version = try XCTUnwrap(
            latest.version,
            "Latest item must have sparkle:version in <enclosure> (build number)"
        )
        XCTAssertFalse(version.isEmpty, "sparkle:version must not be empty")
        XCTAssertNotNil(Int(version), "sparkle:version should be parseable as an integer build number, got: \(version)")
    }

    func testLatestItemHasShortVersionString() throws {
        let latest = try latestItem()
        let shortVersion = try XCTUnwrap(
            latest.shortVersionString,
            "Latest item must have sparkle:shortVersionString in <enclosure> (marketing version)"
        )
        XCTAssertFalse(shortVersion.isEmpty, "sparkle:shortVersionString must not be empty")
    }

    func testLatestItemHasDownloadURL() throws {
        let latest = try latestItem()
        let url = try XCTUnwrap(latest.downloadURL, "Latest item must have url in <enclosure>")
        XCTAssertFalse(url.absoluteString.isEmpty, "Download URL must not be empty")
    }

    func testLatestItemDownloadURLUsesHTTPS() throws {
        let latest = try latestItem()
        let url = try XCTUnwrap(latest.downloadURL)
        XCTAssertEqual(url.scheme?.lowercased(), "https", "Download URL must use HTTPS, got: \(url.absoluteString)")
    }

    func testLatestItemHasFileLength() throws {
        let latest = try latestItem()
        let length = try XCTUnwrap(latest.fileLength, "Latest item must have length in <enclosure>")
        XCTAssertGreaterThan(length, 0, "File length must be a positive value")
    }

    func testLatestItemHasEdSignature() throws {
        let latest = try latestItem()
        let signature = try XCTUnwrap(
            latest.edSignature,
            "Latest item must have sparkle:edSignature in <enclosure> (required for update verification)"
        )
        XCTAssertFalse(signature.isEmpty, "sparkle:edSignature must not be empty")
    }

    func testLatestItemHasReleaseNotes() throws {
        let latest = try latestItem()
        let hasNotes = latest.releaseNotesURL != nil || !(latest.releaseNotesHTML?.isEmpty ?? true)
        XCTAssertTrue(
            hasNotes,
            "Latest item must have either <sparkle:releaseNotesLink> or inline <description> with release notes"
        )
    }

    func testLatestItemHasPubDate() throws {
        let latest = try latestItem()
        let pubDate = try XCTUnwrap(latest.pubDate, "Latest item must have a <pubDate>")
        XCTAssertFalse(pubDate.isEmpty, "<pubDate> must not be empty")
    }

    // MARK: - Download URL Reachability

    func testDownloadURLIsReachable() async throws {
        let latest = try latestItem()
        let url = try XCTUnwrap(latest.downloadURL)

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 30

        let (_, response) = try await URLSession.shared.data(for: request)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(
            httpResponse.statusCode, 200,
            "Download URL must be reachable via HEAD request: \(url.absoluteString)"
        )
    }

    // MARK: - Version Consistency

    func testAppcastVersionIsNotOlderThanCurrentBuild() throws {
        let latest = try latestItem()
        let appcastVersionString = try XCTUnwrap(latest.version, "sparkle:version must be present for comparison")
        let appcastBuild = try XCTUnwrap(
            Int(appcastVersionString),
            "sparkle:version must be parseable as integer, got: \(appcastVersionString)"
        )

        // In the test runner the main bundle is the test host app bundle
        let currentBuildString = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        let currentBuild = Int(currentBuildString) ?? 0

        XCTAssertGreaterThanOrEqual(
            appcastBuild,
            currentBuild,
            "Appcast must contain a version >= the running build (\(currentBuild)). "
            + "Appcast has: \(appcastBuild). The appcast may be outdated."
        )
    }

    // MARK: - Helpers

    private func latestItem() throws -> AppcastItem {
        let feed = try XCTUnwrap(appcast, "Appcast was not fetched (network unavailable?)")
        return try XCTUnwrap(feed.items.first, "Appcast contains no items")
    }
}
