import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settingsSession: AppSettingsSession
    @ObservedObject var petLibrarySession: PetLibrarySession

    var body: some View {
        TabView {
            GeneralSettingsView(
                settingsSession: settingsSession,
                petLibrarySession: petLibrarySession
            )
                .tabItem {
                    Label("일반", systemImage: "gearshape")
                }

            MovementSettingsView(
                settingsSession: settingsSession,
                petDefinition: petLibrarySession.selectedItem.definition,
                petDisplayName: petLibrarySession.selectedItem.metadata.displayName
            )
                .tabItem {
                    Label("이동", systemImage: "location")
                }

            BehaviorSequencesSettingsView(
                settingsSession: settingsSession,
                petDefinition: petLibrarySession.selectedItem.definition,
                petDisplayName: petLibrarySession.selectedItem.metadata.displayName
            )
                .tabItem {
                    Label("행동 루틴", systemImage: "list.bullet.rectangle")
                }

            AutomaticRulesSettingsView(
                settingsSession: settingsSession,
                petDisplayName: petLibrarySession.selectedItem.metadata.displayName
            )
                .tabItem {
                    Label("자동 규칙", systemImage: "bolt.badge.clock")
                }
        }
        .frame(minWidth: 680, minHeight: 540)
        .accessibilityIdentifier("monglepet.settings.root")
    }
}

private struct GeneralSettingsView: View {
    @ObservedObject var settingsSession: AppSettingsSession
    @ObservedObject var petLibrarySession: PetLibrarySession
    @State private var isConfirmingRemoval = false
    @State private var isConfirmingAnimationRemoval = false
    @State private var isEditingPetDetails = false
    @State private var isCreatingEditableCopy = false
    @State private var userPetEditorMode: UserPetEditorMode?
    @State private var editingAnimation: PetMotion?
    @State private var previewMotionID: String?
    @State private var shareReview: PetPackageShareReview?
    @State private var pendingSharingFollowUp: PetSharingFollowUp?
    @State private var petPackageExportDocument: MonglePetPackageDocument?
    @State private var petPackageExportFileName = "MonglePet.monglepet"
    @State private var isPresentingPetPackageExporter = false
    @State private var petPackageExportErrorMessage: String?
    @State private var exportedPackageFileName: String?

