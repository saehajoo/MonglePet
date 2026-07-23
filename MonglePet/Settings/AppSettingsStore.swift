import Foundation

nonisolated enum AppSettingsStoreError: Error, Equatable, Sendable {
    case unavailableApplicationSupport
    case writingDisabledForNewerSchema
    case invalidSettings(String)
    case fileOperationFailed
}

extension AppSettingsStoreError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unavailableApplicationSupport:
            "Application Support 경로를 찾을 수 없습니다."
        case .writingDisabledForNewerSchema:
            "현재 앱보다 새로운 설정 파일을 보호하기 위해 저장을 중단했습니다."
        case let .invalidSettings(field):
            "저장할 설정 값이 올바르지 않습니다: \(field)"
        case .fileOperationFailed:
            "설정 파일 작업을 완료하지 못했습니다."
        }
    }
}

nonisolated final class AppSettingsStore {
    let settingsURL: URL
    private(set) var isWritingEnabled = true

    private let fileManager: FileManager
    private let quarantineIDGenerator: () -> UUID
    private let temporaryIDGenerator: () -> UUID
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(
        settingsURL: URL,
        fileManager: FileManager = .default,
        quarantineIDGenerator: @escaping () -> UUID = UUID.init,
        temporaryIDGenerator: @escaping () -> UUID = UUID.init
    ) {
        self.settingsURL = settingsURL
        self.fileManager = fileManager
        self.quarantineIDGenerator = quarantineIDGenerator
        self.temporaryIDGenerator = temporaryIDGenerator
        decoder = JSONDecoder()
        encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    }

    static func defaultSettingsURL(fileManager: FileManager = .default) throws -> URL {
        guard let applicationSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw AppSettingsStoreError.unavailableApplicationSupport
        }

        return applicationSupportURL
            .appendingPathComponent("MonglePet", isDirectory: true)
            .appendingPathComponent("settings.json", isDirectory: false)
    }

    func load(
        migrationPetDefinitionProvider: ((UUID?) -> PetDefinition?)? = nil
    ) -> AppSettingsLoadResult {
        guard fileManager.fileExists(atPath: settingsURL.path) else {
            isWritingEnabled = true
            return AppSettingsLoadResult(
                settings: .default,
                issues: [],
                source: .defaults,
                isWritingEnabled: true
            )
        }

        guard
            let attributes = try? fileManager.attributesOfItem(atPath: settingsURL.path),
            let fileSize = attributes[.size] as? NSNumber,
            fileSize.int64Value >= 0,
            fileSize.int64Value <= Int64(AppSettingsLimits.maximumFileSize),
            let data = try? Data(contentsOf: settingsURL),
            data.count <= AppSettingsLimits.maximumFileSize
        else {
            return recoverCorruptFile()
        }

        guard let envelope = try? decoder.decode(StoredSchemaEnvelope.self, from: data) else {
            return recoverCorruptFile()
        }

        if envelope.schemaVersion > AppSettingsLimits.schemaVersion {
            isWritingEnabled = false
            return AppSettingsLoadResult(
                settings: .default,
                issues: [.newerSchemaVersion(envelope.schemaVersion)],
                source: .newerSchema(envelope.schemaVersion),
                isWritingEnabled: false
            )
        }

        if envelope.schemaVersion == 1 {
            guard let storedSettings = try? decoder.decode(StoredAppSettings.self, from: data) else {
                return recoverCorruptFile()
            }
            let selectedInstallationID = storedSettings.selectedPetInstallationID
                .flatMap(UUID.init(uuidString:))
            guard
                let selectedPetDefinition = migrationPetDefinitionProvider?(
                    selectedInstallationID
                )
            else {
                isWritingEnabled = false
                return AppSettingsLoadResult(
                    settings: .default,
                    issues: [.invalidField("settingsMigration.selectedPetDefinition")],
                    source: .recovered,
                    isWritingEnabled: false
                )
            }
            do {
                let migratedV2 = try AppSettingsV1ToV2Migrator.migrate(
                    storedSettings,
                    selectedPetDefinition: selectedPetDefinition
                )
                let migratedV3 = try AppSettingsV2ToV3Migrator.migrate(
                    migratedV2.settings
                )
                try write(migratedV3.settings)
                let mapped = AppSettingsV3Mapper.domainSettings(from: migratedV3.settings)
                let issues = migratedV2.issues + migratedV3.issues + mapped.issues
                isWritingEnabled = true
                return AppSettingsLoadResult(
                    settings: mapped.settings,
                    issues: issues,
                    source: issues.isEmpty ? .file : .recovered,
                    isWritingEnabled: true
                )
            } catch {
                isWritingEnabled = false
                return AppSettingsLoadResult(
                    settings: .default,
                    issues: [.invalidField("settingsMigration")],
                    source: .recovered,
                    isWritingEnabled: false
                )
            }
        }

        if envelope.schemaVersion == 2 {
            guard let storedSettings = try? decoder.decode(
                StoredAppSettingsV2.self,
                from: data
            ) else {
                return recoverCorruptFile()
            }
            do {
                let migrated = try AppSettingsV2ToV3Migrator.migrate(storedSettings)
                try write(migrated.settings)
                let mapped = AppSettingsV3Mapper.domainSettings(from: migrated.settings)
                let issues = migrated.issues + mapped.issues
                isWritingEnabled = true
                return AppSettingsLoadResult(
                    settings: mapped.settings,
                    issues: issues,
                    source: issues.isEmpty ? .file : .recovered,
                    isWritingEnabled: true
                )
            } catch {
                isWritingEnabled = false
                return AppSettingsLoadResult(
                    settings: .default,
                    issues: [.invalidField("settingsMigration")],
                    source: .recovered,
                    isWritingEnabled: false
                )
            }
        }

        guard envelope.schemaVersion == AppSettingsLimits.schemaVersion,
              let storedSettings = try? decoder.decode(StoredAppSettingsV3.self, from: data)
        else {
            return recoverCorruptFile()
        }

        let mapped = AppSettingsV3Mapper.domainSettings(from: storedSettings)
        isWritingEnabled = true
        return AppSettingsLoadResult(
            settings: mapped.settings,
            issues: mapped.issues,
            source: mapped.issues.isEmpty ? .file : .recovered,
            isWritingEnabled: true
        )
    }

    func save(_ settings: AppSettings) throws {
        guard isWritingEnabled else {
            throw AppSettingsStoreError.writingDisabledForNewerSchema
        }

        let storedSettings: StoredAppSettingsV3
        do {
            storedSettings = try AppSettingsV3Mapper.storedSettings(from: settings)
        } catch let error as AppSettingsMappingError {
            switch error {
            case let .invalidSettings(field):
                throw AppSettingsStoreError.invalidSettings(field)
            }
        }

        try write(storedSettings)
    }

    private func write<T: Encodable>(_ storedSettings: T) throws {
        let data: Data
        do {
            data = try encoder.encode(storedSettings)
        } catch {
            throw AppSettingsStoreError.fileOperationFailed
        }
        guard data.count <= AppSettingsLimits.maximumFileSize else {
            throw AppSettingsStoreError.invalidSettings("settingsFileSize")
        }

        let parentURL = settingsURL.deletingLastPathComponent()
        let temporaryURL = parentURL.appendingPathComponent(
            ".settings-\(temporaryIDGenerator().uuidString).tmp",
            isDirectory: false
        )
        defer {
            if fileManager.fileExists(atPath: temporaryURL.path) {
                try? fileManager.removeItem(at: temporaryURL)
            }
        }

        do {
            try fileManager.createDirectory(
                at: parentURL,
                withIntermediateDirectories: true
            )
            guard fileManager.createFile(atPath: temporaryURL.path, contents: nil) else {
                throw AppSettingsStoreError.fileOperationFailed
            }

            let handle = try FileHandle(forWritingTo: temporaryURL)
            do {
                try handle.write(contentsOf: data)
                try handle.synchronize()
                try handle.close()
            } catch {
                try? handle.close()
                throw error
            }

            if fileManager.fileExists(atPath: settingsURL.path) {
                _ = try fileManager.replaceItemAt(settingsURL, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: settingsURL)
            }
        } catch let error as AppSettingsStoreError {
            throw error
        } catch {
            throw AppSettingsStoreError.fileOperationFailed
        }
    }

    private func recoverCorruptFile() -> AppSettingsLoadResult {
        let quarantineURL = settingsURL
            .deletingLastPathComponent()
            .appendingPathComponent(
                "settings.corrupt-\(quarantineIDGenerator().uuidString).json",
                isDirectory: false
            )

        do {
            try fileManager.moveItem(at: settingsURL, to: quarantineURL)
            isWritingEnabled = true
            return AppSettingsLoadResult(
                settings: .default,
                issues: [.corruptFileQuarantined(quarantineURL.lastPathComponent)],
                source: .recovered,
                isWritingEnabled: true
            )
        } catch {
            isWritingEnabled = false
            return AppSettingsLoadResult(
                settings: .default,
                issues: [.invalidField("settingsFile")],
                source: .recovered,
                isWritingEnabled: false
            )
        }
    }
}
