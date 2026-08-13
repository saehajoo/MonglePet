import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var settingsSession: AppSettingsSession
    @ObservedObject var petLibrarySession: PetLibrarySession
    @ObservedObject var loginLaunchSettings: LoginLaunchSettings
    @ObservedObject var runtimeControlSession: PetRuntimeControlSession
    @State private var destination = SettingsDestination.activePets

    var body: some View {
        NavigationSplitView {
            List(selection: $destination) {
                Section("데스크톱") {
                    navigationRow(
                        "활성 펫",
                        systemImage: "pawprint.fill",
                        destination: .activePets
                    )
                    navigationRow(
                        "일반",
                        systemImage: "gearshape",
                        destination: .general
                    )
                }

                Section("선택한 펫") {
                    navigationRow(
                        "표시 및 이동",
                        systemImage: "location",
                        destination: .movement
                    )
                    navigationRow(
                        "행동 루틴",
                        systemImage: "list.bullet.rectangle",
                        destination: .behavior
                    )
                    navigationRow(
                        "말풍선",
                        systemImage: "text.bubble",
                        destination: .speech
                    )
                    navigationRow(
                        "자동 규칙",
                        systemImage: "bolt.badge.clock",
                        destination: .automaticRules
                    )
                }

                Section("보관함") {
                    navigationRow(
                        "펫 보관함",
                        systemImage: "shippingbox",
                        destination: .petLibrary
                    )
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(
                min: 180,
                ideal: 210,
                max: 250
            )
            .accessibilityIdentifier("monglepet.settings.sidebar")
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 840, minHeight: 620)
        .accessibilityIdentifier("monglepet.settings.root")
    }

    @ViewBuilder
    private var detailView: some View {
        switch destination {
        case .activePets:
            ActivePetsSettingsView(
                settingsSession: settingsSession,
                petLibrarySession: petLibrarySession,
                runtimeControlSession: runtimeControlSession
            )
        case .general:
            GeneralSettingsView(
                settingsSession: settingsSession,
                loginLaunchSettings: loginLaunchSettings
            )
        case .movement:
            MovementSettingsView(
                settingsSession: settingsSession,
                petDefinition: petLibrarySession.selectedItem.definition,
                petDisplayName: selectedPetDisplayName
            )
        case .behavior:
            BehaviorSequencesSettingsView(
                settingsSession: settingsSession,
                petDefinition: petLibrarySession.selectedItem.definition,
                petDisplayName: selectedPetDisplayName
            )
        case .speech:
            SpeechBubbleSettingsView(
                settingsSession: settingsSession,
                petItem: petLibrarySession.selectedItem,
                petDisplayName: selectedPetDisplayName
            )
        case .automaticRules:
            AutomaticRulesSettingsView(
                settingsSession: settingsSession,
                petDisplayName: selectedPetDisplayName
            )
        case .petLibrary:
            PetSettingsView(
                settingsSession: settingsSession,
                petLibrarySession: petLibrarySession
            )
        }
    }

    private func navigationRow(
        _ title: String,
        systemImage: String,
        destination: SettingsDestination
    ) -> some View {
        Label(title, systemImage: systemImage)
            .tag(destination)
            .accessibilityIdentifier(destination.accessibilityIdentifier)
    }

    private var selectedPetDisplayName: String {
        settingsSession.settings.selectedPetInstance?.nickname
            ?? petLibrarySession.selectedItem.metadata.displayName
    }
}

private enum SettingsDestination: Hashable {
    case activePets
    case general
    case movement
    case behavior
    case speech
    case automaticRules
    case petLibrary

    var accessibilityIdentifier: String {
        switch self {
        case .activePets:
            "monglepet.settings.navigation.activePets"
        case .general:
            "monglepet.settings.navigation.general"
        case .movement:
            "monglepet.settings.navigation.movement"
        case .behavior:
            "monglepet.settings.navigation.behavior"
        case .speech:
            "monglepet.settings.navigation.speech"
        case .automaticRules:
            "monglepet.settings.navigation.automaticRules"
        case .petLibrary:
            "monglepet.settings.navigation.petLibrary"
        }
    }
}

private struct PetSettingsView: View {
    @ObservedObject var settingsSession: AppSettingsSession
    @ObservedObject var petLibrarySession: PetLibrarySession
    @State private var isConfirmingRemoval = false
    @State private var isConfirmingAnimationRemoval = false
    @State private var isEditingPetDetails = false
    @State private var isCreatingEditableCopy = false
    @State private var userPetEditorMode: UserPetEditorMode?
    @State private var editingAnimation: PetMotion?
    @State private var previewMotionID: String?
    @State private var importReview: PetPackageImportReview?
    @State private var pendingImportAction: PetImportAction?
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

            Section("현재 펫") {
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
                    .frame(width: 160, height: 160)
                    .background(
                        .quaternary.opacity(0.35),
                        in: RoundedRectangle(cornerRadius: 12)
                    )
                    .accessibilityLabel("현재 펫 애니메이션 미리보기")

                    VStack(alignment: .leading, spacing: 10) {
                        Text(
                            petLibrarySession.selectedItem.metadata.displayName
                        )
                        .font(.title3.weight(.semibold))

                        LabeledContent(
                            "버전",
                            value: petLibrarySession.selectedItem.metadata.version
                        )
                        LabeledContent(
                            "제작자",
                            value: petLibrarySession.selectedItem.metadata.author
                        )
                        if let description = petLibrarySession.selectedItem.metadata.description {
                            LabeledContent("설명", value: description)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Section("애니메이션") {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(
                            petLibrarySession.selectedItem.definition.motions
                        ) { motion in
                            Button {
                                previewMotionID = motion.id
                            } label: {
                                HStack {
                                    Text(motion.id)
                                        .lineLimit(1)

                                    Spacer()

                                    if motion.id
                                        == petLibrarySession.selectedItem
                                            .definition.defaultMotionID {
                                        Text("기본")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 10)
                                .frame(
                                    maxWidth: .infinity,
                                    minHeight: 32,
                                    alignment: .leading
                                )
                                .background(
                                    effectivePreviewMotionID == motion.id
                                        ? Color.accentColor.opacity(0.16)
                                        : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            .accessibilityLabel(
                                animationAccessibilityLabel(for: motion)
                            )
                            .accessibilityAddTraits(
                                effectivePreviewMotionID == motion.id
                                    ? .isSelected
                                    : []
                            )
                        }
                    }
                    .padding(4)
                }
                .frame(height: animationListHeight)
                .background(
                    .quaternary.opacity(0.24),
                    in: RoundedRectangle(cornerRadius: 8)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            Color(nsColor: .separatorColor).opacity(0.65),
                            lineWidth: 1
                        )
                }
                .accessibilityIdentifier("monglepet.settings.petAnimations")

                if let motion = selectedPreviewMotion {
                    LabeledContent("선택한 애니메이션") {
                        Text(motionSummary(motion))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .accessibilityIdentifier(
                                "monglepet.settings.petAnimationSummary"
                            )
                    }
                }

                if petLibrarySession.selectedItem.isEditable {
                    LazyVGrid(
                        columns: [
                            GridItem(.adaptive(minimum: 160), spacing: 8)
                        ],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        Button {
                            userPetEditorMode = .addAnimation
                        } label: {
                            Label(
                                "애니메이션 추가",
                                systemImage: "photo.badge.plus"
                            )
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(petLibrarySession.isImporting)
                        .accessibilityIdentifier(
                            "monglepet.settings.addPetAnimation"
                        )

                        Button {
                            editingAnimation = selectedPreviewMotion
                        } label: {
                            Label(
                                "애니메이션 수정",
                                systemImage: "slider.horizontal.3"
                            )
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )
                        }
                        .disabled(
                            selectedPreviewMotion == nil
                                || petLibrarySession.isImporting
                        )
                        .accessibilityIdentifier(
                            "monglepet.settings.editPetAnimation"
                        )

                        Button(role: .destructive) {
                            isConfirmingAnimationRemoval = true
                        } label: {
                            Label(
                                "애니메이션 삭제",
                                systemImage: "trash"
                            )
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )
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
                } else {
                    Label(
                        petLibrarySession.selectedItem.isBuiltIn
                            ? "내장 몽글이의 애니메이션은 직접 편집할 수 없습니다."
                            : "가져온 펫을 편집하려면 편집 가능한 사본을 만들어야 합니다.",
                        systemImage: "lock"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section("MonglePet 패키지") {
                Text(
                    ".monglepet 형식으로 펫 정보와 애니메이션을 가져오거나 공유합니다."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 180), spacing: 8)
                    ],
                    alignment: .leading,
                    spacing: 8
                ) {
                    Button {
                        choosePetPackage()
                    } label: {
                        Label(
                            "패키지 가져오기",
                            systemImage: "square.and.arrow.down"
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .disabled(isPetLibraryBusy)
                    .accessibilityIdentifier(
                        "monglepet.settings.importPackage"
                    )

                    if !petLibrarySession.selectedItem.isBuiltIn {
                        Button {
                            shareReview = petLibrarySession
                                .reviewSelectedPetForSharing(
                                    behaviorProfile:
                                        settingsSession.settings
                                            .activeBehaviorProfile
                                )
                        } label: {
                            Label(
                                "현재 펫 내보내기",
                                systemImage: "square.and.arrow.up"
                            )
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )
                        }
                        .disabled(isPetLibraryBusy)
                        .accessibilityIdentifier(
                            "monglepet.settings.exportPackage"
                        )
                    }
                }

                if petLibrarySession.selectedItem.isBuiltIn {
                    Text("내장 몽글이는 패키지로 내보낼 수 없습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("펫 관리") {
                Text(petManagementDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(
                    columns: [
                        GridItem(.adaptive(minimum: 160), spacing: 8)
                    ],
                    alignment: .leading,
                    spacing: 8
                ) {
                    Button {
                        userPetEditorMode = .create
                    } label: {
                        Label("새 펫 만들기", systemImage: "plus")
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )
                    }
                    .disabled(petLibrarySession.isImporting)
                    .accessibilityIdentifier(
                        "monglepet.settings.createUserPet"
                    )

                    if petLibrarySession.selectedItem.isEditable {
                        Button {
                            isEditingPetDetails = true
                        } label: {
                            Label("펫 정보 수정", systemImage: "pencil")
                                .frame(
                                    maxWidth: .infinity,
                                    alignment: .leading
                                )
                        }
                        .disabled(petLibrarySession.isImporting)
                        .accessibilityIdentifier(
                            "monglepet.settings.editPetDetails"
                        )
                    } else if !petLibrarySession.selectedItem.isBuiltIn {
                        Button {
                            isCreatingEditableCopy = true
                        } label: {
                            Label(
                                "편집 가능한 사본 만들기",
                                systemImage: "doc.on.doc"
                            )
                            .frame(
                                maxWidth: .infinity,
                                alignment: .leading
                            )
                        }
                        .disabled(petLibrarySession.isImporting)
                        .accessibilityIdentifier(
                            "monglepet.settings.createEditablePetCopy"
                        )
                    }

                    if !petLibrarySession.selectedItem.isBuiltIn {
                        Button(role: .destructive) {
                            isConfirmingRemoval = true
                        } label: {
                            Label("펫 삭제", systemImage: "trash")
                                .frame(
                                    maxWidth: .infinity,
                                    alignment: .leading
                                )
                        }
                        .disabled(isPetLibraryBusy)
                        .accessibilityIdentifier(
                            "monglepet.settings.removePet"
                        )
                    }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(
            item: $importReview,
            onDismiss: performPendingImportAction
        ) { review in
            PetPackageImportReviewView(
                review: review,
                allowsRecommendedProfileApplication:
                    settingsSession.isWritingEnabled,
                onInstall: { appliesRecommendedProfile in
                    pendingImportAction = PetImportAction(
                        review: review,
                        appliesRecommendedProfile: appliesRecommendedProfile
                    )
                }
            )
        }
        .sheet(item: duplicateInstallRequestBinding) { request in
            DuplicatePetInstallView(
                request: request,
                petLibrarySession: petLibrarySession,
                allowsRecommendedProfileApplication:
                    settingsSession.isWritingEnabled
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

    private var animationListHeight: CGFloat {
        let visibleRowCount = min(
            petLibrarySession.selectedItem.definition.motions.count,
            7
        )
        return max(112, CGFloat(visibleRowCount) * 34 + 8)
    }

    private var isPetLibraryBusy: Bool {
        petLibrarySession.isImporting || petLibrarySession.isExporting
    }

    private var petManagementDescription: String {
        if petLibrarySession.selectedItem.isBuiltIn {
            return "개별 PNG 또는 정적 PNG·WebP 스프라이트 시트로 새 펫을 만들 수 있습니다."
        }
        if petLibrarySession.selectedItem.isEditable {
            return "현재 펫의 이름, 버전과 제작자를 수정하거나 펫을 삭제할 수 있습니다."
        }
        return "가져온 패키지는 원본을 보호하기 위해 직접 수정하지 않으며 필요하면 펫을 삭제할 수 있습니다."
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

    private func animationAccessibilityLabel(for motion: PetMotion) -> String {
        motion.id == petLibrarySession.selectedItem.definition.defaultMotionID
            ? "\(motion.id), 기본 애니메이션"
            : motion.id
    }

    private func durationMilliseconds(_ duration: Duration) -> Int64 {
        let components = duration.components
        return components.seconds * 1_000
            + components.attoseconds / 1_000_000_000_000_000
    }

    private var petSelectionBinding: Binding<PetLibrarySelection> {
        Binding(
            get: { petLibrarySession.selection },
            set: { _ = petLibrarySession.select($0) }
        )
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
        importReview = petLibrarySession.reviewPackageForImport(from: sourceURL)
    }

    private func performPendingImportAction() {
        guard let action = pendingImportAction else {
            return
        }
        pendingImportAction = nil
        _ = petLibrarySession.installReviewedPackage(
            action.review,
            appliesRecommendedProfile: action.appliesRecommendedProfile
        )
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

private struct GeneralSettingsView: View {
    @ObservedObject var settingsSession: AppSettingsSession
    @ObservedObject var loginLaunchSettings: LoginLaunchSettings

    var body: some View {
        Form {
            if let loadNotice = settingsSession.loadNotice {
                noticeLabel(
                    loadNotice,
                    systemImage: "exclamationmark.triangle.fill"
                )
            }
            if let saveErrorMessage = settingsSession.saveErrorMessage {
                noticeLabel(
                    saveErrorMessage,
                    systemImage: "xmark.circle.fill"
                )
            }

            Section("앱 실행") {
                Toggle(
                    "로그인 시 MonglePet 자동 실행",
                    isOn: loginLaunchBinding
                )
                .accessibilityIdentifier(
                    "monglepet.settings.launchAtLogin"
                )

                loginLaunchStatusLabel

                if loginLaunchSettings.requiresApproval {
                    Button("로그인 항목 설정 열기") {
                        loginLaunchSettings.openSystemSettings()
                    }
                    .accessibilityIdentifier(
                        "monglepet.settings.openLoginItems"
                    )
                }

                if let errorMessage = loginLaunchSettings.errorMessage {
                    noticeLabel(
                        errorMessage,
                        systemImage: "xmark.circle.fill"
                    )
                }
            }

            Section("앱 정보") {
                LabeledContent(
                    "버전",
                    value: MonglePetAppVersion.current.displayText
                )
                .accessibilityIdentifier("monglepet.settings.appVersion")

                Text("펫 패키지 호환성은 이 앱 버전을 기준으로 확인합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loginLaunchSettings.refresh)
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            loginLaunchSettings.refresh()
        }
    }

    private var loginLaunchBinding: Binding<Bool> {
        Binding(
            get: { loginLaunchSettings.isRequestedEnabled },
            set: { loginLaunchSettings.setEnabled($0) }
        )
    }

    @ViewBuilder
    private var loginLaunchStatusLabel: some View {
        switch loginLaunchSettings.status {
        case .notRegistered:
            Text("초기에는 꺼져 있으며 원할 때 직접 켤 수 있습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .enabled:
            Label(
                "다음 로그인부터 MonglePet이 자동으로 실행됩니다.",
                systemImage: "checkmark.circle.fill"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        case .requiresApproval:
            Label(
                "macOS 승인이 필요합니다. 로그인 항목 설정에서 MonglePet을 허용해 주세요.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(.orange)
            .accessibilityIdentifier(
                "monglepet.settings.loginApprovalRequired"
            )
        case .notFound:
            Label(
                "아직 로그인 항목 등록 기록이 없습니다. 켜면 새로 등록합니다.",
                systemImage: "info.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier(
                "monglepet.settings.loginItemUnavailable"
            )
        }
    }

    @ViewBuilder
    private func noticeLabel(
        _ message: String,
        systemImage: String
    ) -> some View {
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
}

private struct PetImportAction {
    let review: PetPackageImportReview
    let appliesRecommendedProfile: Bool
}

private struct PetPackageImportReviewView: View {
    @Environment(\.dismiss) private var dismiss

    let review: PetPackageImportReview
    let allowsRecommendedProfileApplication: Bool
    let onInstall: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("가져오기 내용 확인")
                            .font(.title2.weight(.semibold))
                        Text("펫 정보와 함께 제공된 권장 설정을 확인합니다.")
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("펫 정보")
                            .font(.headline)
                        Grid(
                            alignment: .leading,
                            horizontalSpacing: 20,
                            verticalSpacing: 8
                        ) {
                            informationRow("펫 이름", value: review.metadata.displayName)
                            informationRow("버전", value: review.metadata.version)
                            informationRow("제작자", value: review.metadata.author)
                            informationRow("애니메이션", value: "\(review.definition.motions.count)개")
                        }
                        .padding(12)
                        .background(
                            .quaternary.opacity(0.35),
                            in: RoundedRectangle(cornerRadius: 10)
                        )
                    }

                    compatibilitySection
                    recommendedProfileSection

                    Text(
                        "권장 설정을 적용해도 설치 후 행동 루틴, 자동 규칙과 이동 설정을 자유롭게 수정할 수 있습니다."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(20)
            }

            Divider()

            HStack {
                Button("취소", role: .cancel) {
                    dismiss()
                }
                Spacer()
                Button("펫만 설치") {
                    onInstall(false)
                    dismiss()
                }
                .disabled(!review.canInstall)
                .accessibilityIdentifier("monglepet.import.petOnly")
                if review.recommendedProfile != nil,
                   allowsRecommendedProfileApplication {
                    Button("권장 설정 적용 후 설치") {
                        onInstall(true)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!review.canInstall)
                    .accessibilityIdentifier(
                        "monglepet.import.applyRecommendedProfile"
                    )
                }
            }
            .padding(16)
        }
        .frame(width: 560)
        .frame(minHeight: 440, maxHeight: 680)
        .accessibilityIdentifier("monglepet.import.review")
    }

    @ViewBuilder
    private var compatibilitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MonglePet 호환성")
                .font(.headline)

            if let compatibility = review.compatibility {
                Grid(
                    alignment: .leading,
                    horizontalSpacing: 20,
                    verticalSpacing: 8
                ) {
                    informationRow(
                        "현재 앱",
                        value: review.currentMonglePetVersion.description
                    )
                    informationRow(
                        "제작 앱",
                        value: compatibility.createdWithMonglePetVersion?.description
                            ?? "정보 없음"
                    )
                    informationRow(
                        "최소 앱",
                        value: compatibility.minimumMonglePetVersion?.description
                            ?? "정보 없음"
                    )
                }
                .padding(12)
                .background(
                    .quaternary.opacity(0.35),
                    in: RoundedRectangle(cornerRadius: 10)
                )
            } else {
                Label(
                    "이전 형식의 패키지로 앱 호환 버전 정보가 없습니다.",
                    systemImage: "info.circle"
                )
                .foregroundStyle(.secondary)
            }

            switch review.compatibilityAssessment {
            case .compatible:
                if review.compatibility != nil {
                    Label(
                        "현재 MonglePet 버전에서 설치할 수 있습니다.",
                        systemImage: "checkmark.circle.fill"
                    )
                    .foregroundStyle(.green)
                }
            case let .createdWithNewerVersion(createdWithVersion):
                Label(
                    "MonglePet \(createdWithVersion.description)에서 만든 펫입니다. 일부 표현이 다를 수 있지만 설치할 수 있습니다.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
            case let .requiresNewerVersion(requiredVersion):
                Label(
                    "설치하려면 MonglePet \(requiredVersion.description) 이상이 필요합니다. 현재 버전에서는 설치할 수 없습니다.",
                    systemImage: "xmark.octagon.fill"
                )
                .foregroundStyle(.red)
                .accessibilityIdentifier("monglepet.import.incompatibleVersion")
            }
        }
    }

    @ViewBuilder
    private var recommendedProfileSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("펫별 행동·이동·말풍선 권장 설정")
                .font(.headline)

            if let profile = review.recommendedProfile {
                RecommendedProfileSummaryView(
                    summary: RecommendedProfileSummary(profile: profile)
                )

                if !allowsRecommendedProfileApplication {
                    Label(
                        "현재 설정 파일을 보호하기 위해 권장 설정 적용이 비활성화되어 있습니다.",
                        systemImage: "lock.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            } else if let issue = review.recommendedProfileIssue {
                Label(
                    "권장 설정을 적용할 수 없습니다. 펫 자체는 설치할 수 있습니다.",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .foregroundStyle(.orange)
                Text(issue.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label(
                    "이 패키지에는 별도의 권장 설정이 없습니다.",
                    systemImage: "info.circle"
                )
                .foregroundStyle(.secondary)
            }
        }
    }

    private func informationRow(
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

private enum DuplicateReplacementProfileChoice: Hashable {
    case preserveLocal
    case applyRecommended
}

private struct DuplicatePetInstallView: View {
    @Environment(\.dismiss) private var dismiss

    let request: DuplicatePetInstallRequest
    @ObservedObject var petLibrarySession: PetLibrarySession
    let allowsRecommendedProfileApplication: Bool

    @State private var selectedInstallationID: UUID?
    @State private var replacementProfileChoice:
        DuplicateReplacementProfileChoice = .preserveLocal

    init(
        request: DuplicatePetInstallRequest,
        petLibrarySession: PetLibrarySession,
        allowsRecommendedProfileApplication: Bool
    ) {
        self.request = request
        self.petLibrarySession = petLibrarySession
        self.allowsRecommendedProfileApplication =
            allowsRecommendedProfileApplication
        _selectedInstallationID = State(
            initialValue: request.preferredReplacementInstallationID
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("같은 펫 패키지가 이미 있습니다")
                            .font(.title2.weight(.semibold))
                        Text(
                            "새 설치로 추가하거나, 아래 설치 중 하나를 선택해 교체할 수 있습니다."
                        )
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
                            LazyVStack(spacing: 0) {
                                ForEach(request.candidates) { candidate in
                                    Button {
                                        selectedInstallationID =
                                            candidate.installationID
                                    } label: {
                                        candidateRow(candidate)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier(
                                        "monglepet.import.candidate."
                                            + candidate.installationID.uuidString
                                    )

                                    if candidate.id != request.candidates.last?.id {
                                        Divider()
                                    }
                                }
                            }
                            .background(
                                .quaternary.opacity(0.35),
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Label(
                            newInstallationDescription,
                            systemImage: "plus.square.on.square"
                        )
                        Label(
                            replacementDescription,
                            systemImage: selectedCandidate?.isEditable == true
                                ? "exclamationmark.triangle.fill"
                                : "arrow.triangle.2.circlepath"
                        )
                        .foregroundStyle(
                            selectedCandidate?.isEditable == true
                                ? Color.orange
                                : Color.secondary
                        )
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    replacementProfileSection

                    if let errorMessage = petLibrarySession.errorMessage {
                        Label(errorMessage, systemImage: "xmark.circle.fill")
                            .foregroundStyle(.orange)
                            .font(.callout)
                            .accessibilityIdentifier("monglepet.import.error")
                    }
                }
                .padding(20)
            }

            Divider()

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
                        selectedInstallationID,
                        appliesRecommendedProfile:
                            replacementProfileChoice == .applyRecommended
                    )
                }
                .disabled(
                    selectedInstallationID == nil || petLibrarySession.isImporting
                )
                .accessibilityIdentifier("monglepet.import.replaceSelected")
            }
            .padding(16)
        }
        .frame(width: 580)
        .frame(minHeight: 520, maxHeight: 720)
        .accessibilityIdentifier("monglepet.import.duplicateReview")
    }

    @ViewBuilder
    private var replacementProfileSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("교체 후 행동·이동 설정")
                .font(.headline)

            if request.importReview?.recommendedProfile != nil,
               allowsRecommendedProfileApplication {
                Picker(
                    "교체 후 행동·이동 설정",
                    selection: $replacementProfileChoice
                ) {
                    Text("현재 설정 유지")
                        .tag(DuplicateReplacementProfileChoice.preserveLocal)
                    Text("권장 설정으로 전체 교체")
                        .tag(DuplicateReplacementProfileChoice.applyRecommended)
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)
                .accessibilityIdentifier(
                    "monglepet.import.replacementProfileChoice"
                )

                Text(replacementProfileChoiceDescription)
                    .font(.caption)
                    .foregroundStyle(
                        replacementProfileChoice == .applyRecommended
                            ? Color.orange
                            : Color.secondary
                    )
            } else {
                Label(
                    replacementProfileUnavailableDescription,
                    systemImage: allowsRecommendedProfileApplication
                        ? "checkmark.shield"
                        : "lock.fill"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(
            .quaternary.opacity(0.35),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }

    private var replacementProfileChoiceDescription: String {
        switch replacementProfileChoice {
        case .preserveLocal:
            "현재 설치의 행동 모드, 루틴, 자동 규칙, 이동과 쓰다듬기 설정을 그대로 유지합니다."
        case .applyRecommended:
            "현재 펫별 행동·이동·말풍선 설정 전체를 패키지의 권장 설정으로 바꿉니다. 부분 병합은 제공하지 않습니다."
        }
    }

    private var replacementProfileUnavailableDescription: String {
        if !allowsRecommendedProfileApplication {
            return "현재 설정 파일을 보호하기 위해 로컬 설정을 유지합니다."
        }
        if request.importReview?.containsRecommendedProfile == true {
            return "이 패키지의 권장 설정을 적용할 수 없어 현재 로컬 설정을 유지합니다."
        }
        return "패키지에 권장 설정이 없어 현재 로컬 설정을 유지합니다."
    }

    private var selectedCandidate: DuplicatePetInstallationCandidate? {
        request.candidates.first {
            $0.installationID == selectedInstallationID
        }
    }

    private var replacementDescription: String {
        if selectedCandidate?.isEditable == true {
            return "교체하면 선택한 펫 파일과 편집 가능 상태가 읽기 전용 패키지로 바뀝니다. 아래에서 행동·이동 설정 처리 방식을 선택하세요."
        }
        return "교체하면 선택한 설치 ID의 펫 파일이 바뀝니다. 아래에서 행동·이동 설정 처리 방식을 선택하세요."
    }

    private var newInstallationDescription: String {
        if request.appliesRecommendedProfileToNewInstallation,
           request.importReview?.recommendedProfile != nil {
            return "새 설치는 새 설치 ID를 사용하며 확인한 행동·이동·말풍선 권장 설정을 적용합니다."
        }
        return "새 설치는 새 설치 ID와 독립된 기본 행동·이동 설정을 사용합니다."
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
                    }
                    .padding(12)
                    .background(
                        .quaternary.opacity(0.35),
                        in: RoundedRectangle(cornerRadius: 10)
                    )

                    sharedContentOptions

                    Toggle(
                        "이 펫과 이미지 자산을 게시하거나 공유할 권한이 있음을 확인합니다.",
                        isOn: $isSharingRightsConfirmed
                    )
                    .accessibilityIdentifier(
                        "monglepet.share.rightsConfirmation"
                    )

                    Text(
                        "공유한 콘텐츠의 권리와 책임은 게시자에게 있으며, 받는 사용자는 편집 가능한 사본을 만들 수 있습니다."
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

    private var sharedContentOptions: some View {
        GroupBox("내보낼 내용") {
            VStack(alignment: .leading, spacing: 12) {
                Label(
                    "펫 정보, 미리보기와 등록된 애니메이션",
                    systemImage: "photo.on.rectangle.angled"
                )

                Divider()

                Toggle(
                    "펫별 행동·이동·말풍선 권장 설정 포함",
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
                    Text("현재 펫에 공유할 행동·이동·말풍선 권장 설정이 없습니다.")
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
        if let profile = includesApplicationRules
            ? review.recommendedProfileWithApplicationRules
            : review.recommendedProfile {
            RecommendedProfileSummaryView(
                summary: RecommendedProfileSummary(profile: profile)
            )
            .padding(.leading, 8)
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

private struct RecommendedProfileSummaryView: View {
    let summary: RecommendedProfileSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Grid(
                alignment: .leading,
                horizontalSpacing: 16,
                verticalSpacing: 6
            ) {
                informationRow(
                    "행동 모드",
                    value: summary.mode == .automatic ? "자동" : "수동"
                )
                informationRow(
                    "선택 루틴",
                    value: summary.manualSequenceID.map(
                        BuiltInBehaviorPresets.displayName(for:)
                    ) ?? "자동 결정"
                )
                informationRow(
                    "행동 루틴",
                    value: "\(summary.sequences.count)개"
                )
                informationRow(
                    "자동 규칙",
                    value: "\(summary.automaticRules.count)개"
                )
                informationRow(
                    "이동 방식",
                    value: movementModeName(summary.movement.mode)
                )
                informationRow(
                    "쓰다듬기",
                    value: summary.movement.mode == .cursorAvoiding
                        ? "도망가기 모드에서 사용하지 않음"
                        : summary.pettingMotionID ?? "지정 안 함"
                )
                informationRow(
                    "말풍선",
                    value: summary.speech.isEnabled
                        ? "사용 · \(summary.speech.theme.colorStyle.displayName) 테마"
                        : "사용 안 함 · \(summary.speech.theme.colorStyle.displayName) 테마"
                )
                informationRow(
                    "말풍선 위치",
                    value:
                        "\(summary.speech.placement.preferredPosition.displayName) · "
                        + "좌우 \(Int(summary.speech.placement.horizontalOffset.rounded()))pt · "
                        + "간격 \(Int(summary.speech.placement.gap.rounded()))pt"
                )
                informationRow(
                    "행동 대사",
                    value:
                        "\(summary.speech.behaviorPhrases.count)개 · "
                        + "전환 시 \(summary.speech.behaviorChangePolicy.displayName)"
                )
                informationRow(
                    "주기 대사",
                    value: summary.speech.periodicIsEnabled
                        ? "\(summary.speech.periodicPhrases.count)개 · "
                            + "\(summary.speech.periodicOrder.displayName) · "
                            + speechIntervalDescription
                        : "사용 안 함 · \(summary.speech.periodicPhrases.count)개"
                )
            }

            DisclosureGroup("행동 루틴 상세") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(summary.sequences, id: \.id) { sequence in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(
                                BuiltInBehaviorPresets.displayName(
                                    for: sequence.id
                                )
                            )
                                .font(.caption.weight(.semibold))
                            Text(
                                sequence.repeats
                                    ? "전체 반복"
                                    : "한 번 재생"
                            )
                            .foregroundStyle(.secondary)
                            ForEach(
                                Array(sequence.steps.enumerated()),
                                id: \.offset
                            ) { index, step in
                                Text(
                                    "\(index + 1). \(BuiltInBehaviorPresets.motionDisplayName(for: step.motionID)) × \(step.repeatCount)"
                                )
                                .textSelection(.enabled)
                            }
                        }
                    }
                }
                .padding(.top, 6)
            }

            DisclosureGroup("자동 규칙 상세") {
                VStack(alignment: .leading, spacing: 8) {
                    if summary.automaticRules.isEmpty {
                        Text("포함된 자동 규칙이 없습니다.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(summary.automaticRules, id: \.id) { rule in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ruleConditionText(rule.condition))
                                    .textSelection(.enabled)
                                Text(
                                    "\(rule.isEnabled ? "사용" : "사용 안 함") · 우선순위 \(rule.priority) · \(BuiltInBehaviorPresets.displayName(for: rule.sequenceID))"
                                )
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .padding(.top, 6)
            }

            DisclosureGroup("이동 설정 상세") {
                VStack(alignment: .leading, spacing: 6) {
                    Grid(
                        alignment: .leading,
                        horizontalSpacing: 14,
                        verticalSpacing: 5
                    ) {
                        informationRow(
                            "이동 속도",
                            value:
                                "\(Int(summary.movement.speed.rounded())) pt/s"
                        )
                        informationRow(
                            "마우스와 거리",
                            value:
                                "\(Int(summary.movement.cursorDistance.rounded())) pt"
                        )
                        informationRow(
                            "정지 반경",
                            value:
                                "\(Int(summary.movement.stopRadius.rounded())) pt"
                        )
                        informationRow(
                            "자유 이동 대기",
                            value: dwellText(
                                summary.movement
                                    .freeRoamingDwellMilliseconds
                            )
                        )
                        informationRow(
                            "활성 앱 창 우선",
                            value: summary.movement.prefersFrontmostWindow
                                ? "사용"
                                : "사용 안 함"
                        )
                        informationRow(
                            "도망가기 평상시",
                            value:
                                summary.movement
                                    .cursorAvoidingIdleBehavior
                                    == .stationary
                                ? "가만히 있기"
                                : "자유 이동"
                        )
                        informationRow(
                            "마우스 감지 거리",
                            value:
                                "\(Int(summary.movement.cursorAvoidingDetectionDistance.rounded())) pt"
                        )
                        informationRow(
                            "도망가는 속도",
                            value:
                                "\(Int(summary.movement.cursorAvoidingSpeed.rounded())) pt/s"
                        )
                    }

                    Divider()

                    movementAnimationSummary(
                        title: "마우스 따라가기",
                        systemImage: "cursorarrow",
                        mode: .cursorFollowing,
                        animation:
                            summary.movement.cursorFollowingAnimation
                    )

                    Divider()

                    movementAnimationSummary(
                        title: "자유 이동",
                        systemImage: "arrow.triangle.2.circlepath",
                        mode: .freeRoaming,
                        animation: summary.movement.freeRoamingAnimation
                    )

                    Divider()

                    movementAnimationSummary(
                        title: "마우스 도망가기",
                        systemImage: "figure.run",
                        mode: .cursorAvoiding,
                        animation:
                            summary.movement.cursorAvoidingAnimation
                    )
                }
                .padding(.top, 6)
            }

            Label(
                "화면 위치·이동 범위·크기·투명도·클릭 통과·픽셀 표시·로그인 실행은 이 패키지에 포함되지 않습니다.",
                systemImage: "desktopcomputer"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(12)
        .background(
            .quaternary.opacity(0.35),
            in: RoundedRectangle(cornerRadius: 10)
        )
    }

    @ViewBuilder
    private func movementAnimationSummary(
        title: String,
        systemImage: String,
        mode: PetMovementMode,
        animation: MovementAnimationSettings
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Label(title, systemImage: systemImage)
                    .font(.subheadline.weight(.semibold))

                Spacer(minLength: 8)

                if summary.movement.mode == mode {
                    Text("현재 사용")
                        .foregroundStyle(.tint)
                        .font(.caption2.weight(.semibold))
                }

                Text(animationStyleName(animation))
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        .quaternary,
                        in: Capsule()
                    )
            }

            Grid(
                alignment: .leading,
                horizontalSpacing: 14,
                verticalSpacing: 5
            ) {
                informationRow(
                    "기본 이동",
                    value: animation.fallbackMotionID ?? "기존 행동 유지"
                )
                if animation.usesDirectionalMotions {
                    ForEach(displayedDirections(for: animation), id: \.self) {
                        direction in
                        informationRow(
                            directionLabel(direction),
                            value: directionMotionDescription(
                                direction,
                                animation: animation
                            )
                        )
                    }
                }
            }
        }
    }

    private var speechIntervalDescription: String {
        let seconds =
            summary.speech.periodicIntervalMilliseconds / 1_000
        if seconds >= 60, seconds.isMultiple(of: 60) {
            return "\(seconds / 60)분 간격"
        }
        return "\(seconds)초 간격"
    }

    private func animationStyleName(
        _ animation: MovementAnimationSettings
    ) -> String {
        guard animation.usesDirectionalMotions else {
            return "공통 하나"
        }
        return animation.usesDiagonalMotions
            ? "방향별 8방향"
            : "방향별 4방향"
    }

    private func directionMotionDescription(
        _ direction: MovementDirection,
        animation: MovementAnimationSettings
    ) -> String {
        if let motionID = animation.directionMotionIDs[direction] {
            return motionID
        }
        let availableDirections = animation.usesDiagonalMotions
            ? MovementDirection.cardinalCases
                + MovementDirection.diagonalCases
            : MovementDirection.cardinalCases
        if availableDirections.contains(where: {
            $0 != direction
                && animation.directionMotionIDs[$0] != nil
        }) {
            return "가까운 사용 방향 자동 선택"
        }
        if let fallbackMotionID = animation.fallbackMotionID {
            return "기본 이동 사용 · \(fallbackMotionID)"
        }
        return "기존 행동 유지"
    }

    private func displayedDirections(
        for animation: MovementAnimationSettings
    ) -> [MovementDirection] {
        animation.usesDiagonalMotions
            ? MovementDirection.cardinalCases
                + MovementDirection.diagonalCases
            : MovementDirection.cardinalCases
    }

    private func informationRow(
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

    private func movementModeName(_ mode: PetMovementMode) -> String {
        switch mode {
        case .fixed:
            "위치 고정"
        case .cursorFollowing:
            "마우스 따라가기"
        case .freeRoaming:
            "자유 이동"
        case .cursorAvoiding:
            "마우스 도망가기"
        }
    }

    private func directionLabel(_ direction: MovementDirection) -> String {
        switch direction {
        case .left:
            "왼쪽"
        case .right:
            "오른쪽"
        case .up:
            "위쪽"
        case .down:
            "아래쪽"
        case .upLeft:
            "왼쪽 위"
        case .upRight:
            "오른쪽 위"
        case .downLeft:
            "왼쪽 아래"
        case .downRight:
            "오른쪽 아래"
        }
    }

    private func ruleConditionText(_ condition: RuleCondition) -> String {
        switch condition {
        case let .application(bundleIdentifier):
            "앱: \(bundleIdentifier)"
        case let .idleAtLeast(milliseconds):
            "입력 없음: \(dwellText(milliseconds)) 이상"
        case let .unsupported(type):
            "지원하지 않는 규칙: \(type)"
        }
    }

    private func dwellText(_ milliseconds: Int64) -> String {
        let seconds = Double(milliseconds) / 1_000
        if seconds >= 60, seconds.truncatingRemainder(dividingBy: 60) == 0 {
            return "\(Int(seconds / 60))분"
        }
        if seconds.rounded() == seconds {
            return "\(Int(seconds))초"
        }
        return String(format: "%.1f초", seconds)
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
    @State private var petDescription = "MonglePet에서 사용자가 만든 펫입니다."
    @State private var animationName = ""
    @State private var frameDurationMilliseconds = 120
    @State private var loops = true
    @State private var frames: [UserPetAnimationFrameDraft] = []
    @State private var selectedFrameID: UUID?
    @State private var spriteSheetImport: SpriteSheetImportPresentation?
    @State private var imageImportErrorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(mode == .create ? "새 펫 만들기" : "펫 애니메이션 추가")
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

                    Text("개별 프레임은 512×512 px 투명 PNG를 권장합니다. 정적 PNG·WebP 스프라이트 시트도 경계를 확인한 뒤 여러 프레임으로 가져올 수 있습니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let imageImportErrorMessage {
                        Label(imageImportErrorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                    }

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
        .sheet(item: $spriteSheetImport) { presentation in
            SpriteSheetImportView(document: presentation.document) { images in
                appendSpriteImages(images)
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
                    fieldLabel("새 프레임 간격")
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
                        Text("애니메이션 프레임")
                            .font(.headline)
                        Text("프레임을 선택하면 배율·위치·재생 간격을 개별 편집할 수 있습니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        Button("개별 PNG 추가…") {
                            choosePNGs()
                        }
                        .accessibilityIdentifier("monglepet.userPet.choosePNGs")

                        Button("스프라이트 시트에서 추가…") {
                            chooseSpriteSheet()
                        }
                        .accessibilityIdentifier("monglepet.userPet.chooseSpriteSheet")
                        Divider()
                        SpriteSheetPromptCopyButton()
                    } label: {
                        Label(
                            frames.isEmpty ? "프레임 선택" : "프레임 추가",
                            systemImage: "plus"
                        )
                    }
                    .accessibilityIdentifier(
                        "monglepet.userPet.frameImportMenu"
                    )
                }

                if frames.isEmpty {
                    ContentUnavailableView(
                        "추가한 프레임이 없습니다.",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("개별 PNG 또는 정적 PNG·WebP 스프라이트 시트를 추가해 주세요.")
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
                    && !author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
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
        imageImportErrorMessage = nil
    }

    private func chooseSpriteSheet() {
        let panel = NSOpenPanel()
        panel.title = "정적 스프라이트 시트 선택"
        panel.prompt = "열기"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.allowedContentTypes = [.png, .webP]

        guard panel.runModal() == .OK, let sourceURL = panel.url else {
            return
        }
        do {
            let document = try SpriteSheetFrameExtractor().load(at: sourceURL)
            spriteSheetImport = SpriteSheetImportPresentation(document: document)
            imageImportErrorMessage = nil
        } catch {
            imageImportErrorMessage = error.localizedDescription
        }
    }

    private func appendSpriteImages(_ images: [UserPetSourceImage]) {
        let addedFrames = UserPetAnimationDraftFactory.new(
            images: images,
            durationMilliseconds: frameDurationMilliseconds,
            reference: frames.first
        )
        frames.append(contentsOf: addedFrames)
        selectedFrameID = addedFrames.first?.id ?? selectedFrameID
        imageImportErrorMessage = nil
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
            switch frame.source {
            case .existing:
                return nil
            case let .png(url):
                return UserPetSourceFrameRequest(
                    sourceURL: url,
                    durationMilliseconds: frame.durationMilliseconds,
                    placement: frame.placement
                )
            case let .image(image):
                return UserPetSourceFrameRequest(
                    image: image,
                    durationMilliseconds: frame.durationMilliseconds,
                    placement: frame.placement
                )
            }
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
        switch frame.source {
        case .existing:
            return "기존 프레임"
        case let .png(url):
            return url.lastPathComponent
        case let .image(image):
            return image.displayName
        }
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
    @State private var petDescription: String
    @State private var defaultMotionID: String

    init(item: PetLibraryItem, petLibrarySession: PetLibrarySession) {
        self.item = item
        self.petLibrarySession = petLibrarySession
        _displayName = State(initialValue: item.metadata.displayName)
        _version = State(initialValue: item.metadata.version)
        _author = State(initialValue: item.metadata.author)
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
            && item.definition.motion(id: defaultMotionID) != nil
    }

    private func save() {
        let succeeded = petLibrarySession.updateSelectedPetDetails(
            UserPetDetailsRequest(
                displayName: displayName,
                version: version,
                author: author,
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
    @State private var spriteSheetImport: SpriteSheetImportPresentation?
    @State private var imageImportErrorMessage: String?

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

                    Menu {
                        Button("개별 PNG 추가…") {
                            choosePNGs()
                        }
                        .accessibilityIdentifier("monglepet.petAnimation.addFrames")

                        Button("스프라이트 시트에서 추가…") {
                            chooseSpriteSheet()
                        }
                        .accessibilityIdentifier("monglepet.petAnimation.addSpriteSheet")
                        Divider()
                        SpriteSheetPromptCopyButton()
                    } label: {
                        Label("프레임 추가", systemImage: "plus")
                    }
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

            Text("개별 프레임은 512×512 px 투명 PNG를 권장합니다. 정적 PNG·WebP 스프라이트 시트도 경계를 확인한 뒤 추가할 수 있습니다. 각 프레임 간격은 16~60000ms입니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

                    if let imageImportErrorMessage {
                        Label(
                            imageImportErrorMessage,
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.callout)
                        .foregroundStyle(.orange)
                    }

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
        .sheet(item: $spriteSheetImport) { presentation in
            SpriteSheetImportView(document: presentation.document) { images in
                appendSpriteImages(images)
            }
        }
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
        imageImportErrorMessage = nil
    }

    private func chooseSpriteSheet() {
        let panel = NSOpenPanel()
        panel.title = "정적 스프라이트 시트 선택"
        panel.prompt = "열기"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.allowedContentTypes = [.png, .webP]

        guard panel.runModal() == .OK, let sourceURL = panel.url else {
            return
        }
        do {
            let document = try SpriteSheetFrameExtractor().load(at: sourceURL)
            spriteSheetImport = SpriteSheetImportPresentation(document: document)
            imageImportErrorMessage = nil
        } catch {
            imageImportErrorMessage = error.localizedDescription
        }
    }

    private func appendSpriteImages(_ images: [UserPetSourceImage]) {
        let addedFrames = UserPetAnimationDraftFactory.new(
            images: images,
            durationMilliseconds: 120,
            reference: frames.first
        )
        frames.append(contentsOf: addedFrames)
        selectedFrameID = addedFrames.first?.id ?? selectedFrameID
        imageImportErrorMessage = nil
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
        let sources = urls.compactMap { url -> NewFrameSource? in
            guard let image = loadImage(at: url),
                  let content = try? FrameCanvasComposer().transparentContent(in: image) else {
                return nil
            }
            return NewFrameSource(
                source: .png(url),
                image: image,
                content: content
            )
        }
        return new(
            sources: sources,
            durationMilliseconds: durationMilliseconds,
            reference: reference
        )
    }

    static func new(
        images: [UserPetSourceImage],
        durationMilliseconds: Int,
        reference: UserPetAnimationFrameDraft? = nil
    ) -> [UserPetAnimationFrameDraft] {
        let sources = images.compactMap { sourceImage -> NewFrameSource? in
            guard let content = try? FrameCanvasComposer().transparentContent(
                in: sourceImage.image
            ) else {
                return nil
            }
            return NewFrameSource(
                source: .image(sourceImage),
                image: sourceImage.image,
                content: content
            )
        }
        return new(
            sources: sources,
            durationMilliseconds: durationMilliseconds,
            reference: reference
        )
    }

    private static func new(
        sources: [NewFrameSource],
        durationMilliseconds: Int,
        reference: UserPetAnimationFrameDraft?
    ) -> [UserPetAnimationFrameDraft] {
        guard !sources.isEmpty else {
            return []
        }

        if let reference {
            let referencePlacement = reference.placement
            let targetSize = reference.renderedContentSize
            let anchorX = referencePlacement.x + targetSize.width / 2
            let anchorBottom = referencePlacement.y + targetSize.height
            return sources.compactMap { item in
                let scale = min(
                    targetSize.width / Double(item.content.image.width),
                    targetSize.height / Double(item.content.image.height)
                )
                return UserPetAnimationFrameDraft(
                    source: item.source,
                    durationMilliseconds: durationMilliseconds,
                    image: item.image,
                    canvasSize: reference.canvasSize,
                    baseScale: scale,
                    anchorX: anchorX,
                    anchorBottom: anchorBottom
                )
            }
        }

        let canvasSize = PixelSize(
            width: sources.map { $0.image.width }.max() ?? 512,
            height: sources.map { $0.image.height }.max() ?? 512
        )
        let usesSameCanvas = Set(
            sources.map { "\($0.image.width)x\($0.image.height)" }
        ).count == 1
        return sources.compactMap { item in
            let image = item.image
            let content = item.content
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
                source: item.source,
                durationMilliseconds: durationMilliseconds,
                image: image,
                canvasSize: canvasSize,
                baseScale: scale,
                anchorX: anchorX,
                anchorBottom: anchorBottom
            )
        }
    }

    private struct NewFrameSource {
        let source: UserPetAnimationFrameSource
        let image: CGImage
        let content: TransparentFrameContent
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
        ),
        loginLaunchSettings: LoginLaunchSettings(
            service: PreviewLoginLaunchService()
        ),
        runtimeControlSession: PetRuntimeControlSession()
    )
}

@MainActor
private final class PreviewLoginLaunchService: LoginLaunchServicing {
    var status: LoginLaunchStatus {
        .notRegistered
    }

    func register() throws {}
    func unregister() throws {}
    func openSystemSettings() {}
}