    var body: some View {
        Form {
            if let loadNotice = settingsSession.loadNotice {
                noticeLabel(loadNotice, systemImage: "exclamationmark.triangle.fill")
            }
            if let saveErrorMessage = settingsSession.saveErrorMessage {
                noticeLabel(saveErrorMessage, systemImage: "xmark.circle.fill")
            }
            if let libraryErrorMessage = petLibrarySession.errorMessage {
                noticeLabel(libraryErrorMessage, systemImage: "xmark.circle.fill")
            }
            if let petPackageExportErrorMessage {
                noticeLabel(
                    petPackageExportErrorMessage,
                    systemImage: "xmark.circle.fill"
                )
            }

            Section("펫 라이브러리") {
                Picker("현재 펫", selection: petSelectionBinding) {
                    ForEach(petLibrarySession.items) { item in
                        Text(item.metadata.displayName)
                            .tag(item.selection)
                    }
                }
                .accessibilityIdentifier("monglepet.settings.petSelection")

                HStack(alignment: .top, spacing: 16) {
                    PetAnimationPreviewView(
                        item: petLibrarySession.selectedItem,
                        motionID: effectivePreviewMotionID
                    )
                    .frame(width: 176, height: 176)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("현재 펫 애니메이션 미리보기")

                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent(
                            "버전",
                            value: petLibrarySession.selectedItem.metadata.version
                        )
                        LabeledContent(
                            "제작자",
                            value: petLibrarySession.selectedItem.metadata.author
                        )
                        LabeledContent(
                            "라이선스",
                            value: petLibrarySession.selectedItem.metadata.license
                        )
                        if let description = petLibrarySession.selectedItem.metadata.description {
                            LabeledContent("설명", value: description)
                        }

                        Text("등록된 애니메이션")
                            .font(.headline)

                        List(selection: $previewMotionID) {
                            ForEach(petLibrarySession.selectedItem.definition.motions) { motion in
                                HStack {
                                    Text(motion.id)
                                    Spacer()
                                    if motion.id
                                        == petLibrarySession.selectedItem.definition.defaultMotionID {
                                        Text("기본")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .tag(motion.id)
                            }
                        }
                        .frame(minHeight: 96, maxHeight: 132)
                        .accessibilityIdentifier("monglepet.settings.petAnimations")

                        if let motion = selectedPreviewMotion {
                            Text(motionSummary(motion))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                                .accessibilityIdentifier(
                                    "monglepet.settings.petAnimationSummary"
                                )
                        }

                        if petLibrarySession.selectedItem.isEditable,
                           let motion = selectedPreviewMotion {
                            HStack {
                                Button("애니메이션 수정…") {
                                    editingAnimation = motion
                                }
                                .disabled(petLibrarySession.isImporting)
                                .accessibilityIdentifier(
                                    "monglepet.settings.editPetAnimation"
                                )

                                Button("애니메이션 삭제…", role: .destructive) {
                                    isConfirmingAnimationRemoval = true
                                }
                                .disabled(
                                    !canDeleteSelectedAnimation
                                        || petLibrarySession.isImporting
                                )
                                .help(animationDeletionHelp)
                                .accessibilityIdentifier(
                                    "monglepet.settings.removePetAnimation"
                                )
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                HStack {
                    Button("PNG로 새 펫 만들기…") {
                        userPetEditorMode = .create
                    }
                    .disabled(petLibrarySession.isImporting)
                    .accessibilityIdentifier("monglepet.settings.createUserPet")

                    if petLibrarySession.selectedItem.isEditable {
                        Button("펫 정보 수정…") {
                            isEditingPetDetails = true
                        }
                        .disabled(petLibrarySession.isImporting)
                        .accessibilityIdentifier("monglepet.settings.editPetDetails")

                        Button("펫 애니메이션 추가…") {
                            userPetEditorMode = .addAnimation
                        }
                        .disabled(petLibrarySession.isImporting)
                        .accessibilityIdentifier("monglepet.settings.addPetAnimation")
                    } else if !petLibrarySession.selectedItem.isBuiltIn {
                        Button("편집 가능한 사본 만들기…") {
                            isCreatingEditableCopy = true
                        }
                        .disabled(petLibrarySession.isImporting)
                        .accessibilityIdentifier(
                            "monglepet.settings.createEditablePetCopy"
                        )
                    }
                }

                HStack {
                    Button("MonglePet 패키지 가져오기…") {
                        choosePetPackage()
                    }
                    .disabled(isPetLibraryBusy)
                    .accessibilityIdentifier("monglepet.settings.importPackage")

                    if !petLibrarySession.selectedItem.isBuiltIn {
                        Button("선택한 펫 내보내기…") {
                            shareReview = petLibrarySession
                                .reviewSelectedPetForSharing(
                                    behaviorProfile:
                                        settingsSession.settings
                                            .activeBehaviorProfile
                                )
                        }
                        .disabled(isPetLibraryBusy)
                        .accessibilityIdentifier("monglepet.settings.exportPackage")

                        Button("선택한 펫 삭제…", role: .destructive) {
                            isConfirmingRemoval = true
                        }
                        .disabled(isPetLibraryBusy)
                        .accessibilityIdentifier("monglepet.settings.removePet")
                    }
                }

                Text(
                    petLibrarySession.selectedItem.isBuiltIn
                        ? "내장 몽글이는 삭제할 수 없으며 언제든 다시 선택할 수 있습니다."
                        : petLibrarySession.selectedItem.isEditable
                            ? "PNG 한 장은 정지 애니메이션, 여러 장은 지정한 순서대로 재생됩니다."
                            : "가져온 패키지는 직접 바꾸지 않습니다. 새 ID의 편집 가능한 사본을 만들어 수정할 수 있습니다."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("펫 표시") {
                Toggle("펫 깨우기", isOn: awakeBinding)
                    .accessibilityIdentifier("monglepet.settings.awake")

                Text("재워도 메뉴 막대에서 언제든 다시 깨울 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("행동 모드") {
                Picker("행동 모드", selection: behaviorModeBinding) {
                    Text("자동").tag(BehaviorMode.automatic.rawValue)
                    Text("수동").tag(BehaviorMode.manual.rawValue)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("monglepet.settings.behaviorMode")

                if settingsSession.settings.behaviorMode == .manual {
                    Picker("수동 행동 루틴", selection: manualSequenceBinding) {
                        ForEach(settingsSession.settings.sequences) { sequence in
                            Text(BuiltInBehaviorPresets.displayName(for: sequence.id))
                                .tag(sequence.id)
                        }
                    }
                    .accessibilityIdentifier("monglepet.settings.manualSequence")
                }

                Text(modeDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .disabled(!settingsSession.isWritingEnabled)

            Section("화면 표시") {
                HStack {
                    Text("펫 크기")
                    Slider(
                        value: overlayWidthBinding,
                        in: AppSettingsLimits.minimumOverlayWidth
                            ... AppSettingsLimits.maximumOverlayWidth,
                        step: 8,
                        onEditingChanged: { isEditing in
                            if !isEditing {
                                settingsSession.persistCurrentSettings()
                            }
                        }
                    )
                    .accessibilityIdentifier("monglepet.settings.overlayWidth")
                    Text("\(Int(settingsSession.settings.overlay.width)) pt")
                        .monospacedDigit()
                        .frame(width: 52, alignment: .trailing)
                }

                Toggle("클릭 통과", isOn: clickThroughBinding)
                    .accessibilityIdentifier("monglepet.settings.clickThrough")

                Text(
                    settingsSession.settings.overlay.clickThrough
                        ? "펫을 직접 드래그할 수 없습니다. 이 설정창에서 클릭 통과를 끌 수 있습니다."
                        : "켜면 펫 아래의 앱을 바로 클릭할 수 있습니다."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .disabled(!settingsSession.isWritingEnabled)
        }
        .formStyle(.grouped)
        .sheet(item: duplicateInstallRequestBinding) { request in
            DuplicatePetInstallView(
                request: request,
                petLibrarySession: petLibrarySession
            )
        }
        .alert("선택한 펫을 삭제할까요?", isPresented: $isConfirmingRemoval) {
            Button("삭제", role: .destructive) {
                _ = petLibrarySession.removeSelectedInstallation()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text(
                "라이브러리의 패키지 파일과 이 펫의 행동 루틴·자동 규칙 설정을 "
                    + "함께 삭제하고 내장 몽글이로 전환합니다."
            )
        }
        .alert(
            "선택한 애니메이션을 삭제할까요?",
            isPresented: $isConfirmingAnimationRemoval
        ) {
            Button("삭제", role: .destructive) {
                removeSelectedAnimation()
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("이 애니메이션을 사용하던 행동 단계는 현재 펫의 기본 애니메이션으로 복구됩니다.")
        }
        .alert(
            "펫 내보내기 완료",
            isPresented: exportSuccessAlertBinding
        ) {
            Button("확인", role: .cancel) {}
        } message: {
            Text("\(exportedPackageFileName ?? "펫 패키지") 파일을 저장했습니다.")
        }
        .sheet(item: $userPetEditorMode) { mode in
            UserPetAnimationEditorView(
                mode: mode,
                petLibrarySession: petLibrarySession
            )
        }
        .sheet(isPresented: $isEditingPetDetails) {
            UserPetDetailsEditorView(
                item: petLibrarySession.selectedItem,
                petLibrarySession: petLibrarySession
            )
        }
        .sheet(isPresented: $isCreatingEditableCopy) {
            ReadOnlyPetCopyEditorView(
                item: petLibrarySession.selectedItem,
                petLibrarySession: petLibrarySession
            )
        }
        .sheet(item: $editingAnimation) { motion in
            UserPetAnimationDetailsEditorView(
                item: petLibrarySession.selectedItem,
                motion: motion,
                petLibrarySession: petLibrarySession,
                onSaved: { animationID in
                    previewMotionID = animationID
                }
            )
        }
        .sheet(
            item: $shareReview,
            onDismiss: performPendingSharingFollowUp
        ) { review in
            PetPackageShareReviewView(
                review: review,
                blockedActionTitle: blockedSharingActionTitle,
                onBlockedAction: {
                    pendingSharingFollowUp = petLibrarySession.selectedItem.isEditable
                        ? .editDetails
                        : .createEditableCopy
                },
                onExport: { options in
                    pendingSharingFollowUp = .export(review, options)
                }
            )
        }
        .fileExporter(
            isPresented: $isPresentingPetPackageExporter,
            document: petPackageExportDocument,
            contentType: MonglePetPackageDocument.contentType,
            defaultFilename: petPackageExportFileName,
            onCompletion: handlePetPackageExportResult
        )
        .onAppear(perform: synchronizePreviewMotion)
        .onChange(of: petLibrarySession.selection) {
            synchronizePreviewMotion()
        }
        .onChange(of: isPresentingPetPackageExporter) {
            if !isPresentingPetPackageExporter {
                petPackageExportDocument = nil
            }
        }
    }

    private var effectivePreviewMotionID: String {
        if let previewMotionID,
           petLibrarySession.selectedItem.definition.motion(id: previewMotionID) != nil {
            return previewMotionID
        }
        return petLibrarySession.selectedItem.definition.defaultMotion?.id ?? ""
    }

    private var selectedPreviewMotion: PetMotion? {
        petLibrarySession.selectedItem.definition.motion(id: effectivePreviewMotionID)
    }

    private var isPetLibraryBusy: Bool {
        petLibrarySession.isImporting || petLibrarySession.isExporting
    }

    private var blockedSharingActionTitle: String? {
        guard !petLibrarySession.selectedItem.isBuiltIn else {
            return nil
        }
        return petLibrarySession.selectedItem.isEditable
            ? "펫 정보 수정…"
            : "편집 가능한 사본 만들기…"
    }

    private var canDeleteSelectedAnimation: Bool {
        guard let motion = selectedPreviewMotion else {
            return false
        }
        return petLibrarySession.selectedItem.definition.motions.count > 1
            && motion.id != petLibrarySession.selectedItem.definition.defaultMotionID
    }

    private var animationDeletionHelp: String {
        guard petLibrarySession.selectedItem.definition.motions.count > 1 else {
            return "마지막 남은 애니메이션은 삭제할 수 없습니다."
        }
        guard selectedPreviewMotion?.id
                != petLibrarySession.selectedItem.definition.defaultMotionID else {
            return "기본 애니메이션은 펫 정보 수정에서 다른 기본값을 선택한 뒤 삭제할 수 있습니다."
        }
        return "선택한 애니메이션을 삭제합니다."
    }

    private func synchronizePreviewMotion() {
        previewMotionID = petLibrarySession.selectedItem.definition.defaultMotion?.id
    }

    private func removeSelectedAnimation() {
        guard let motionID = selectedPreviewMotion?.id else {
            return
        }
        if petLibrarySession.removeSelectedPetAnimation(id: motionID) {
            synchronizePreviewMotion()
        }
    }

    private func motionSummary(_ motion: PetMotion) -> String {
        let duration = motion.frames.reduce(Int64.zero) {
            $0 + durationMilliseconds($1.duration)
        }
        let playback = motion.loops ? "반복" : "1회"
        return "\(motion.frames.count)프레임 · \(duration)ms · \(playback)"
    }

    private func durationMilliseconds(_ duration: Duration) -> Int64 {
        let components = duration.components
        return components.seconds * 1_000
            + components.attoseconds / 1_000_000_000_000_000
    }

    private var awakeBinding: Binding<Bool> {
        Binding(
            get: { settingsSession.settings.lastUserPresentation == .awake },
            set: {
                settingsSession.setUserPresentation($0 ? .awake : .tuckedAway)
            }
        )
    }

    private var petSelectionBinding: Binding<PetLibrarySelection> {
        Binding(
            get: { petLibrarySession.selection },
            set: { _ = petLibrarySession.select($0) }
        )
    }

    private var behaviorModeBinding: Binding<String> {
        Binding(
            get: { settingsSession.settings.behaviorMode.rawValue },
            set: { rawValue in
                guard let mode = BehaviorMode(rawValue: rawValue) else {
                    return
                }
                settingsSession.setBehaviorMode(mode)
            }
        )
    }

    private var overlayWidthBinding: Binding<Double> {
        Binding(
            get: { settingsSession.settings.overlay.width },
            set: { settingsSession.setOverlayWidth($0, persist: false) }
        )
    }

    private var manualSequenceBinding: Binding<String> {
        Binding(
            get: {
                settingsSession.settings.manualSequenceID
                    ?? settingsSession.settings.sequences.first?.id
                    ?? ""
            },
            set: { settingsSession.setManualSequenceID($0) }
        )
    }

    private var clickThroughBinding: Binding<Bool> {
        Binding(
            get: { settingsSession.settings.overlay.clickThrough },
            set: { settingsSession.setClickThrough($0) }
        )
    }

    private var modeDescription: String {
        switch settingsSession.settings.behaviorMode {
        case .automatic:
            "활성화된 자동 규칙 중 우선순위가 가장 높은 행동을 재생합니다."
        case .manual:
            "선택한 행동 루틴의 펫 애니메이션을 순서대로 재생합니다."
        }
    }

    private var duplicateInstallRequestBinding: Binding<DuplicatePetInstallRequest?> {
        Binding(
            get: { petLibrarySession.duplicateInstallRequest },
            set: { request in
                if request == nil {
                    petLibrarySession.cancelDuplicateInstallation()
                }
            }
        )
    }

    private var exportSuccessAlertBinding: Binding<Bool> {
        Binding(
            get: { exportedPackageFileName != nil },
            set: { isPresented in
                if !isPresented {
                    exportedPackageFileName = nil
                }
            }
        )
    }

    private func choosePetPackage() {
        let panel = NSOpenPanel()
        panel.title = "MonglePet 패키지 가져오기"
        panel.prompt = "가져오기"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        if let packageType = UTType(filenameExtension: "monglepet") {
            panel.allowedContentTypes = [packageType]
        }

        guard panel.runModal() == .OK, let sourceURL = panel.url else {
            return
        }
        _ = petLibrarySession.installPackage(from: sourceURL)
    }

    private func preparePetPackageExport(
        for review: PetPackageShareReview,
        options: PetPackageShareOptions
    ) {
        let workspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "MonglePetShareUI-\(UUID().uuidString)",
                isDirectory: true
            )
        let archiveURL = workspaceURL.appendingPathComponent(
            review.suggestedFileName,
            isDirectory: false
        )

        do {
            try FileManager.default.createDirectory(
                at: workspaceURL,
                withIntermediateDirectories: false
            )
        } catch {
            petPackageExportErrorMessage = "펫 공유 파일을 준비하지 못했습니다."
            return
        }
        defer { try? FileManager.default.removeItem(at: workspaceURL) }

        guard petLibrarySession.exportSelectedPet(
            reviewed: review,
            options: options,
            isConfirmed: true,
            to: archiveURL
        ) else {
            return
        }

        do {
            petPackageExportDocument = MonglePetPackageDocument(
                data: try Data(contentsOf: archiveURL)
            )
            petPackageExportFileName = review.suggestedFileName
            petPackageExportErrorMessage = nil
            isPresentingPetPackageExporter = true
        } catch {
            petPackageExportDocument = nil
            petPackageExportErrorMessage = "펫 공유 파일을 준비하지 못했습니다."
        }
    }

    private func handlePetPackageExportResult(
        _ result: Result<URL, Error>
    ) {
        switch result {
        case let .success(destinationURL):
            petPackageExportErrorMessage = nil
            exportedPackageFileName = destinationURL.lastPathComponent
        case let .failure(error):
            if (error as? CocoaError)?.code != .userCancelled {
                petPackageExportErrorMessage = error.localizedDescription
            }
        }
    }

    private func performPendingSharingFollowUp() {
        guard let followUp = pendingSharingFollowUp else {
            return
        }
        pendingSharingFollowUp = nil

        switch followUp {
        case let .export(review, options):
            preparePetPackageExport(for: review, options: options)
        case .editDetails:
            isEditingPetDetails = true
        case .createEditableCopy:
            isCreatingEditableCopy = true
        }
    }

    @ViewBuilder
    private func noticeLabel(_ message: String, systemImage: String) -> some View {
        Label(message, systemImage: systemImage)
            .foregroundStyle(.orange)
            .font(.callout)
            .accessibilityIdentifier("monglepet.settings.notice")
    }
}

nonisolated struct MonglePetPackageDocument: FileDocument {
    static let contentType = UTType(
        filenameExtension: "monglepet",
        conformingTo: .zip
    ) ?? .zip

    static var readableContentTypes: [UTType] {
        [contentType]
    }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private enum PetSharingFollowUp {
    case export(PetPackageShareReview, PetPackageShareOptions)
    case editDetails
    case createEditableCopy
}

private struct DuplicatePetInstallView: View {
    @Environment(\.dismiss) private var dismiss

    let request: DuplicatePetInstallRequest
    @ObservedObject var petLibrarySession: PetLibrarySession

    @State private var selectedInstallationID: UUID?

    init(
        request: DuplicatePetInstallRequest,
        petLibrarySession: PetLibrarySession
    ) {
        self.request = request
        self.petLibrarySession = petLibrarySession
        _selectedInstallationID = State(
            initialValue: request.preferredReplacementInstallationID
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("같은 펫 패키지가 이미 있습니다")
                    .font(.title2.weight(.semibold))
                Text("새 설치로 추가하거나, 아래 설치 중 하나를 선택해 교체할 수 있습니다.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("가져올 펫")
                    .font(.headline)
                packageInformation(request.incomingMetadata)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("교체할 기존 설치")
                    .font(.headline)

                if request.candidates.isEmpty {
                    Label(
                        "기존 설치 정보를 다시 불러오지 못했습니다. 취소 후 다시 시도해 주세요.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(request.candidates) { candidate in
                                Button {
                                    selectedInstallationID = candidate.installationID
                                } label: {
                                    candidateRow(candidate)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier(
                                    "monglepet.import.candidate.\(candidate.installationID.uuidString)"
                                )

                                if candidate.id != request.candidates.last?.id {
                                    Divider()
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                    .background(
                        .quaternary.opacity(0.35),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Label(
                    "새 설치는 새 설치 ID와 독립된 행동 루틴·자동 규칙을 사용하며 읽기 전용으로 등록됩니다.",
                    systemImage: "plus.square.on.square"
                )
                Label(
                    replacementDescription,
                    systemImage: selectedCandidate?.isEditable == true
                        ? "exclamationmark.triangle.fill"
                        : "arrow.triangle.2.circlepath"
                )
                .foregroundStyle(
                    selectedCandidate?.isEditable == true ? Color.orange : Color.secondary
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if let errorMessage = petLibrarySession.errorMessage {
                Label(errorMessage, systemImage: "xmark.circle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
                    .accessibilityIdentifier("monglepet.import.error")
            }

            HStack {
                Spacer()
                Button("취소", role: .cancel) {
                    petLibrarySession.cancelDuplicateInstallation()
                    dismiss()
                }
                Button("새 설치로 추가") {
                    petLibrarySession.installDuplicateSeparately()
                }
                .disabled(petLibrarySession.isImporting)
                .accessibilityIdentifier("monglepet.import.installSeparately")
                Button("선택 항목 교체", role: .destructive) {
                    guard let selectedInstallationID else {
                        return
                    }
                    petLibrarySession.replaceDuplicateInstallation(
                        selectedInstallationID
                    )
                }
                .disabled(
                    selectedInstallationID == nil || petLibrarySession.isImporting
                )
                .accessibilityIdentifier("monglepet.import.replaceSelected")
            }
        }
        .padding(20)
        .frame(width: 560)
        .accessibilityIdentifier("monglepet.import.duplicateReview")
    }

    private var selectedCandidate: DuplicatePetInstallationCandidate? {
        request.candidates.first {
            $0.installationID == selectedInstallationID
        }
    }

    private var replacementDescription: String {
        if selectedCandidate?.isEditable == true {
            return "교체하면 선택한 펫 파일과 편집 가능 상태가 읽기 전용 패키지로 바뀝니다. 기존 행동 루틴·자동 규칙은 유지됩니다."
        }
        return "교체하면 선택한 설치 ID의 펫 파일만 바뀌고 기존 행동 루틴·자동 규칙은 유지됩니다."
    }

    @ViewBuilder
    private func packageInformation(_ metadata: PetPackageMetadata) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
            importInformationRow("펫 이름", value: metadata.displayName)
            importInformationRow("버전", value: metadata.version)
            importInformationRow("제작자", value: metadata.author)
            importInformationRow("패키지 ID", value: metadata.id)
        }
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder
    private func candidateRow(
        _ candidate: DuplicatePetInstallationCandidate
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(
                systemName: candidate.installationID == selectedInstallationID
                    ? "largecircle.fill.circle"
                    : "circle"
            )
            .foregroundStyle(
                candidate.installationID == selectedInstallationID
                    ? Color.accentColor
                    : Color.secondary
            )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(candidate.metadata.displayName)
                        .fontWeight(.medium)
                    if candidate.isCurrentlySelected {
                        Text("현재 선택")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(candidate.isEditable ? "편집 가능" : "읽기 전용")
                        .font(.caption2)
                        .foregroundStyle(
                            candidate.isEditable ? Color.blue : Color.secondary
                        )
                }
                Text("버전 \(candidate.metadata.version) · 제작자 \(candidate.metadata.author)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text("설치 ID \(candidate.installationID.uuidString)")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
        }
        .contentShape(Rectangle())
        .padding(12)
    }

    private func importInformationRow(
        _ label: String,
        value: String
    ) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }
}

private struct PetPackageShareReviewView: View {
    @Environment(\.dismiss) private var dismiss

    let review: PetPackageShareReview
    let blockedActionTitle: String?
    let onBlockedAction: () -> Void
    let onExport: (PetPackageShareOptions) -> Void

    @State private var isSharingRightsConfirmed = false
    @State private var includesRecommendedProfile = false
    @State private var includesApplicationRules = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("공유 내용 확인")
                            .font(.title2.weight(.semibold))
                        Text("저장할 `.monglepet` 파일에 포함할 내용을 선택합니다.")
                            .foregroundStyle(.secondary)
                    }

                    Grid(
                        alignment: .leading,
                        horizontalSpacing: 20,
                        verticalSpacing: 10
                    ) {
                        shareInformationRow("펫 이름", value: review.displayName)
                        shareInformationRow("버전", value: review.version)
                        shareInformationRow("제작자", value: review.author)
                        shareInformationRow("라이선스", value: review.license)
                    }
                    .padding(12)
                    .background(
                        .quaternary.opacity(0.35),
                        in: RoundedRectangle(cornerRadius: 10)
                    )

                    if let blockingReason = review.blockingReason {
                        blockedContent(reason: blockingReason)
                    } else {
                        sharedContentOptions

                        Toggle(
                            "이 펫과 이미지 자산을 다른 사용자에게 공유할 권한이 있음을 확인합니다.",
                            isOn: $isSharingRightsConfirmed
                        )
                        .accessibilityIdentifier(
                            "monglepet.share.rightsConfirmation"
                        )
                    }

                    Text(
                        "MonglePet은 입력된 라이선스의 법적 유효성이나 실제 공유 권한을 보증하지 않습니다."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(20)
            }

            Divider()
            HStack {
                Spacer()
                Button("취소", role: .cancel) {
                    dismiss()
                }

                if review.canExport {
                    Button("저장 위치 선택…") {
                        onExport(
                            PetPackageShareOptions(
                                includesRecommendedProfile:
                                    includesRecommendedProfile,
                                includesApplicationRules:
                                    includesApplicationRules
                            )
                        )
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isSharingRightsConfirmed)
                    .accessibilityIdentifier("monglepet.share.chooseDestination")
                } else if let blockedActionTitle {
                    Button(blockedActionTitle) {
                        onBlockedAction()
                        dismiss()
                    }
                    .accessibilityIdentifier("monglepet.share.resolveBlock")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(width: 560)
        .frame(minHeight: 480, maxHeight: 680)
        .onChange(of: includesRecommendedProfile) {
            if !includesRecommendedProfile {
                includesApplicationRules = false
            }
        }
        .accessibilityIdentifier("monglepet.share.review")
    }

    @ViewBuilder
    private func blockedContent(
        reason: PetPackageSharingBlockReason
    ) -> some View {
        Label(reason.message, systemImage: "exclamationmark.triangle.fill")
            .foregroundStyle(.orange)
            .accessibilityIdentifier("monglepet.share.blockedReason")

        Text(
            "편집 가능한 펫은 라이선스 정보를 수정할 수 있습니다. "
                + "가져온 읽기 전용 펫은 먼저 편집 가능한 사본을 만들어 주세요."
        )
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var sharedContentOptions: some View {
        GroupBox("내보낼 내용") {
            VStack(alignment: .leading, spacing: 12) {
                Label(
                    "펫 정보, 미리보기와 등록된 애니메이션",
                    systemImage: "photo.on.rectangle.angled"
                )

                Divider()

                Toggle(
                    "펫별 행동·이동 권장 설정 포함",
                    isOn: $includesRecommendedProfile
                )
                .disabled(review.recommendedProfile == nil)
                .accessibilityIdentifier(
                    "monglepet.share.includeRecommendedProfile"
                )

                if let issue = review.recommendedProfileIssue {
                    Label(
                        "현재 설정은 포함할 수 없습니다: \(issue)",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                } else if review.recommendedProfile == nil {
                    Text("현재 펫에 공유할 행동·이동 권장 설정이 없습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if includesRecommendedProfile {
                    recommendedProfileSummary
                    applicationRuleOptions
                } else {
                    Text("선택하지 않으면 기존과 같이 펫과 애니메이션만 저장합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var recommendedProfileSummary: some View {
        if let profile = review.recommendedProfile {
            Grid(
                alignment: .leading,
                horizontalSpacing: 16,
                verticalSpacing: 6
            ) {
                shareInformationRow(
                    "행동 모드",
                    value: profile.mode == .automatic ? "자동" : "수동"
                )
                shareInformationRow(
                    "행동 루틴",
                    value: "\(profile.sequences.count)개"
                )
                shareInformationRow(
                    "유휴 자동 규칙",
                    value: "\(profile.automaticRules.count)개"
                )
                shareInformationRow(
                    "이동 방식",
                    value: movementModeName(profile.movement.mode)
                )
                shareInformationRow(
                    "쓰다듬기",
                    value: profile.pettingMotionID ?? "지정 안 함"
                )
            }
            .padding(.leading, 24)
            .font(.caption)
        }
    }

    @ViewBuilder
    private var applicationRuleOptions: some View {
        if review.applicationRuleCount > 0 {
            Divider()

            Toggle(
                "앱별 자동 규칙 \(review.applicationRuleCount)개 포함",
                isOn: $includesApplicationRules
            )
            .disabled(review.recommendedProfileWithApplicationRules == nil)
            .accessibilityIdentifier(
                "monglepet.share.includeApplicationRules"
            )

            if let issue = review.applicationRulesIssue {
                Label(
                    "앱별 자동 규칙은 포함할 수 없습니다: \(issue)",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            } else {
                Text(
                    includesApplicationRules
                        ? "포함할 앱 식별자: "
                            + review.applicationBundleIdentifiers.joined(
                                separator: ", "
                            )
                        : "앱별 자동 규칙은 기본적으로 포함하지 않습니다."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
        }
    }

    private func movementModeName(_ mode: PetMovementMode) -> String {
        switch mode {
        case .fixed:
            "위치 고정"
        case .cursorFollowing:
            "마우스 따라가기"
        case .freeRoaming:
            "자유 이동"
        }
    }

    private func shareInformationRow(
        _ label: String,
        value: String
    ) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .textSelection(.enabled)
        }
    }
}

private enum UserPetEditorMode: String, Identifiable {
    case create
    case addAnimation

    var id: String { rawValue }
}

private struct UserPetAnimationEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let mode: UserPetEditorMode
    @ObservedObject var petLibrarySession: PetLibrarySession

    @State private var petName = ""
    @State private var version = "1.0.0"
    @State private var author = "MonglePet 사용자"
    @State private var license = "Private Use"
    @State private var petDescription = "MonglePet에서 사용자가 만든 펫입니다."
    @State private var animationName = ""
    @State private var frameDurationMilliseconds = 120
    @State private var loops = true
    @State private var frames: [UserPetAnimationFrameDraft] = []
    @State private var selectedFrameID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(mode == .create ? "PNG로 새 펫 만들기" : "펫 애니메이션 추가")
                .font(.title2.weight(.semibold))
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if mode == .create {
                        petInformationSection
                    }
                    animationInformationSection
                    frameEditorSection

                    Text("권장: 512×512 px 투명 PNG, 모든 프레임에 동일한 캔버스와 캐릭터 크기를 사용해 주세요. 크기가 다르면 투명 영역을 기준으로 자동 맞춤하며 선택 프레임의 배율과 위치를 조정할 수 있습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let errorMessage = petLibrarySession.errorMessage {
                        Label(errorMessage, systemImage: "xmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(20)
            }

            Divider()

            HStack {
                Spacer()
                Button("취소", role: .cancel) {
                    dismiss()
                }
                Button(mode == .create ? "펫 만들기" : "추가") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave || petLibrarySession.isImporting)
                .accessibilityIdentifier("monglepet.userPet.save")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 760, idealWidth: 820, minHeight: 560, idealHeight: 680)
        .onAppear {
            if mode == .create {
                animationName = "기본"
            }
        }
    }

    private var petInformationSection: some View {
        GroupBox("펫 정보") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    fieldLabel("펫 이름")
                    TextField("펫 이름", text: $petName)
                        .accessibilityIdentifier("monglepet.userPet.petName")
                }

                GridRow {
                    fieldLabel("제작자")
                    TextField("제작자", text: $author)
                        .accessibilityIdentifier("monglepet.userPet.author")
                }

                GridRow {
                    fieldLabel("버전")
                    TextField("버전", text: $version)
                        .accessibilityIdentifier("monglepet.userPet.version")
                }

                GridRow {
                    fieldLabel("라이선스")
                    TextField("라이선스", text: $license)
                        .accessibilityIdentifier("monglepet.userPet.license")
                }

                GridRow {
                    fieldLabel("설명")
                    TextField("설명", text: $petDescription, axis: .vertical)
                        .lineLimit(2...4)
                        .accessibilityIdentifier("monglepet.userPet.description")
                }
            }
            .padding(8)
        }
    }

    private var animationInformationSection: some View {
        GroupBox("애니메이션 설정") {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    fieldLabel("이름")
                    TextField("애니메이션 이름", text: $animationName)
                        .accessibilityIdentifier("monglepet.userPet.animationName")
                }

                GridRow {
                    fieldLabel("새 PNG 간격")
                    HStack {
                        Stepper(
                            "\(frameDurationMilliseconds) ms",
                            value: $frameDurationMilliseconds,
                            in: 16...60_000,
                            step: 10
                        )
                        .accessibilityIdentifier("monglepet.userPet.frameDuration")

                        Text("앞으로 추가할 프레임의 기본값")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                GridRow {
                    fieldLabel("재생")
                    Toggle("반복 재생", isOn: $loops)
                        .accessibilityIdentifier("monglepet.userPet.loops")
                }
            }
            .padding(8)
        }
    }

    private var frameEditorSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("PNG 프레임")
                            .font(.headline)
                        Text("프레임을 선택하면 배율·위치·재생 간격을 개별 편집할 수 있습니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(frames.isEmpty ? "PNG 선택…" : "PNG 추가…") {
                        choosePNGs()
                    }
                    .accessibilityIdentifier("monglepet.userPet.choosePNGs")
                }

                if frames.isEmpty {
                    ContentUnavailableView(
                        "선택한 PNG가 없습니다.",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("한 장 또는 여러 장의 PNG를 선택해 주세요.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                } else {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            EditableAnimationPreviewPanel(
                                frames: frames,
                                loops: loops,
                                selectedFrameID: selectedFrameID
                            )

                            if let selectedFrameBinding {
                                FramePlacementControls(frame: selectedFrameBinding)
                            }
                        }
                        .frame(width: 230)

                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("프레임 순서와 간격")
                                .font(.subheadline.weight(.semibold))

                            List(selection: $selectedFrameID) {
                                ForEach(Array(frames.enumerated()), id: \.element.id) { index, frame in
                                    frameRow(frame, at: index)
                                        .tag(frame.id)
                                }
                            }
                            .frame(minHeight: 320)
                            .accessibilityIdentifier("monglepet.userPet.frames")
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(8)
        }
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title)
            .foregroundStyle(.secondary)
            .frame(width: 88, alignment: .trailing)
    }

    private func frameRow(
        _ frame: UserPetAnimationFrameDraft,
        at index: Int
    ) -> some View {
        HStack(spacing: 8) {
            frameThumbnail(frame)
                .frame(width: 38, height: 38)

            Text("\(index + 1)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)

            Text(frameFilename(frame))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField(
                "간격",
                value: durationBinding(for: frame.id),
                format: .number
            )
            .frame(width: 66)
            .multilineTextAlignment(.trailing)
            .accessibilityLabel("\(index + 1)번 프레임 간격")

            Text("ms")
                .foregroundStyle(.secondary)

            Button {
                moveFrame(at: index, offset: -1)
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(index == frames.startIndex)
            .accessibilityLabel("위로 이동")

            Button {
                moveFrame(at: index, offset: 1)
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(index == frames.index(before: frames.endIndex))
            .accessibilityLabel("아래로 이동")

            Button(role: .destructive) {
                removeFrame(id: frame.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("프레임 삭제")
        }
    }

    private var canSave: Bool {
        !animationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !frames.isEmpty
            && frames.allSatisfy { 16...60_000 ~= $0.durationMilliseconds }
            && (mode != .create
                || (!petName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !license.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
    }

    private func choosePNGs() {
        let panel = NSOpenPanel()
        panel.title = "PNG 프레임 선택"
        panel.prompt = "추가"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true
        panel.allowedContentTypes = [.png]

        guard panel.runModal() == .OK else {
            return
        }
        let addedFrames = UserPetAnimationDraftFactory.new(
            urls: panel.urls,
            durationMilliseconds: frameDurationMilliseconds,
            reference: frames.first
        )
        frames.append(contentsOf: addedFrames)
        selectedFrameID = addedFrames.first?.id ?? selectedFrameID
    }

    private func moveFrame(at index: Int, offset: Int) {
        let destination = index + offset
        guard frames.indices.contains(index), frames.indices.contains(destination) else {
            return
        }
        frames.swapAt(index, destination)
    }

    private func removeFrame(id: UUID) {
        frames.removeAll { $0.id == id }
        if selectedFrameID == id {
            selectedFrameID = frames.first?.id
        }
    }

    private func durationBinding(for id: UUID) -> Binding<Int> {
        Binding(
            get: {
                frames.first(where: { $0.id == id })?.durationMilliseconds ?? 120
            },
            set: { newValue in
                guard let index = frames.firstIndex(where: { $0.id == id }) else {
                    return
                }
                frames[index].durationMilliseconds = newValue
            }
        )
    }

    private func save() {
        let succeeded: Bool
        switch mode {
        case .create:
            succeeded = petLibrarySession.createUserPet(
                UserPetCreationRequest(
                    displayName: petName,
                    animationName: animationName,
                    loops: loops,
                    frames: sourceFrameRequests,
                    version: version,
                    author: author,
                    license: license,
                    description: petDescription
                )
            )
        case .addAnimation:
            succeeded = petLibrarySession.addAnimationToSelectedPet(
                UserPetAnimationRequest(
                    animationName: animationName,
                    loops: loops,
                    frames: sourceFrameRequests
                )
            )
        }
        if succeeded {
            dismiss()
        }
    }

    private var sourceFrameRequests: [UserPetSourceFrameRequest] {
        frames.compactMap { frame in
            guard case let .png(url) = frame.source else {
                return nil
            }
            return UserPetSourceFrameRequest(
                sourceURL: url,
                durationMilliseconds: frame.durationMilliseconds,
                placement: frame.placement
            )
        }
    }

    private var selectedFrameBinding: Binding<UserPetAnimationFrameDraft>? {
        guard let selectedFrameID,
              frames.contains(where: { $0.id == selectedFrameID }) else {
            return nil
        }
        return Binding(
            get: { frames.first(where: { $0.id == selectedFrameID })! },
            set: { updated in
                guard let index = frames.firstIndex(where: { $0.id == selectedFrameID }) else {
                    return
                }
                frames[index] = updated
            }
        )
    }

    @ViewBuilder
    private func frameThumbnail(_ frame: UserPetAnimationFrameDraft) -> some View {
        if let image = frame.previewImage {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
        }
    }

    private func frameFilename(_ frame: UserPetAnimationFrameDraft) -> String {
        guard case let .png(url) = frame.source else {
            return "기존 프레임"
        }
        return url.lastPathComponent
    }
}

private struct ReadOnlyPetCopyEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let item: PetLibraryItem
    @ObservedObject var petLibrarySession: PetLibrarySession

    @State private var displayName: String

    init(item: PetLibraryItem, petLibrarySession: PetLibrarySession) {
        self.item = item
        self.petLibrarySession = petLibrarySession
        _displayName = State(initialValue: "\(item.metadata.displayName) 사본")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("편집 가능한 사본 만들기")
                .font(.title2.weight(.semibold))

            Text("가져온 원본은 읽기 전용으로 그대로 보존됩니다. 사본은 독립된 사용자 펫으로 설치되어 정보와 애니메이션을 수정할 수 있습니다.")
                .foregroundStyle(.secondary)

            Form {
                TextField("사본 이름", text: $displayName)
                    .accessibilityIdentifier("monglepet.editableCopy.name")

                LabeledContent("원본 펫", value: item.metadata.displayName)
                LabeledContent("제작자", value: item.metadata.author)
                LabeledContent("버전", value: item.metadata.version)
                LabeledContent("라이선스", value: item.metadata.license)
                LabeledContent("원본 패키지 ID", value: item.metadata.id)
                    .textSelection(.enabled)
            }
            .formStyle(.grouped)

            Text("애니메이션과 미리보기 자산만 사본 패키지에 복사합니다. 현재 행동 루틴과 자동 규칙은 앱 설정에 그대로 유지됩니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let errorMessage = petLibrarySession.errorMessage {
                Label(errorMessage, systemImage: "xmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("취소", role: .cancel) {
                    dismiss()
                }
                Button("사본 만들기") {
                    createCopy()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate || petLibrarySession.isImporting)
                .accessibilityIdentifier("monglepet.editableCopy.create")
            }
        }
        .padding(20)
        .frame(minWidth: 540, minHeight: 420)
    }

    private var canCreate: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func createCopy() {
        if petLibrarySession.createEditableCopyOfSelectedPet(displayName: displayName) {
            dismiss()
        }
    }
}

private struct UserPetDetailsEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let item: PetLibraryItem
    @ObservedObject var petLibrarySession: PetLibrarySession

    @State private var displayName: String
    @State private var version: String
    @State private var author: String
    @State private var license: String
    @State private var petDescription: String
    @State private var defaultMotionID: String

    init(item: PetLibraryItem, petLibrarySession: PetLibrarySession) {
        self.item = item
        self.petLibrarySession = petLibrarySession
        _displayName = State(initialValue: item.metadata.displayName)
        _version = State(initialValue: item.metadata.version)
        _author = State(initialValue: item.metadata.author)
        _license = State(initialValue: item.metadata.license)
        _petDescription = State(initialValue: item.metadata.description ?? "")
        _defaultMotionID = State(initialValue: item.definition.defaultMotionID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("펫 정보 수정")
                .font(.title2.weight(.semibold))

            Form {
                LabeledContent("패키지 ID", value: item.metadata.id)
                    .textSelection(.enabled)

                TextField("펫 이름", text: $displayName)
                    .accessibilityIdentifier("monglepet.petDetails.name")

                TextField("제작자", text: $author)
                    .accessibilityIdentifier("monglepet.petDetails.author")

                TextField("버전", text: $version)
                    .accessibilityIdentifier("monglepet.petDetails.version")

                TextField("라이선스", text: $license)
                    .accessibilityIdentifier("monglepet.petDetails.license")

                TextField("설명", text: $petDescription, axis: .vertical)
                    .lineLimit(2...5)
                    .accessibilityIdentifier("monglepet.petDetails.description")

                Picker("기본 애니메이션", selection: $defaultMotionID) {
                    ForEach(item.definition.motions) { motion in
                        Text(motion.id).tag(motion.id)
                    }
                }
                .accessibilityIdentifier("monglepet.petDetails.defaultAnimation")
            }
            .formStyle(.grouped)

            Text("패키지 ID와 설치 항목은 유지됩니다. 저장 전 임시 사본을 전체 검증한 뒤 현재 펫을 교체합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let errorMessage = petLibrarySession.errorMessage {
                Label(errorMessage, systemImage: "xmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("취소", role: .cancel) {
                    dismiss()
                }
                Button("저장") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave || petLibrarySession.isImporting)
                .accessibilityIdentifier("monglepet.petDetails.save")
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 440)
    }

    private var canSave: Bool {
        !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !license.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && item.definition.motion(id: defaultMotionID) != nil
    }

    private func save() {
        let succeeded = petLibrarySession.updateSelectedPetDetails(
            UserPetDetailsRequest(
                displayName: displayName,
                version: version,
                author: author,
                license: license,
                description: petDescription,
                defaultMotionID: defaultMotionID
            )
        )
        if succeeded {
            dismiss()
        }
    }
}

private struct UserPetAnimationDetailsEditorView: View {
    @Environment(\.dismiss) private var dismiss
    let motion: PetMotion
    @ObservedObject var petLibrarySession: PetLibrarySession
    let onSaved: (String) -> Void

    @State private var animationName: String
    @State private var loops: Bool
    @State private var frames: [UserPetAnimationFrameDraft]
    @State private var selectedFrameID: UUID?

    init(
        item: PetLibraryItem,
        motion: PetMotion,
        petLibrarySession: PetLibrarySession,
        onSaved: @escaping (String) -> Void
    ) {
        self.motion = motion
        self.petLibrarySession = petLibrarySession
        self.onSaved = onSaved
        _animationName = State(initialValue: motion.id)
        _loops = State(initialValue: motion.loops)
        let frameDrafts = UserPetAnimationDraftFactory.existing(
            item: item,
            motion: motion
        )
        _frames = State(initialValue: frameDrafts)
        _selectedFrameID = State(initialValue: frameDrafts.first?.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("펫 애니메이션 수정")
                .font(.title2.weight(.semibold))

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Form {
                TextField("애니메이션 이름", text: $animationName)
                    .accessibilityIdentifier("monglepet.petAnimation.name")

                Toggle("반복 재생", isOn: $loops)
                    .accessibilityIdentifier("monglepet.petAnimation.loops")

                LabeledContent("프레임 수", value: "\(frames.count)")
            }
            .formStyle(.grouped)

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("편집 미리보기")
                        .font(.headline)
                    EditableAnimationPreviewPanel(
                        frames: frames,
                        loops: loops,
                        selectedFrameID: selectedFrameID
                    )
                        .frame(width: 220)
                        .accessibilityLabel("편집 중인 애니메이션 미리보기")

                    if let selectedFrameBinding {
                        FramePlacementControls(frame: selectedFrameBinding)
                    }

                    Button("PNG 프레임 추가…") {
                        choosePNGs()
                    }
                    .accessibilityIdentifier("monglepet.petAnimation.addFrames")
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("프레임 순서와 간격")
                        .font(.headline)

                    List {
                        ForEach(Array(frames.enumerated()), id: \.element.id) { index, frame in
                            HStack(spacing: 8) {
                                frameThumbnail(frame)
                                    .frame(width: 38, height: 38)

                                Text("\(index + 1)")
                                    .monospacedDigit()
                                    .frame(width: 24, alignment: .trailing)

                                TextField(
                                    "간격",
                                    value: durationBinding(for: frame.id),
                                    format: .number
                                )
                                .frame(width: 72)
                                .multilineTextAlignment(.trailing)
                                .accessibilityLabel("\(index + 1)번 프레임 간격")

                                Text("ms")
                                    .foregroundStyle(.secondary)

                                Spacer()

                                Button {
                                    moveFrame(at: index, offset: -1)
                                } label: {
                                    Image(systemName: "chevron.up")
                                }
                                .buttonStyle(.borderless)
                                .disabled(index == frames.startIndex)
                                .accessibilityLabel("위로 이동")

                                Button {
                                    moveFrame(at: index, offset: 1)
                                } label: {
                                    Image(systemName: "chevron.down")
                                }
                                .buttonStyle(.borderless)
                                .disabled(index == frames.index(before: frames.endIndex))
                                .accessibilityLabel("아래로 이동")

                                Button(role: .destructive) {
                                    removeFrame(id: frame.id)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                                .disabled(frames.count == 1)
                                .accessibilityLabel("프레임 삭제")
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedFrameID = frame.id
                            }
                            .background(
                                selectedFrameID == frame.id
                                    ? Color.accentColor.opacity(0.12)
                                    : Color.clear,
                                in: RoundedRectangle(cornerRadius: 6)
                            )
                        }
                    }
                    .frame(minHeight: 190)
                    .accessibilityIdentifier("monglepet.petAnimation.frames")
                }
                .frame(maxWidth: .infinity)
            }

            Text("권장: 512×512 px 투명 PNG, 모든 프레임에 동일한 캔버스와 캐릭터 크기를 사용해 주세요. 새 프레임은 투명 영역을 기준으로 자동 맞춤하며 선택 프레임의 배율과 위치를 조정할 수 있습니다. 각 프레임 간격은 16~60000ms입니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

                    if let errorMessage = petLibrarySession.errorMessage {
                        Label(errorMessage, systemImage: "xmark.circle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }
                }
            }

            HStack {
                Spacer()
                Button("취소", role: .cancel) {
                    dismiss()
                }
                Button("저장") {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave || petLibrarySession.isImporting)
                .accessibilityIdentifier("monglepet.petAnimation.save")
            }
        }
        .padding(20)
        .frame(minWidth: 720, idealWidth: 780, minHeight: 560, idealHeight: 680)
    }

    private var canSave: Bool {
        !animationName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !frames.isEmpty
            && frames.allSatisfy { 16...60_000 ~= $0.durationMilliseconds }
    }

    @ViewBuilder
    private func frameThumbnail(_ frame: UserPetAnimationFrameDraft) -> some View {
        if let image = frame.previewImage {
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
        }
    }

    private func durationBinding(for id: UUID) -> Binding<Int> {
        Binding(
            get: {
                frames.first(where: { $0.id == id })?.durationMilliseconds ?? 120
            },
            set: { newValue in
                guard let index = frames.firstIndex(where: { $0.id == id }) else {
                    return
                }
                frames[index].durationMilliseconds = newValue
            }
        )
    }

    private var selectedFrameBinding: Binding<UserPetAnimationFrameDraft>? {
        guard let selectedFrameID,
              frames.contains(where: { $0.id == selectedFrameID }) else {
            return nil
        }
        return Binding(
            get: {
                frames.first(where: { $0.id == selectedFrameID })!
            },
            set: { updated in
                guard let index = frames.firstIndex(where: { $0.id == selectedFrameID }) else {
                    return
                }
                frames[index] = updated
            }
        )
    }

    private func choosePNGs() {
        let panel = NSOpenPanel()
        panel.title = "추가할 PNG 프레임 선택"
        panel.prompt = "추가"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.resolvesAliases = true
        panel.allowedContentTypes = [.png]

        guard panel.runModal() == .OK else {
            return
        }
        let addedFrames = UserPetAnimationDraftFactory.new(
            urls: panel.urls,
            durationMilliseconds: 120,
            reference: frames.first
        )
        frames.append(contentsOf: addedFrames)
        selectedFrameID = addedFrames.first?.id ?? selectedFrameID
    }

    private func moveFrame(at index: Int, offset: Int) {
        let destination = index + offset
        guard frames.indices.contains(index), frames.indices.contains(destination) else {
            return
        }
        frames.swapAt(index, destination)
    }

    private func removeFrame(id: UUID) {
        guard frames.count > 1 else {
            return
        }
        frames.removeAll { $0.id == id }
        if selectedFrameID == id {
            selectedFrameID = frames.first?.id
        }
    }

    private func save() {
        let normalizedName = animationName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let succeeded = petLibrarySession.updateSelectedPetAnimation(
            UserPetAnimationDetailsRequest(
                animationID: motion.id,
                animationName: normalizedName,
                loops: loops,
                frames: frames.map {
                    UserPetAnimationFrameRequest(
                        source: $0.source,
                        durationMilliseconds: $0.durationMilliseconds,
                        placement: $0.placement
                    )
                }
            )
        )
        if succeeded {
            onSaved(normalizedName)
            dismiss()
        }
    }

}

private struct UserPetAnimationFrameDraft: Identifiable {
    let id = UUID()
    let source: UserPetAnimationFrameSource
    var durationMilliseconds: Int
    let content: TransparentFrameContent
    let canvasSize: PixelSize
    let baseScale: Double
    let anchorX: Double
    let anchorBottom: Double
    var scalePercent: Double = 100
    var offsetX: Double = 0
    var offsetY: Double = 0
    var previewImage: CGImage?

    init?(
        source: UserPetAnimationFrameSource,
        durationMilliseconds: Int,
        image: CGImage,
        canvasSize: PixelSize,
        baseScale: Double,
        anchorX: Double,
        anchorBottom: Double
    ) {
        guard let content = try? FrameCanvasComposer().transparentContent(in: image) else {
            return nil
        }
        self.source = source
        self.durationMilliseconds = durationMilliseconds
        self.content = content
        self.canvasSize = canvasSize
        self.baseScale = baseScale
        self.anchorX = anchorX
        self.anchorBottom = anchorBottom
        previewImage = nil
        refreshPreview()
    }

    var placement: FrameCanvasPlacement {
        let scale = baseScale * scalePercent / 100
        return FrameCanvasPlacement(
            canvasWidth: canvasSize.width,
            canvasHeight: canvasSize.height,
            scale: scale,
            x: anchorX - Double(content.image.width) * scale / 2 + offsetX,
            y: anchorBottom - Double(content.image.height) * scale + offsetY
        )
    }

    var renderedContentSize: CGSize {
        CGSize(
            width: Double(content.image.width) * placement.scale,
            height: Double(content.image.height) * placement.scale
        )
    }

    mutating func refreshPreview() {
        previewImage = try? FrameCanvasComposer().compose(
            content,
            placement: placement
        )
    }

    mutating func resetPlacement() {
        scalePercent = 100
        offsetX = 0
        offsetY = 0
        refreshPreview()
    }
}

@MainActor
private enum UserPetAnimationDraftFactory {
    static func existing(
        item: PetLibraryItem,
        motion: PetMotion
    ) -> [UserPetAnimationFrameDraft] {
        let atlases = (try? PetPresentationResourceLoader.loadAtlases(for: item)) ?? []
        let atlasImages = Dictionary(uniqueKeysWithValues: atlases.map { ($0.id, $0.image) })
        return motion.frames.enumerated().compactMap { index, frame in
            guard let image = atlasImages[frame.atlasID]?.cropping(
                to: CGRect(
                    x: frame.sourceRect.x,
                    y: frame.sourceRect.y,
                    width: frame.sourceRect.width,
                    height: frame.sourceRect.height
                )
            ), let content = try? FrameCanvasComposer().transparentContent(in: image) else {
                return nil
            }
            return UserPetAnimationFrameDraft(
                source: .existing(index: index),
                durationMilliseconds: durationMilliseconds(frame.duration),
                image: image,
                canvasSize: PixelSize(
                    width: frame.sourceRect.width,
                    height: frame.sourceRect.height
                ),
                baseScale: 1,
                anchorX: Double(content.sourceBounds.x)
                    + Double(content.sourceBounds.width) / 2,
                anchorBottom: Double(
                    content.sourceBounds.y + content.sourceBounds.height
                )
            )
        }
    }

    static func new(
        urls: [URL],
        durationMilliseconds: Int,
        reference: UserPetAnimationFrameDraft? = nil
    ) -> [UserPetAnimationFrameDraft] {
        let sources = urls.compactMap { url -> (URL, CGImage, TransparentFrameContent)? in
            guard let image = loadImage(at: url),
                  let content = try? FrameCanvasComposer().transparentContent(in: image) else {
                return nil
            }
            return (url, image, content)
        }
        guard !sources.isEmpty else {
            return []
        }

        if let reference {
            let referencePlacement = reference.placement
            let targetSize = reference.renderedContentSize
            let anchorX = referencePlacement.x + targetSize.width / 2
            let anchorBottom = referencePlacement.y + targetSize.height
            return sources.compactMap { url, image, content in
                let scale = min(
                    targetSize.width / Double(content.image.width),
                    targetSize.height / Double(content.image.height)
                )
                return UserPetAnimationFrameDraft(
                    source: .png(url),
                    durationMilliseconds: durationMilliseconds,
                    image: image,
                    canvasSize: reference.canvasSize,
                    baseScale: scale,
                    anchorX: anchorX,
                    anchorBottom: anchorBottom
                )
            }
        }

        let canvasSize = PixelSize(
            width: sources.map { $0.1.width }.max() ?? 512,
            height: sources.map { $0.1.height }.max() ?? 512
        )
        let usesSameCanvas = Set(sources.map { "\($0.1.width)x\($0.1.height)" }).count == 1
        return sources.compactMap { url, image, content in
            let scale: Double
            let anchorX: Double
            let anchorBottom: Double
            if usesSameCanvas {
                scale = 1
                anchorX = Double(content.sourceBounds.x)
                    + Double(content.sourceBounds.width) / 2
                anchorBottom = Double(
                    content.sourceBounds.y + content.sourceBounds.height
                )
            } else {
                scale = min(
                    Double(canvasSize.width) * 0.8 / Double(content.image.width),
                    Double(canvasSize.height) * 0.8 / Double(content.image.height)
                )
                anchorX = Double(canvasSize.width) / 2
                anchorBottom = Double(canvasSize.height) * 0.9
            }
            return UserPetAnimationFrameDraft(
                source: .png(url),
                durationMilliseconds: durationMilliseconds,
                image: image,
                canvasSize: canvasSize,
                baseScale: scale,
                anchorX: anchorX,
                anchorBottom: anchorBottom
            )
        }
    }

    private static func loadImage(at fileURL: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    private static func durationMilliseconds(_ duration: Duration) -> Int {
        let components = duration.components
        let value = components.seconds * 1_000
            + components.attoseconds / 1_000_000_000_000_000
        return Int(clamping: value)
    }
}

private struct FramePlacementControls: View {
    @Binding var frame: UserPetAnimationFrameDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("자동 맞춤 대비 배율")
                Spacer()
                Text("\(Int(frame.scalePercent.rounded()))%")
                    .monospacedDigit()
            }
            .font(.caption)

            Slider(value: scaleBinding, in: 25...400, step: 5)
                .accessibilityLabel("선택 프레임 배율")

            Stepper(
                "가로 \(Int(frame.offsetX.rounded())) px (오른쪽 +)",
                value: horizontalOffsetBinding,
                in: -Double(frame.canvasSize.width)...Double(frame.canvasSize.width),
                step: 1
            )
            .accessibilityLabel("선택 프레임 가로 위치")

            Stepper(
                "세로 \(Int(frame.offsetY.rounded())) px (아래 +)",
                value: verticalOffsetBinding,
                in: -Double(frame.canvasSize.height)...Double(frame.canvasSize.height),
                step: 1
            )
            .accessibilityLabel("선택 프레임 세로 위치")

            Button("배치 초기화") {
                frame.resetPlacement()
            }
            .accessibilityIdentifier("monglepet.petAnimation.resetPlacement")
        }
        .controlSize(.small)
    }

    private var scaleBinding: Binding<Double> {
        Binding(
            get: { frame.scalePercent },
            set: {
                frame.scalePercent = $0
                frame.refreshPreview()
            }
        )
    }

    private var horizontalOffsetBinding: Binding<Double> {
        Binding(
            get: { frame.offsetX },
            set: {
                frame.offsetX = $0
                frame.refreshPreview()
            }
        )
    }

    private var verticalOffsetBinding: Binding<Double> {
        Binding(
            get: { frame.offsetY },
            set: {
                frame.offsetY = $0
                frame.refreshPreview()
            }
        )
    }
}

private enum EditableAnimationPreviewMode: String, CaseIterable, Identifiable {
    case animation = "전체 재생"
    case selectedFrame = "선택 프레임"

    var id: Self { self }
}

private struct EditableAnimationPreviewPanel: View {
    let frames: [UserPetAnimationFrameDraft]
    let loops: Bool
    let selectedFrameID: UUID?

    @State private var previewMode: EditableAnimationPreviewMode = .selectedFrame
    @State private var isPlaying = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("미리보기 방식", selection: $previewMode) {
                ForEach(EditableAnimationPreviewMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityIdentifier("monglepet.petAnimation.previewMode")

            EditableAnimationPreviewView(
                frames: frames,
                loops: loops,
                selectedFrameID: selectedFrameID,
                previewMode: previewMode,
                isPlaying: $isPlaying
            )
            .frame(height: 190)
            .background(
                .quaternary.opacity(0.18),
                in: RoundedRectangle(cornerRadius: 10)
            )

            HStack {
                if previewMode == .animation {
                    Button {
                        isPlaying.toggle()
                    } label: {
                        Label(
                            isPlaying ? "일시정지" : "재생",
                            systemImage: isPlaying ? "pause.fill" : "play.fill"
                        )
                    }
                    .controlSize(.small)
                    .accessibilityIdentifier("monglepet.petAnimation.previewPlayback")
                }

                Spacer()

                Text(previewCaption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }

    private var previewCaption: String {
        switch previewMode {
        case .animation:
            "총 \(frames.count)개 프레임"
        case .selectedFrame:
            if let selectedFrameID,
               let index = frames.firstIndex(where: { $0.id == selectedFrameID }) {
                "선택 \(index + 1)/\(frames.count)"
            } else {
                "프레임을 선택해 주세요"
            }
        }
    }
}

private struct EditableAnimationPreviewView: View {
    let frames: [UserPetAnimationFrameDraft]
    let loops: Bool
    let selectedFrameID: UUID?
    let previewMode: EditableAnimationPreviewMode
    @Binding var isPlaying: Bool

    @State private var frameIndex = 0

    var body: some View {
        GeometryReader { geometry in
            let canvasSize = fittedCanvasSize(in: geometry.size)

            ZStack {
                TransparencyGridView()

                if let image = currentFrame?.previewImage {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                } else {
                    Image(systemName: "photo")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
            .overlay {
                Rectangle()
                    .stroke(.secondary.opacity(0.45), lineWidth: 1)
            }
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
        }
        .task(id: playbackIdentity) {
            guard previewMode == .animation, isPlaying, !frames.isEmpty else {
                return
            }
            if !frames.indices.contains(frameIndex) {
                frameIndex = 0
            }
            if !loops, frameIndex == frames.index(before: frames.endIndex) {
                frameIndex = 0
            }
            while !Task.isCancelled {
                let delay = min(
                    60_000,
                    max(16, currentFrame?.durationMilliseconds ?? 120)
                )
                try? await Task.sleep(for: .milliseconds(delay))
                guard !Task.isCancelled else {
                    return
                }
                if frameIndex + 1 < frames.count {
                    frameIndex += 1
                } else if loops {
                    frameIndex = 0
                } else {
                    isPlaying = false
                    return
                }
            }
        }
    }

    private var currentFrame: UserPetAnimationFrameDraft? {
        if previewMode == .selectedFrame {
            return frames.first(where: { $0.id == selectedFrameID }) ?? frames.first
        }
        guard frames.indices.contains(frameIndex) else {
            return frames.first
        }
        return frames[frameIndex]
    }

    private func fittedCanvasSize(in availableSize: CGSize) -> CGSize {
        let width = max(1, Double(currentFrame?.canvasSize.width ?? 1))
        let height = max(1, Double(currentFrame?.canvasSize.height ?? 1))
        let availableWidth = max(1, availableSize.width - 16)
        let availableHeight = max(1, availableSize.height - 16)
        let scale = min(availableWidth / width, availableHeight / height)
        return CGSize(width: width * scale, height: height * scale)
    }

    private var playbackIdentity: String {
        frames.map { "\($0.id.uuidString):\($0.durationMilliseconds)" }
            .joined(separator: "|")
            + ":\(loops):\(previewMode.rawValue):\(isPlaying)"
    }
}

private struct TransparencyGridView: View {
    private let squareLength = 10.0

    var body: some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(Color(nsColor: .controlBackgroundColor))
            )
            let columns = Int(ceil(size.width / squareLength))
            let rows = Int(ceil(size.height / squareLength))
            for row in 0..<rows {
                for column in 0..<columns where (row + column).isMultiple(of: 2) {
                    context.fill(
                        Path(
                            CGRect(
                                x: Double(column) * squareLength,
                                y: Double(row) * squareLength,
                                width: squareLength,
                                height: squareLength
                            )
                        ),
                        with: .color(.secondary.opacity(0.13))
                    )
                }
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    let settingsSession = AppSettingsSession(
            store: AppSettingsStore(
                settingsURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("MonglePet-Preview-settings.json")
            )
        )
    let definition = BuiltInPet.mongleDefinition(
        atlasPixelSize: PixelSize(width: 192, height: 208)
    )
    SettingsView(
        settingsSession: settingsSession,
        petLibrarySession: PetLibrarySession(
            builtInDefinition: definition,
            installedPackagesProvider: { [] },
            installationRemover: { _ in }
        )
    )
}
