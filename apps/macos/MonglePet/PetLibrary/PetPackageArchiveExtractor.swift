import Foundation
import ZIPFoundation

nonisolated struct PetPackageArchiveLimits: Equatable, Sendable {
    static let standard = PetPackageArchiveLimits(
        maximumArchiveByteCount: 20 * 1_024 * 1_024,
        maximumExpandedByteCount: 100 * 1_024 * 1_024,
        maximumEntryCount: 2_000,
        maximumCompressionRatio: 100
    )

    let maximumArchiveByteCount: UInt64
    let maximumExpandedByteCount: UInt64
    let maximumEntryCount: Int
    let maximumCompressionRatio: UInt64
}

nonisolated enum PetPackageArchiveError: Error, Equatable, Sendable {
    case invalidSource
    case archiveTooLarge
    case invalidArchive
    case invalidEntryPath(String)
    case unsupportedEntry(String)
    case duplicateEntry(String)
    case entryCountExceeded
    case expandedSizeExceeded
    case suspiciousCompressionRatio(String)
    case extractionFailed(String)
    case missingPackageRoot
    case multiplePackageRoots
}

extension PetPackageArchiveError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidSource:
            "선택한 파일이 `.monglepet` ZIP 패키지가 아닙니다."
        case .archiveTooLarge:
            "압축 패키지가 20 MiB 제한을 초과합니다."
        case .invalidArchive:
            "ZIP 패키지를 읽을 수 없거나 손상되었습니다."
        case let .invalidEntryPath(path):
            "안전하지 않은 ZIP 경로입니다: \(path)"
        case let .unsupportedEntry(path):
            "ZIP에서 허용하지 않는 항목입니다: \(path)"
        case let .duplicateEntry(path):
            "ZIP에 중복된 경로가 있습니다: \(path)"
        case .entryCountExceeded:
            "ZIP 엔트리 수가 제한을 초과합니다."
        case .expandedSizeExceeded:
            "ZIP 해제 크기가 100 MiB 제한을 초과합니다."
        case let .suspiciousCompressionRatio(path):
            "비정상적으로 높은 압축률입니다: \(path)"
        case let .extractionFailed(path):
            "ZIP 항목을 안전하게 추출하지 못했습니다: \(path)"
        case .missingPackageRoot:
            "ZIP 안에서 pet.json이 있는 패키지 루트를 찾지 못했습니다."
        case .multiplePackageRoots:
            "ZIP 안에 패키지 루트가 여러 개이거나 불필요한 최상위 항목이 있습니다."
        }
    }
}

