import CryptoKit
import Foundation
import XCTest
@testable import MonglePet

final class RemotePetImportSourceTests: XCTestCase {
    func testParsesDevelopmentAndProductionDetailURLs() throws {
        let development = try RemotePetImportSource(
            userInput: " https://dev.mapleroom.kr/monglepet/pets/monglepet-abc123?shared=1#preview "
        )
        XCTAssertEqual(development.environment, .development)
        XCTAssertEqual(development.petSlug, "monglepet-abc123")
        XCTAssertEqual(
            development.canonicalWebURL.absoluteString,
            "https://dev.mapleroom.kr/monglepet/pets/monglepet-abc123"
        )
        XCTAssertEqual(
            development.detailAPIURL.absoluteString,
            "https://dev-api.mapleroom.kr/api/v1/monglepet/pets/monglepet-abc123"
        )

        let production = try RemotePetImportSource(
            userInput: "https://mapleroom.kr/monglepet/pets/monglepet-def456"
        )
        XCTAssertEqual(production.environment, .production)
        XCTAssertEqual(
            production.detailAPIURL.absoluteString,
            "https://api.mapleroom.kr/api/v1/monglepet/pets/monglepet-def456"
        )
    }

    func testRejectsUntrustedOrMalformedDetailURLs() {
        let rejected = [
            "http://dev.mapleroom.kr/monglepet/pets/monglepet-abc123",
            "https://evil.example/monglepet/pets/monglepet-abc123",
            "https://dev.mapleroom.kr.evil.example/monglepet/pets/monglepet-abc123",
            "https://user@dev.mapleroom.kr/monglepet/pets/monglepet-abc123",
            "https://dev.mapleroom.kr:443/monglepet/pets/monglepet-abc123",
            "https://dev.mapleroom.kr/monglepet/pets/monglepet-abc123/extra",
            "https://dev.mapleroom.kr/monglepet/pets/MonglePet-ABC"
        ]

        for value in rejected {
            XCTAssertThrowsError(try RemotePetImportSource(userInput: value), value)
        }
    }

    func testParsesExactInstallDeepLink() throws {
        var components = URLComponents()
        components.scheme = "monglepet"
        components.host = "install"
        components.queryItems = [
            URLQueryItem(
                name: "url",
                value: "https://dev.mapleroom.kr/monglepet/pets/monglepet-abc123"
            )
        ]
        let url = try XCTUnwrap(components.url)

        let link = try RemotePetImportDeepLink(url: url)
        XCTAssertEqual(link.source.environment, .development)
        XCTAssertEqual(link.source.petSlug, "monglepet-abc123")

        XCTAssertThrowsError(
            try RemotePetImportDeepLink(
                url: URL(string: "monglepet://download?url=https://dev.mapleroom.kr")!
            )
        )
        XCTAssertThrowsError(
            try RemotePetImportDeepLink(
                url: URL(string: "monglepet://install?url=https://evil.example/pet")!
            )
        )
    }
}

final class RemotePetImportServiceTests: XCTestCase {
    func testDownloadsAndVerifiesPublishedPackage() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "RemotePetImportTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let packageData = Data("valid monglepet package".utf8)
        let checksum = sha256(packageData)
        let downloadedURL = rootURL.appendingPathComponent("download.tmp")
        try packageData.write(to: downloadedURL)
        let transport = StubRemotePetImportTransport(
            dataResponses: try makeAPIResponses(
                size: Int64(packageData.count),
                checksum: checksum
            ),
            downloadURL: downloadedURL,
            downloadResponse: try httpResponse(
                url: URL(
                    string: "https://dev-api.mapleroom.kr/media/monglepet/downloads/token"
                )!,
                contentLength: Int64(packageData.count)
            )
        )
        let service = RemotePetImportService(
            transport: transport,
            temporaryDirectoryURL: rootURL,
            currentAppVersion: SemanticVersion(major: 1, minor: 1, patch: 0)
        )

        let prepared = try await service.preparePackage(
            from: "https://dev.mapleroom.kr/monglepet/pets/monglepet-abc123"
        )
        defer {
            try? FileManager.default.removeItem(
                at: prepared.temporaryDirectoryURL
            )
        }

