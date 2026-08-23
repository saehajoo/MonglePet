import CryptoKit
import Foundation

nonisolated struct RemotePetImportSource: Equatable, Sendable {
    enum Environment: String, Equatable, Sendable {
        case development
        case production

        var webHost: String {
            switch self {
            case .development:
                "dev.mapleroom.kr"
            case .production:
                "mapleroom.kr"
            }
        }

        var apiBaseURL: URL {
            switch self {
            case .development:
                URL(string: "https://dev-api.mapleroom.kr/api/v1")!
            case .production:
                URL(string: "https://api.mapleroom.kr/api/v1")!
            }
        }
    }

    let environment: Environment
    let petSlug: String

    var canonicalWebURL: URL {
        URL(string: "https://\(environment.webHost)/monglepet/pets/\(petSlug)")!
    }

    var detailAPIURL: URL {
        environment.apiBaseURL
            .appendingPathComponent("monglepet")
            .appendingPathComponent("pets")
            .appendingPathComponent(petSlug)
    }

    init(webURL: URL) throws {
        guard
            let components = URLComponents(
                url: webURL,
                resolvingAgainstBaseURL: false
            ),
            components.scheme?.lowercased() == "https",
            components.user == nil,
            components.password == nil,
            components.port == nil,
            let host = components.host?.lowercased(),
            let environment = Environment.allCases.first(where: {
                $0.webHost == host
            })
        else {
            throw RemotePetImportError.unsupportedWebURL
        }

        let pathComponents = components.path.split(separator: "/")
        guard
            pathComponents.count == 3,
            pathComponents[0] == "monglepet",
            pathComponents[1] == "pets"
        else {
            throw RemotePetImportError.unsupportedWebURL
        }

        let slug = String(pathComponents[2])
        guard Self.isValidPetSlug(slug) else {
            throw RemotePetImportError.unsupportedWebURL
        }

        self.environment = environment
        petSlug = slug
    }

    init(userInput: String) throws {
        guard let url = URL(string: userInput.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw RemotePetImportError.unsupportedWebURL
        }
        try self.init(webURL: url)
    }

    private static func isValidPetSlug(_ value: String) -> Bool {
        guard (1...128).contains(value.utf8.count) else {
            return false
        }
        return value.unicodeScalars.allSatisfy { scalar in
            CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
                .contains(scalar)
        }
    }
}

extension RemotePetImportSource.Environment: CaseIterable {}

nonisolated struct RemotePetImportDeepLink: Equatable, Sendable {
    let source: RemotePetImportSource

    init(url: URL) throws {
        guard
            let components = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
            ),
            components.scheme?.lowercased() == "monglepet",
            components.host?.lowercased() == "install",
            components.path.isEmpty,
            components.user == nil,
            components.password == nil,
            components.port == nil,
            let queryItems = components.queryItems,
            queryItems.filter({ $0.name == "url" }).count == 1,
            queryItems.count == 1,
            let value = queryItems.first?.value
        else {
            throw RemotePetImportError.invalidDeepLink
        }

        do {
            source = try RemotePetImportSource(userInput: value)
        } catch {
            throw RemotePetImportError.invalidDeepLink
        }
    }
}

nonisolated struct RemotePetPreparedPackage: Equatable, Sendable {
    let packageURL: URL
    let temporaryDirectoryURL: URL
    let source: RemotePetImportSource
    let suggestedFileName: String
}

nonisolated enum RemotePetImportError: Error, Equatable, Sendable {
    case unsupportedWebURL
    case invalidDeepLink
    case invalidServerResponse
    case serverRejected(message: String)
    case metadataMismatch
    case packageTooLarge(maximumBytes: Int64)
    case packageSizeMismatch
    case checksumMismatch
    case minimumAppVersionRequired(required: SemanticVersion, current: SemanticVersion)
}

