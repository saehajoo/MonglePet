import Combine
import Foundation

@MainActor
final class AppSettingsSession: ObservableObject {
    @Published private(set) var settings: AppSettings = .default
    @Published private(set) var isWritingEnabled = true
    @Published private(set) var loadNotice: String?
    @Published private(set) var saveErrorMessage: String?
    @Published private(set) var behaviorEditErrorMessage: String?

    var onChange: ((AppSettings) -> Void)?

    private let store: AppSettingsStore

    init(store: AppSettingsStore) {
        self.store = store
    }

    @discardableResult
    func load(
        migrationPetDefinitionProvider: ((UUID?) -> PetDefinition?)? = nil
    ) -> AppSettingsLoadResult {
        let result = store.load(
            migrationPetDefinitionProvider: migrationPetDefinitionProvider
        )
        settings = result.settings
        isWritingEnabled = result.isWritingEnabled
        loadNotice = Self.loadNotice(for: result)
        saveErrorMessage = nil
        behaviorEditErrorMessage = nil
        return result
    }

    func setUserPresentation(_ presentation: PetPresentation) {
        guard presentation == .awake || presentation == .tuckedAway else {
            return
        }

        update(
            AppSettings(
                selectedPetInstallationID: settings.selectedPetInstallationID,
                lastUserPresentation: presentation,
                overlay: settings.overlay,
                behaviorProfiles: settings.behaviorProfiles
            )
        )
    }

    func setBehaviorMode(_ mode: BehaviorMode) {
        updateActiveProfile(
            BehaviorProfile(
                petKey: settings.selectedPetKey,
                mode: mode,
                manualSequenceID: settings.manualSequenceID,
                sequences: settings.sequences,
                automaticRules: settings.automaticRules
            )
        )
    }

    func setSelectedPetInstallationID(_ installationID: UUID?) {
        let selectedSettings = AppSettings(
            selectedPetInstallationID: installationID,
            lastUserPresentation: settings.lastUserPresentation,
            overlay: settings.overlay,
            behaviorProfiles: settings.behaviorProfiles
        )
        update(
            BuiltInBehaviorPresets.normalizedDefaults(in: selectedSettings)
        )
    }

    func ensureSystemDefaultBehavior() {
        settings = BuiltInBehaviorPresets.normalizedDefaults(in: settings)
    }

    func setManualSequenceID(_ sequenceID: String) {
        guard settings.sequences.contains(where: { $0.id == sequenceID }) else {
            return
        }

        updateActiveProfile(
            BehaviorProfile(
                petKey: settings.selectedPetKey,
                mode: settings.behaviorMode,
                manualSequenceID: sequenceID,
                sequences: settings.sequences,
                automaticRules: settings.automaticRules
            )
        )
    }

    @discardableResult
    func addBehaviorSequence(named name: String) -> Bool {
        applyBehaviorEdit {
            try BehaviorSettingsEditor.addingSequence(named: name, to: settings)
        }
    }

    @discardableResult
    func removeBehaviorSequence(id sequenceID: String) -> Bool {
        applyBehaviorEdit {
            try BehaviorSettingsEditor.removingSequence(id: sequenceID, from: settings)
        }
    }

    @discardableResult
    func addBehaviorStep(to sequenceID: String) -> Bool {
        applyBehaviorEdit {
            try BehaviorSettingsEditor.addingStep(to: sequenceID, in: settings)
        }
    }

    @discardableResult
    func updateBehaviorStep(
        sequenceID: String,
        index: Int,
        motionID: String,
        repeatCount: Int
    ) -> Bool {
        applyBehaviorEdit {
            guard (1...AppSettingsLimits.maximumRepeatCount).contains(repeatCount) else {
                throw BehaviorSettingsEditError.invalidStep
            }
            return try BehaviorSettingsEditor.replacingStep(
                in: sequenceID,
                at: index,
                with: BehaviorStep(
                    motionID: motionID,
                    repeatCount: repeatCount
                ),
                settings: settings
            )
        }
    }

    @discardableResult
    func removeBehaviorStep(from sequenceID: String, at index: Int) -> Bool {
        applyBehaviorEdit {
            try BehaviorSettingsEditor.removingStep(
                from: sequenceID,
                at: index,
                settings: settings
            )
        }
    }

    @discardableResult
    func moveBehaviorStep(
        in sequenceID: String,
        from sourceIndex: Int,
        to destinationIndex: Int
    ) -> Bool {
        applyBehaviorEdit {
            try BehaviorSettingsEditor.movingStep(
                in: sequenceID,
                from: sourceIndex,
                to: destinationIndex,
                settings: settings
            )
        }
    }

    @discardableResult
    func setBehaviorSequenceRepeats(_ repeats: Bool, for sequenceID: String) -> Bool {
        applyBehaviorEdit {
            try BehaviorSettingsEditor.settingRepeats(
                repeats,
                for: sequenceID,
                in: settings
            )
        }
    }

    @discardableResult
    func addApplicationRule(bundleIdentifier: String, sequenceID: String) -> Bool {
        applyBehaviorEdit {
            try BehaviorSettingsEditor.addingApplicationRule(
                bundleIdentifier: bundleIdentifier,
                sequenceID: sequenceID,
                to: settings
            )
        }
    }