        XCTAssertEqual(try Data(contentsOf: prepared.packageURL), packageData)
        XCTAssertEqual(prepared.suggestedFileName, "monglepet-abc123-1.0.0.monglepet")
        let requestedURLs = await transport.requestedURLs
        XCTAssertEqual(
            requestedURLs,
            [
                "https://dev-api.mapleroom.kr/api/v1/monglepet/pets/monglepet-abc123",
                "https://dev-api.mapleroom.kr/api/v1/monglepet/pet-versions/30d59aa6-d722-4b4e-9181-e8e39425e708/download",
                "https://dev-api.mapleroom.kr/media/monglepet/downloads/token"
            ]
        )
    }

    func testRejectsDetailAndDownloadMetadataMismatchBeforeDownload() async throws {
        let detailChecksum = String(repeating: "a", count: 64)
        let downloadChecksum = String(repeating: "b", count: 64)
        let responses = try makeAPIResponses(
            size: 4,
            checksum: detailChecksum,
            downloadChecksum: downloadChecksum
        )
        let transport = StubRemotePetImportTransport(
            dataResponses: responses,
            downloadURL: URL(fileURLWithPath: "/unreachable"),
            downloadResponse: try httpResponse(
                url: URL(string: "https://dev-api.mapleroom.kr/media/monglepet/downloads/token")!
            )
        )
        let service = RemotePetImportService(transport: transport)

        await XCTAssertThrowsRemotePetImportError(.metadataMismatch) {
            _ = try await service.preparePackage(
                from: "https://dev.mapleroom.kr/monglepet/pets/monglepet-abc123"
            )
        }
        let downloadRequestCount = await transport.downloadRequestCount
        XCTAssertEqual(downloadRequestCount, 0)
    }

    func testRejectsChecksumMismatchAfterDownload() async throws {
        let rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "RemotePetImportTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: rootURL,
            withIntermediateDirectories: false
        )
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let packageData = Data("changed".utf8)
        let downloadedURL = rootURL.appendingPathComponent("download.tmp")
        try packageData.write(to: downloadedURL)
        let publishedChecksum = sha256(Data("expected".utf8))
        let transport = StubRemotePetImportTransport(
            dataResponses: try makeAPIResponses(
                size: Int64(packageData.count),
                checksum: publishedChecksum
            ),
            downloadURL: downloadedURL,
            downloadResponse: try httpResponse(
                url: URL(string: "https://dev-api.mapleroom.kr/media/monglepet/downloads/token")!,
                contentLength: Int64(packageData.count)
            )
        )
        let service = RemotePetImportService(
            transport: transport,
            temporaryDirectoryURL: rootURL
        )

        await XCTAssertThrowsRemotePetImportError(.checksumMismatch) {
            _ = try await service.preparePackage(
                from: "https://dev.mapleroom.kr/monglepet/pets/monglepet-abc123"
            )
        }
    }

    func testRejectsNewerMinimumVersionBeforeDownload() async throws {
        let checksum = String(repeating: "a", count: 64)
        let transport = StubRemotePetImportTransport(
            dataResponses: try makeAPIResponses(
                size: 4,
                checksum: checksum,
                minimumVersion: "9.0.0"
            ),
            downloadURL: URL(fileURLWithPath: "/unreachable"),
            downloadResponse: try httpResponse(
                url: URL(string: "https://dev-api.mapleroom.kr/media/monglepet/downloads/token")!
            )
        )
        let current = SemanticVersion(major: 1, minor: 1, patch: 0)
        let service = RemotePetImportService(
            transport: transport,
            currentAppVersion: current
        )

        await XCTAssertThrowsRemotePetImportError(
            .minimumAppVersionRequired(
                required: SemanticVersion(major: 9, minor: 0, patch: 0),
                current: current
            )
        ) {
            _ = try await service.preparePackage(
                from: "https://dev.mapleroom.kr/monglepet/pets/monglepet-abc123"
            )
        }
        let downloadRequestCount = await transport.downloadRequestCount
        XCTAssertEqual(downloadRequestCount, 0)
    }

    func testRejectsOversizedPublishedPackageBeforeDownload() async throws {
        let checksum = String(repeating: "a", count: 64)
        let transport = StubRemotePetImportTransport(
            dataResponses: try makeAPIResponses(
                size: RemotePetImportService.maximumPackageBytes + 1,
                checksum: checksum
            ),
            downloadURL: URL(fileURLWithPath: "/unreachable"),
            downloadResponse: try httpResponse(
                url: URL(string: "https://dev-api.mapleroom.kr/media/monglepet/downloads/token")!
            )
        )
        let service = RemotePetImportService(transport: transport)

        await XCTAssertThrowsRemotePetImportError(
            .packageTooLarge(
                maximumBytes: RemotePetImportService.maximumPackageBytes
            )
        ) {
            _ = try await service.preparePackage(
                from: "https://dev.mapleroom.kr/monglepet/pets/monglepet-abc123"
            )
        }
        let downloadRequestCount = await transport.downloadRequestCount
        XCTAssertEqual(downloadRequestCount, 0)
    }

    func testPreservesServerMessageWhenFailureDataHasDifferentShape() async throws {
        let detailURL = URL(
            string: "https://dev-api.mapleroom.kr/api/v1/monglepet/pets/monglepet-abc123"
        )!
        let failure = """
        {"status":"error","message":"공개된 펫이 아닙니다.","code":"not_public","data":{}}
        """
        let transport = StubRemotePetImportTransport(
            dataResponses: [
                detailURL.absoluteString: (
                    Data(failure.utf8),
                    try httpResponse(url: detailURL)
                )
            ],
            downloadURL: URL(fileURLWithPath: "/unreachable"),
            downloadResponse: try httpResponse(url: detailURL)
        )
        let service = RemotePetImportService(transport: transport)

        await XCTAssertThrowsRemotePetImportError(
            .serverRejected(message: "공개된 펫이 아닙니다.")
        ) {
            _ = try await service.preparePackage(
                from: "https://dev.mapleroom.kr/monglepet/pets/monglepet-abc123"
            )
        }
    }

    private func makeAPIResponses(
        size: Int64,
        checksum: String,
        downloadChecksum: String? = nil,
        minimumVersion: String = "1.1.0"
    ) throws -> [String: StubRemotePetImportTransport.DataResponse] {
        let detailURL = "https://dev-api.mapleroom.kr/api/v1/monglepet/pets/monglepet-abc123"
        let downloadMetadataURL = "https://dev-api.mapleroom.kr/api/v1/monglepet/pet-versions/30d59aa6-d722-4b4e-9181-e8e39425e708/download"
        let detailJSON = """
        {"status":"success","message":"ok","code":"ok","data":{"pet":{"slug":"monglepet-abc123","representative_version":{"pet_version_uuid":"30d59aa6-d722-4b4e-9181-e8e39425e708","minimum_app_version":"\(minimumVersion)","size_bytes":\(size),"sha256":"\(checksum)"}}}}
        """
        let downloadJSON = """
        {"status":"success","message":"ok","code":"ok","data":{"download_url":"/media/monglepet/downloads/token","filename":"monglepet-abc123-1.0.0.monglepet","size_bytes":\(size),"sha256":"\(downloadChecksum ?? checksum)"}}
        """
        return [
            detailURL: (
                Data(detailJSON.utf8),
                try httpResponse(url: URL(string: detailURL)!)
            ),
            downloadMetadataURL: (
                Data(downloadJSON.utf8),
                try httpResponse(url: URL(string: downloadMetadataURL)!)
            )
        ]
    }

    private func httpResponse(
        url: URL,
        contentLength: Int64? = nil
    ) throws -> HTTPURLResponse {
        let headers = contentLength.map { ["Content-Length": String($0)] }
        return try XCTUnwrap(
            HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: headers
            )
        )
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private func XCTAssertThrowsRemotePetImportError(
        _ expected: RemotePetImportError,
        operation: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as RemotePetImportError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }
}