extension RemotePetImportError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unsupportedWebURL:
            "지원하는 MonglePet 펫 상세 주소를 입력해 주세요."
        case .invalidDeepLink:
            "MonglePet에서 열기 링크가 올바르지 않습니다."
        case .invalidServerResponse:
            "펫 서버의 응답을 확인할 수 없습니다. 잠시 뒤 다시 시도해 주세요."
        case let .serverRejected(message):
            message.isEmpty ? "이 펫을 다운로드할 수 없습니다." : message
        case .metadataMismatch:
            "펫 상세 정보와 다운로드 정보가 일치하지 않아 가져오기를 중단했습니다."
        case let .packageTooLarge(maximumBytes):
            "패키지가 최대 허용 크기 \(maximumBytes / 1_048_576) MiB를 초과합니다."
        case .packageSizeMismatch:
            "다운로드한 패키지 크기가 게시된 정보와 일치하지 않습니다."
        case .checksumMismatch:
            "다운로드한 패키지의 SHA-256이 게시된 정보와 일치하지 않습니다."
        case let .minimumAppVersionRequired(required, current):
            "이 펫은 MonglePet \(required) 이상이 필요합니다. 현재 버전은 \(current)입니다."
        }
    }
}

nonisolated protocol RemotePetImportTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
    func download(for request: URLRequest) async throws -> (URL, URLResponse)
}

nonisolated struct URLSessionRemotePetImportTransport: RemotePetImportTransport {
    private let session: URLSession
    private let redirectDelegate: RemotePetImportRedirectDelegate?

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
            redirectDelegate = nil
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.httpCookieStorage = nil
            configuration.urlCredentialStorage = nil
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 60
            let redirectDelegate = RemotePetImportRedirectDelegate()
            self.redirectDelegate = redirectDelegate
            self.session = URLSession(
                configuration: configuration,
                delegate: redirectDelegate,
                delegateQueue: nil
            )
        }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await session.data(for: request)
    }

    func download(for request: URLRequest) async throws -> (URL, URLResponse) {
        try await session.download(for: request)
    }
}

private nonisolated final class RemotePetImportRedirectDelegate:
    NSObject,
    URLSessionTaskDelegate,
    @unchecked Sendable
{
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        guard
            let originalURL = task.originalRequest?.url,
            let redirectedURL = request.url,
            originalURL.scheme?.lowercased() == redirectedURL.scheme?.lowercased(),
            originalURL.host?.lowercased() == redirectedURL.host?.lowercased(),
            originalURL.port == redirectedURL.port
        else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}