    @discardableResult
    func addIdleRule(minutes: Int, sequenceID: String) -> Bool {
        applyBehaviorEdit {
            try BehaviorSettingsEditor.addingIdleRule(
                minutes: minutes,
                sequenceID: sequenceID,
                to: settings
            )
        }
    }

    @discardableResult
    func updateAutomaticRule(_ rule: AutomaticRule) -> Bool {
        applyBehaviorEdit {
            try BehaviorSettingsEditor.replacingRule(rule, in: settings)
        }
    }

    @discardableResult
    func removeAutomaticRule(id: UUID) -> Bool {
        applyBehaviorEdit {
            try BehaviorSettingsEditor.removingRule(id: id, from: settings)
        }
    }

    @discardableResult
    func replaceBehaviorMotionReferences(
        from oldMotionID: String,
        with newMotionID: String
    ) -> Bool {
        applyBehaviorEdit {
            try BehaviorSettingsEditor.replacingMotionReferences(
                from: oldMotionID,
                with: newMotionID,
                in: settings
            )
        }
    }

    func clearBehaviorEditError() {
        behaviorEditErrorMessage = nil
    }

    func setOverlayWidth(_ width: Double, persist: Bool = true) {
        let normalizedWidth = min(
            max(width, AppSettingsLimits.minimumOverlayWidth),
            AppSettingsLimits.maximumOverlayWidth
        )
        replaceOverlay(
            OverlaySettings(
                screenIdentifier: settings.overlay.screenIdentifier,
                originX: settings.overlay.originX,
                originY: settings.overlay.originY,
                width: normalizedWidth,
                clickThrough: settings.overlay.clickThrough
            ),
            persist: persist
        )
    }

    func setClickThrough(_ clickThrough: Bool) {
        replaceOverlay(
            OverlaySettings(
                screenIdentifier: settings.overlay.screenIdentifier,
                originX: settings.overlay.originX,
                originY: settings.overlay.originY,
                width: settings.overlay.width,
                clickThrough: clickThrough
            )
        )
    }

    func setOverlayGeometry(_ overlay: OverlaySettings) {
        replaceOverlay(overlay)
    }

    func synchronizeOverlayGeometry(_ overlay: OverlaySettings) {
        let synchronizedSettings = settingsReplacingOverlay(overlay)
        guard synchronizedSettings != settings else {
            return
        }
        settings = synchronizedSettings
    }

    func persistCurrentSettings() {
        persist(settings)
    }

    private func replaceOverlay(_ overlay: OverlaySettings, persist: Bool = true) {
        update(settingsReplacingOverlay(overlay), persist: persist)
    }

    @discardableResult
    private func applyBehaviorEdit(
        _ edit: () throws -> AppSettings
    ) -> Bool {
        guard isWritingEnabled else {
            return false
        }

        do {
            let editedSettings = try edit()
            behaviorEditErrorMessage = nil
            update(editedSettings)
            return true
        } catch {
            behaviorEditErrorMessage = error.localizedDescription
            return false
        }
    }

    private func settingsReplacingOverlay(_ overlay: OverlaySettings) -> AppSettings {
        AppSettings(
            selectedPetInstallationID: settings.selectedPetInstallationID,
            lastUserPresentation: settings.lastUserPresentation,
            overlay: overlay,
            behaviorProfiles: settings.behaviorProfiles
        )
    }

    private func updateActiveProfile(_ profile: BehaviorProfile) {
        update(settings.replacingActiveBehaviorProfile(profile))
    }

    private func update(_ newSettings: AppSettings, persist shouldPersist: Bool = true) {
        guard newSettings != settings else {
            if shouldPersist {
                persistCurrentSettings()
            }
            return
        }

        settings = newSettings
        onChange?(newSettings)
        if shouldPersist {
            persist(settings)
        }
    }

    private func persist(_ settings: AppSettings) {
        guard isWritingEnabled else {
            return
        }

        do {
            try store.save(settings)
            saveErrorMessage = nil
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    private static func loadNotice(for result: AppSettingsLoadResult) -> String? {
        switch result.source {
        case let .newerSchema(version):
            return "더 새로운 설정 형식(버전 \(version))을 보호하기 위해 설정 저장을 중단했습니다."
        case .defaults:
            return nil
        case .file:
            return nil
        case .recovered:
            if result.issues.contains(where: { issue in
                if case .corruptFileQuarantined = issue {
                    return true
                }
                return false
            }) {
                return "손상된 설정 파일을 별도로 보관하고 기본 설정으로 복구했습니다."
            }
            if !result.isWritingEnabled {
                return "기존 설정 파일을 보호하기 위해 설정 저장을 중단했습니다."
            }
            return result.issues.isEmpty
                ? nil
                : "일부 잘못된 설정을 안전한 값으로 복구했습니다."
        }
    }
}

extension AppSettingsLoadResult {
    var shouldRestoreOverlayPosition: Bool {
        switch source {
        case .file:
            return true
        case .defaults, .newerSchema:
            return false
        case .recovered:
            return !issues.contains(where: { issue in
                switch issue {
                case .corruptFileQuarantined:
                    return true
                case let .invalidField(field):
                    return field == "settingsFile"
                default:
                    return false
                }
            })
        }
    }
}