@MainActor
final class RemotePetImportRequestCenterTests: XCTestCase {
    func testPublishesAndConsumesDeepLinkRequest() throws {
        let center = RemotePetImportRequestCenter()
        var components = URLComponents()
        components.scheme = "monglepet"
        components.host = "install"
        components.queryItems = [
            URLQueryItem(
                name: "url",
                value: "https://dev.mapleroom.kr/monglepet/pets/monglepet-abc123"
            )
        ]

        center.submit(deepLinkURL: try XCTUnwrap(components.url))
        let request = try XCTUnwrap(center.request)
        XCTAssertEqual(request.source.petSlug, "monglepet-abc123")
        XCTAssertNil(center.errorMessage)

        center.consume(request.id)
        XCTAssertNil(center.request)
    }
}

private actor StubRemotePetImportTransport: RemotePetImportTransport {
    typealias DataResponse = (Data, URLResponse)

    let dataResponses: [String: DataResponse]
    let downloadURL: URL
    let downloadResponse: URLResponse
    private(set) var requestedURLs: [String] = []
    private(set) var downloadRequestCount = 0

    init(
        dataResponses: [String: DataResponse],
        downloadURL: URL,
        downloadResponse: URLResponse
    ) {
        self.dataResponses = dataResponses
        self.downloadURL = downloadURL
        self.downloadResponse = downloadResponse
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let key = request.url?.absoluteString ?? ""
        requestedURLs.append(key)
        guard let response = dataResponses[key] else {
            throw URLError(.badURL)
        }
        return response
    }

    func download(for request: URLRequest) async throws -> (URL, URLResponse) {
        requestedURLs.append(request.url?.absoluteString ?? "")
        downloadRequestCount += 1
        return (downloadURL, downloadResponse)
    }
}