actor RemotePetImportService {
    static let maximumPackageBytes: Int64 = 20 * 1_024 * 1_024

    private let transport: any RemotePetImportTransport
    private let fileManager: FileManager
    private let temporaryDirectoryURL: URL
    private let currentAppVersion: SemanticVersion
    private let decoder = JSONDecoder()

    init(
        transport: any RemotePetImportTransport = URLSessionRemotePetImportTransport(),
        fileManager: FileManager = .default,
        temporaryDirectoryURL: URL? = nil,
        currentAppVersion: SemanticVersion = MonglePetAppVersion.current.semanticVersion
    ) {
        self.transport = transport
        self.fileManager = fileManager
        self.temporaryDirectoryURL = temporaryDirectoryURL ?? fileManager.temporaryDirectory
        self.currentAppVersion = currentAppVersion
    }

    func preparePackage(from userInput: String) async throws -> RemotePetPreparedPackage {
        let source = try RemotePetImportSource(userInput: userInput)
        return try await preparePackage(from: source)
    }

    func preparePackage(from source: RemotePetImportSource) async throws -> RemotePetPreparedPackage {
        let detail: PetDetailData = try await fetchJSON(from: source.detailAPIURL)
        guard detail.pet.slug == source.petSlug else {
            throw RemotePetImportError.metadataMismatch
        }

        let version = detail.pet.representativeVersion
        try validate(metadata: version)

        guard let requiredVersion = SemanticVersion(version.minimumAppVersion) else {
            throw RemotePetImportError.invalidServerResponse
        }
        if currentAppVersion < requiredVersion {
            throw RemotePetImportError.minimumAppVersionRequired(
                required: requiredVersion,
                current: currentAppVersion
            )
        }

        guard UUID(uuidString: version.petVersionUUID) != nil else {
            throw RemotePetImportError.invalidServerResponse
        }
        let downloadMetadataURL = source.environment.apiBaseURL
            .appendingPathComponent("monglepet")
            .appendingPathComponent("pet-versions")
            .appendingPathComponent(version.petVersionUUID)
            .appendingPathComponent("download")
        let download: PetDownloadData = try await fetchJSON(from: downloadMetadataURL)

        guard
            download.sizeBytes == version.sizeBytes,
            download.sha256.lowercased() == version.sha256.lowercased()
        else {
            throw RemotePetImportError.metadataMismatch
        }
        try validate(metadata: download)

        let packageURL = try validatedDownloadURL(
            download.downloadURL,
            environment: source.environment
        )
        let request = makeRequest(url: packageURL)
        let (downloadedURL, response) = try await transport.download(for: request)
        var didMoveDownloadedFile = false
        defer {
            if !didMoveDownloadedFile {
                try? fileManager.removeItem(at: downloadedURL)
            }
        }
        try validateHTTPResponse(response)
        guard
            let responseURL = response.url,
            responseURL.scheme?.lowercased() == packageURL.scheme?.lowercased(),
            responseURL.host?.lowercased() == packageURL.host?.lowercased(),
            responseURL.port == packageURL.port,
            responseURL.path.hasPrefix("/media/monglepet/downloads/")
        else {
            throw RemotePetImportError.invalidServerResponse
        }

        if response.expectedContentLength > Self.maximumPackageBytes {
            throw RemotePetImportError.packageTooLarge(
                maximumBytes: Self.maximumPackageBytes
            )
        }

        let attributes = try fileManager.attributesOfItem(atPath: downloadedURL.path)
        guard let fileSize = attributes[.size] as? NSNumber else {
            throw RemotePetImportError.invalidServerResponse
        }
        let actualSize = fileSize.int64Value
        guard actualSize <= Self.maximumPackageBytes else {
            throw RemotePetImportError.packageTooLarge(
                maximumBytes: Self.maximumPackageBytes
            )
        }
        guard actualSize == download.sizeBytes else {
            throw RemotePetImportError.packageSizeMismatch
        }

        let actualSHA256 = try sha256(of: downloadedURL)
        guard actualSHA256 == download.sha256.lowercased() else {
            throw RemotePetImportError.checksumMismatch
        }

        let workspaceURL = temporaryDirectoryURL.appendingPathComponent(
            "MonglePetRemoteImport-\(UUID().uuidString)",
            isDirectory: true
        )
        do {
            try fileManager.createDirectory(
                at: workspaceURL,
                withIntermediateDirectories: false
            )
            let ownedPackageURL = workspaceURL.appendingPathComponent(
                "package.monglepet",
                isDirectory: false
            )
            try fileManager.moveItem(at: downloadedURL, to: ownedPackageURL)
            didMoveDownloadedFile = true
            return RemotePetPreparedPackage(
                packageURL: ownedPackageURL,
                temporaryDirectoryURL: workspaceURL,
                source: source,
                suggestedFileName: download.filename
            )
        } catch {
            try? fileManager.removeItem(at: workspaceURL)
            throw error
        }
    }

    private func fetchJSON<Value: Decodable>(from url: URL) async throws -> Value {
        let (data, response) = try await transport.data(for: makeRequest(url: url))
        try validateHTTPResponse(response)

        let statusEnvelope: APIStatusEnvelope
        do {
            statusEnvelope = try decoder.decode(APIStatusEnvelope.self, from: data)
        } catch {
            throw RemotePetImportError.invalidServerResponse
        }
        guard statusEnvelope.status == "success", statusEnvelope.code == "ok" else {
            throw RemotePetImportError.serverRejected(
                message: statusEnvelope.message
            )
        }

        let envelope: APIEnvelope<Value>
        do {
            envelope = try decoder.decode(APIEnvelope<Value>.self, from: data)
        } catch {
            throw RemotePetImportError.invalidServerResponse
        }
        guard let value = envelope.data else {
            throw RemotePetImportError.invalidServerResponse
        }
        return value
    }

    private func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func validateHTTPResponse(_ response: URLResponse) throws {
        guard
            let response = response as? HTTPURLResponse,
            (200..<300).contains(response.statusCode)
        else {
            throw RemotePetImportError.invalidServerResponse
        }
    }

    private func validate(metadata: some PetDownloadMetadata) throws {
        guard
            metadata.sizeBytes >= 0,
            metadata.sizeBytes <= Self.maximumPackageBytes,
            metadata.sha256.count == 64,
            metadata.sha256.unicodeScalars.allSatisfy({
                CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0)
            })
        else {
            if metadata.sizeBytes > Self.maximumPackageBytes {
                throw RemotePetImportError.packageTooLarge(
                    maximumBytes: Self.maximumPackageBytes
                )
            }
            throw RemotePetImportError.invalidServerResponse
        }
    }

    private func validatedDownloadURL(
        _ value: String,
        environment: RemotePetImportSource.Environment
    ) throws -> URL {
        let prefix = "/media/monglepet/downloads/"
        let token = String(value.dropFirst(prefix.count))
        guard
            value.hasPrefix(prefix),
            !token.isEmpty,
            token.utf8.count <= 512,
            !token.contains("/"),
            token.unicodeScalars.allSatisfy({
                CharacterSet(
                    charactersIn:
                        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
                )
                    .contains($0)
            }),
            let url = URL(string: value, relativeTo: environment.apiBaseURL)?.absoluteURL,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.scheme?.lowercased() == "https",
            components.host?.lowercased() == environment.apiBaseURL.host?.lowercased(),
            components.port == nil,
            components.user == nil,
            components.password == nil,
            components.path.hasPrefix("/media/monglepet/downloads/")
        else {
            throw RemotePetImportError.invalidServerResponse
        }
        return url
    }

    private func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 64 * 1_024), !data.isEmpty {
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

private nonisolated protocol PetDownloadMetadata {
    var sizeBytes: Int64 { get }
    var sha256: String { get }
}

private nonisolated struct APIEnvelope<Value: Decodable>: Decodable {
    let status: String
    let message: String
    let code: String
    let data: Value?
}

private nonisolated struct APIStatusEnvelope: Decodable {
    let status: String
    let message: String
    let code: String
}

private nonisolated struct PetDetailData: Decodable {
    let pet: Pet

    struct Pet: Decodable {
        let slug: String
        let representativeVersion: PetVersion

        enum CodingKeys: String, CodingKey {
            case slug
            case representativeVersion = "representative_version"
        }
    }
}

private nonisolated struct PetVersion: Decodable, PetDownloadMetadata {
    let petVersionUUID: String
    let minimumAppVersion: String
    let sizeBytes: Int64
    let sha256: String

    enum CodingKeys: String, CodingKey {
        case petVersionUUID = "pet_version_uuid"
        case minimumAppVersion = "minimum_app_version"
        case sizeBytes = "size_bytes"
        case sha256
    }
}

private nonisolated struct PetDownloadData: Decodable, PetDownloadMetadata {
    let downloadURL: String
    let filename: String
    let sizeBytes: Int64
    let sha256: String

    enum CodingKeys: String, CodingKey {
        case downloadURL = "download_url"
        case filename
        case sizeBytes = "size_bytes"
        case sha256
    }
}
