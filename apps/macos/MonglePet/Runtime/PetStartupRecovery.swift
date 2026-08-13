import Foundation

nonisolated struct PetStartupRecoveryRecord: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let restoringInstanceID: UUID
    let reason: PetStartupRecoveryReason

    init(
        restoringInstanceID: UUID,
        reason: PetStartupRecoveryReason = .interruptedRestore
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.restoringInstanceID = restoringInstanceID
        self.reason = reason
    }
}

nonisolated enum PetStartupRecoveryReason: String, Codable, Sendable {
    case interruptedRestore
    case userRequestedSafeMode
}

nonisolated protocol PetStartupRecoveryStoring: Sendable {
    func pendingRecord() -> PetStartupRecoveryRecord?
    func markRestoring(_ instanceID: UUID) throws
    func markSafeMode(_ instanceID: UUID) throws
    func clear() throws
}

nonisolated final class PetStartupRecoveryStore:
    PetStartupRecoveryStoring,
    @unchecked Sendable
{
    static let maximumFileSize = 4 * 1_024

    let journalURL: URL
    private let fileManager: FileManager
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    init(
        journalURL: URL,
        fileManager: FileManager = .default
    ) {
        self.journalURL = journalURL
        self.fileManager = fileManager
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    static func journalURL(for settingsURL: URL) -> URL {
        settingsURL.deletingLastPathComponent()
            .appendingPathComponent(
                "startup-recovery.json",
                isDirectory: false
            )
    }

    func pendingRecord() -> PetStartupRecoveryRecord? {
        guard fileManager.fileExists(atPath: journalURL.path) else {
            return nil
        }
        guard
            let attributes = try? fileManager.attributesOfItem(
                atPath: journalURL.path
            ),
            let fileSize = attributes[.size] as? NSNumber,
            fileSize.intValue > 0,
            fileSize.intValue <= Self.maximumFileSize,
            let data = try? Data(contentsOf: journalURL),
            data.count <= Self.maximumFileSize,
            let record = try? decoder.decode(
                PetStartupRecoveryRecord.self,
                from: data
            ),
            record.schemaVersion
                == PetStartupRecoveryRecord.currentSchemaVersion
        else {
            try? clear()
            return nil
        }
        return record
    }

    func markRestoring(_ instanceID: UUID) throws {
        try write(
            PetStartupRecoveryRecord(
                restoringInstanceID: instanceID,
                reason: .interruptedRestore
            )
        )
    }

    func markSafeMode(_ instanceID: UUID) throws {
        try write(
            PetStartupRecoveryRecord(
                restoringInstanceID: instanceID,
                reason: .userRequestedSafeMode
            )
        )
    }

    private func write(_ record: PetStartupRecoveryRecord) throws {
        let parentURL = journalURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: parentURL,
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(record)
        try data.write(to: journalURL, options: .atomic)
    }

    func clear() throws {
        guard fileManager.fileExists(atPath: journalURL.path) else {
            return
        }
        try fileManager.removeItem(at: journalURL)
    }
}

@MainActor
final class PetStartupRestorer {
    private let recoveryStore: any PetStartupRecoveryStoring

    init(recoveryStore: any PetStartupRecoveryStoring) {
        self.recoveryStore = recoveryStore
    }

    func restore(
        instanceIDs: [UUID],
        restoreStep: (UUID) throws -> Void
    ) throws {
        for instanceID in instanceIDs {
            try recoveryStore.markRestoring(instanceID)
            try restoreStep(instanceID)
            try recoveryStore.clear()
        }
    }
}