nonisolated struct PetPackageArchiveExtractor {
    let limits: PetPackageArchiveLimits
    private let fileManager: FileManager

    init(
        limits: PetPackageArchiveLimits = .standard,
        fileManager: FileManager = .default
    ) {
        self.limits = limits
        self.fileManager = fileManager
    }

    func extractArchive(at archiveURL: URL, into workspaceURL: URL) throws -> URL {
        let archiveByteCount = try validateArchiveSource(archiveURL)
        let archive: Archive
        do {
            archive = try Archive(url: archiveURL, accessMode: .read)
        } catch {
            throw PetPackageArchiveError.invalidArchive
        }

        let entries = Array(archive)
        guard !entries.isEmpty else {
            throw PetPackageArchiveError.invalidArchive
        }
        let validatedEntries = try validate(entries: entries, archiveByteCount: archiveByteCount)

        let extractionRootURL = workspaceURL
            .appendingPathComponent("payload.monglepet", isDirectory: true)
        do {
            try fileManager.createDirectory(
                at: extractionRootURL,
                withIntermediateDirectories: false
            )
        } catch {
            throw PetPackageArchiveError.extractionFailed("payload.monglepet")
        }

        for validatedEntry in validatedEntries {
            let destinationURL = extractionRootURL
                .appendingPathComponent(validatedEntry.relativePath)
            do {
                _ = try archive.extract(
                    validatedEntry.entry,
                    to: destinationURL,
                    skipCRC32: false,
                    allowUncontainedSymlinks: false
                )
            } catch {
                throw PetPackageArchiveError.extractionFailed(validatedEntry.relativePath)
            }
        }

        return try locatePackageRoot(in: extractionRootURL)
    }

    private func validateArchiveSource(_ archiveURL: URL) throws -> UInt64 {
        var isDirectory: ObjCBool = false
        guard
            archiveURL.pathExtension.lowercased() == "monglepet",
            fileManager.fileExists(atPath: archiveURL.path, isDirectory: &isDirectory),
            !isDirectory.boolValue
        else {
            throw PetPackageArchiveError.invalidSource
        }

        do {
            let values = try archiveURL.resourceValues(
                forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]
            )
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                throw PetPackageArchiveError.invalidSource
            }
            let byteCount = UInt64(values.fileSize ?? 0)
            guard byteCount <= limits.maximumArchiveByteCount else {
                throw PetPackageArchiveError.archiveTooLarge
            }
            return byteCount
        } catch let error as PetPackageArchiveError {
            throw error
        } catch {
            throw PetPackageArchiveError.invalidSource
        }
    }

    private func validate(
        entries: [Entry],
        archiveByteCount: UInt64
    ) throws -> [ValidatedArchiveEntry] {
        guard entries.count <= limits.maximumEntryCount else {
            throw PetPackageArchiveError.entryCountExceeded
        }

        var normalizedPaths = Set<String>()
        var totalCompressedByteCount: UInt64 = 0
        var totalExpandedByteCount: UInt64 = 0
        var validatedEntries: [ValidatedArchiveEntry] = []

        for entry in entries {
            guard entry.type == .file || entry.type == .directory else {
                throw PetPackageArchiveError.unsupportedEntry(entry.path)
            }
            let relativePath = try normalizedEntryPath(entry.path, type: entry.type)
            guard normalizedPaths.insert(collisionKey(for: relativePath)).inserted else {
                throw PetPackageArchiveError.duplicateEntry(relativePath)
            }

            let compressedResult = totalCompressedByteCount.addingReportingOverflow(entry.compressedSize)
            let expandedResult = totalExpandedByteCount.addingReportingOverflow(entry.uncompressedSize)
            guard !compressedResult.overflow, !expandedResult.overflow else {
                throw PetPackageArchiveError.expandedSizeExceeded
            }
            totalCompressedByteCount = compressedResult.partialValue
            totalExpandedByteCount = expandedResult.partialValue

            guard
                totalCompressedByteCount <= archiveByteCount,
                totalExpandedByteCount <= limits.maximumExpandedByteCount
            else {
                throw PetPackageArchiveError.expandedSizeExceeded
            }
            try validateCompressionRatio(
                compressedByteCount: entry.compressedSize,
                expandedByteCount: entry.uncompressedSize,
                path: relativePath
            )
            validatedEntries.append(
                ValidatedArchiveEntry(entry: entry, relativePath: relativePath)
            )
        }

        try validateCompressionRatio(
            compressedByteCount: totalCompressedByteCount,
            expandedByteCount: totalExpandedByteCount,
            path: "전체 패키지"
        )
        try validatePathHierarchy(validatedEntries)
        return validatedEntries
    }

    private func normalizedEntryPath(_ originalPath: String, type: Entry.EntryType) throws -> String {
        var path = originalPath
        if type == .directory {
            while path.hasSuffix("/") {
                path.removeLast()
            }
        }
        guard
            !path.isEmpty,
            !(path as NSString).isAbsolutePath,
            !path.contains("\\"),
            !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else {
            throw PetPackageArchiveError.invalidEntryPath(originalPath)
        }

        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        guard
            components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
            components.first?.contains(":") != true
        else {
            throw PetPackageArchiveError.invalidEntryPath(originalPath)
        }
        return components.joined(separator: "/")
    }

    private func validatePathHierarchy(_ entries: [ValidatedArchiveEntry]) throws {
        let keyedEntries = entries.map { (collisionKey(for: $0.relativePath), $0) }
        for (path, entry) in keyedEntries where entry.entry.type == .file {
            let childPrefix = path + "/"
            if keyedEntries.contains(where: { $0.0.hasPrefix(childPrefix) }) {
                throw PetPackageArchiveError.invalidEntryPath(entry.relativePath)
            }
        }
    }

    private func collisionKey(for path: String) -> String {
        path.precomposedStringWithCanonicalMapping.lowercased()
    }

    private func validateCompressionRatio(
        compressedByteCount: UInt64,
        expandedByteCount: UInt64,
        path: String
    ) throws {
        guard expandedByteCount > 0 else {
            return
        }
        guard compressedByteCount > 0 else {
            throw PetPackageArchiveError.suspiciousCompressionRatio(path)
        }
        let maximumExpanded = compressedByteCount.multipliedReportingOverflow(
            by: limits.maximumCompressionRatio
        )
        guard maximumExpanded.overflow || expandedByteCount <= maximumExpanded.partialValue else {
            throw PetPackageArchiveError.suspiciousCompressionRatio(path)
        }
    }

    private func locatePackageRoot(in extractionRootURL: URL) throws -> URL {
        if fileManager.fileExists(
            atPath: extractionRootURL.appendingPathComponent("pet.json").path
        ) {
            return extractionRootURL
        }

        let children: [URL]
        do {
            children = try fileManager.contentsOfDirectory(
                at: extractionRootURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: []
            )
        } catch {
            throw PetPackageArchiveError.missingPackageRoot
        }
        guard children.count == 1 else {
            throw PetPackageArchiveError.multiplePackageRoots
        }

        let candidateURL = children[0]
        do {
            guard
                try candidateURL.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true,
                fileManager.fileExists(
                    atPath: candidateURL.appendingPathComponent("pet.json").path
                )
            else {
                throw PetPackageArchiveError.missingPackageRoot
            }
        } catch let error as PetPackageArchiveError {
            throw error
        } catch {
            throw PetPackageArchiveError.missingPackageRoot
        }
        return candidateURL
    }
}

private nonisolated struct ValidatedArchiveEntry {
    let entry: Entry
    let relativePath: String
}
