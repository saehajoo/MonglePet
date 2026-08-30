import AppKit
import SwiftUI
import UniformTypeIdentifiers

nonisolated enum BehaviorMotionCatalog {
    static func identifiers(
        for petDefinition: PetDefinition,
        including currentMotionID: String
    ) -> [String] {
        var identifiers = [PetMotionReference.currentPetDefault]
        identifiers.append(contentsOf: petDefinition.motions
            .map(\.id)
            .filter { $0 != petDefinition.defaultMotionID })
        if !currentMotionID.isEmpty, !identifiers.contains(currentMotionID) {
            identifiers.append(currentMotionID)
        }
        return identifiers
    }
}

private struct ApplicationRuleTargetPicker: View {
    @Binding var bundleIdentifier: String
    @ObservedObject var applicationCatalog: ApplicationCatalogSession
    let accessibilityPrefix: String
    let onCommit: (String) -> Void

    @State private var selectedApplication: ApplicationChoice?
    @State private var isChoosingApplication = false
    @State private var isShowingDirectInput = false
    @State private var directInputDraft = ""
    @State private var errorMessage: String?

    init(
        bundleIdentifier: Binding<String>,
        applicationCatalog: ApplicationCatalogSession,
        accessibilityPrefix: String,
        onCommit: @escaping (String) -> Void = { _ in }
    ) {
        _bundleIdentifier = bundleIdentifier
        self.applicationCatalog = applicationCatalog
        self.accessibilityPrefix = accessibilityPrefix
        self.onCommit = onCommit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("대상 앱")
                .font(.subheadline.weight(.semibold))

            GroupBox {
                selectedApplicationView
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(
                        maxWidth: .infinity,
                        minHeight: 44,
                        alignment: .leading
                    )
            }

            Menu {
                Menu {
                    if applicationCatalog.runningApplications.isEmpty {
                        Text("선택할 수 있는 실행 중인 앱이 없습니다.")
                    } else {
                        ForEach(
                            applicationCatalog.runningApplications
                        ) { application in
                            Button {
                                select(application)
                            } label: {
                                applicationMenuLabel(for: application)
                            }
                        }
                    }

                    Divider()
                    Button("목록 새로고침", action: refreshRunningApplications)
                } label: {
                    Label("열려 있는 앱", systemImage: "macwindow")
                }

                Button {
                    isChoosingApplication = true
                } label: {
                    Label(
                        "설치된 앱 파일 선택…",
                        systemImage: "folder"
                    )
                }

                Button {
                    directInputDraft = normalizedBundleIdentifier
                    isShowingDirectInput = true
                } label: {
                    Label(
                        "Bundle Identifier 직접 입력…",
                        systemImage: "keyboard"
                    )
                }
            } label: {
                Label("대상 앱 선택…", systemImage: "app.badge.checkmark")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .menuStyle(.button)
            .controlSize(.large)
            .accessibilityIdentifier(
                "\(accessibilityPrefix).selectionMenu"
            )

            Text("열려 있는 앱, 설치된 .app 파일 또는 Bundle Identifier로 선택할 수 있습니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier(
                        "\(accessibilityPrefix).applicationError"
                    )
            }
        }
        .fileImporter(
            isPresented: $isChoosingApplication,
            allowedContentTypes: [.applicationBundle],
            allowsMultipleSelection: false,
            onCompletion: handleApplicationSelection
        )
        .popover(isPresented: $isShowingDirectInput, arrowEdge: .bottom) {
            directInputPopover
        }
        .onAppear(perform: synchronizeSelectedApplication)
        .onChange(of: bundleIdentifier) {
            synchronizeSelectedApplication()
        }
        .onChange(of: applicationCatalog.runningApplications) {
            synchronizeSelectedApplication()
        }
    }

    private var directInputPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bundle Identifier 직접 입력")
                .font(.headline)

            TextField(
                "예: com.apple.dt.Xcode",
                text: $directInputDraft
            )
            .textFieldStyle(.roundedBorder)
            .fontDesign(.monospaced)
            .onSubmit(commitDirectInput)
            .accessibilityIdentifier(
                "\(accessibilityPrefix).bundleIdentifier"
            )

            Text("목록에 없는 앱을 정확한 식별자로 등록할 때 사용합니다.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()

                Button("취소", role: .cancel) {
                    isShowingDirectInput = false
                }

                Button("적용") {
                    commitDirectInput()
                }
                .buttonStyle(.borderedProminent)
                .disabled(normalizedDirectInputDraft.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    @ViewBuilder
    private var selectedApplicationView: some View {
        if let selectedApplication,
           selectedApplication.bundleIdentifier == normalizedBundleIdentifier {
            HStack(spacing: 10) {
                applicationIcon(for: selectedApplication)

                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedApplication.displayName)
                        .font(.headline)
                    Text(selectedApplication.bundleIdentifier)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(
                "\(accessibilityPrefix).selectedApplication"
            )
        } else if !normalizedBundleIdentifier.isEmpty {
            LabeledContent(
                "선택한 Bundle Identifier",
                value: normalizedBundleIdentifier
            )
            .accessibilityIdentifier(
                "\(accessibilityPrefix).selectedApplication"
            )
        } else {
            Text("실행 중인 앱을 고르거나 설치된 .app 파일을 선택해 주세요.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func applicationMenuLabel(
        for application: ApplicationChoice
    ) -> some View {
        if let iconData = application.iconData,
           let icon = NSImage(data: iconData) {
            Label {
                Text(
                    "\(application.displayName) — "
                        + application.bundleIdentifier
                )
            } icon: {
                Image(nsImage: icon)
            }
        } else {
            Text(
                "\(application.displayName) — "
                    + application.bundleIdentifier
            )
        }
    }

    @ViewBuilder
    private func applicationIcon(
        for application: ApplicationChoice
    ) -> some View {
        if let iconData = application.iconData,
           let icon = NSImage(data: iconData) {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
        } else if let bundleURL = application.bundleURL {
            Image(nsImage: NSWorkspace.shared.icon(forFile: bundleURL.path))
                .resizable()
                .scaledToFit()
                .frame(width: 32, height: 32)
        } else {
            Image(systemName: "app")
                .font(.title2)
                .frame(width: 32, height: 32)
        }
    }

    private var normalizedBundleIdentifier: String {
        bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedDirectInputDraft: String {
        directInputDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func refreshRunningApplications() {
        applicationCatalog.refresh()
        synchronizeSelectedApplication()
    }

    private func synchronizeSelectedApplication() {
        guard selectedApplication?.bundleIdentifier
                != normalizedBundleIdentifier else {
            return
        }
        selectedApplication = applicationCatalog.runningApplications.first {
            $0.bundleIdentifier == normalizedBundleIdentifier
        }
    }

    private func select(_ application: ApplicationChoice) {
        errorMessage = nil
        selectedApplication = application
        bundleIdentifier = application.bundleIdentifier
        onCommit(application.bundleIdentifier)
    }

    private func commitDirectInput() {
        let normalizedIdentifier = normalizedDirectInputDraft
        guard !normalizedIdentifier.isEmpty else {
            return
        }
        errorMessage = nil
        bundleIdentifier = normalizedIdentifier
        synchronizeSelectedApplication()
        onCommit(normalizedIdentifier)
        isShowingDirectInput = false
    }

    private func handleApplicationSelection(
        _ result: Result<[URL], Error>
    ) {
        do {
            guard let url = try result.get().first else {
                return
            }
            select(try applicationCatalog.application(at: url))
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct HorizontalIntegerAdjuster: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let suffix: String
    let accessibilityPrefix: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)

            Spacer()

            Button {
                value = max(value - 1, range.lowerBound)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.bordered)
            .disabled(value <= range.lowerBound)
            .help("\(title) 줄이기")
            .accessibilityLabel("\(title) 줄이기")
            .accessibilityIdentifier("\(accessibilityPrefix).decrement")

            HStack(spacing: 3) {
                TextField(
                    title,
                    value: clampedValue,
                    format: .number
                )
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .monospacedDigit()
                .frame(width: 72)
                .accessibilityIdentifier("\(accessibilityPrefix).value")

                if !suffix.isEmpty {
                    Text(suffix)
                        .foregroundStyle(.secondary)
                }
            }

            Button {
                value = min(value + 1, range.upperBound)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.bordered)
            .disabled(value >= range.upperBound)
            .help("\(title) 늘리기")
            .accessibilityLabel("\(title) 늘리기")
            .accessibilityIdentifier("\(accessibilityPrefix).increment")
        }
    }

    private var clampedValue: Binding<Int> {
        Binding(
            get: { value },
            set: {
                value = min(max($0, range.lowerBound), range.upperBound)
            }
        )
    }
}

struct BehaviorSequencesSettingsView: View {
    @ObservedObject var settingsSession: AppSettingsSession
    let petDefinition: PetDefinition
    let petDisplayName: String
    @State private var selectedSequenceID = BuiltInBehaviorPresets.defaultSequenceID
    @State private var showsSequenceCreator = false

    var body: some View {
        Form {
            editNotice

            Section {
                LabeledContent("설정 대상 펫", value: petDisplayName)
                    .accessibilityIdentifier(
                        "monglepet.settings.behaviorPetName"
                    )
            }

            Section("편집할 행동") {
                HStack {
                    Picker("선택한 행동", selection: $selectedSequenceID) {
                        ForEach(settingsSession.settings.sequences) { sequence in
                            Text(sequence.displayName)
                                .tag(sequence.id)
                        }
                    }
                    .accessibilityIdentifier("monglepet.settings.sequencePicker")

                    Button("삭제", role: .destructive) {
                        if settingsSession.removeBehaviorSequence(id: selectedSequenceID) {
                            selectAvailableSequence()
                        }
                    }
                    .disabled(
                        BehaviorSettingsEditor.protectedSequenceIDs.contains(selectedSequenceID)
                    )
                    .accessibilityIdentifier("monglepet.settings.deleteSequence")

                    Button {
                        settingsSession.clearBehaviorEditError()
                        showsSequenceCreator = true
                    } label: {
                        Label("행동 추가", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("monglepet.settings.addSequence")
                }

                Text("행동은 하나 이상의 애니메이션 단계로 구성됩니다. 규칙 설정, 표시 및 이동, 쓰다듬기에서 같은 행동을 선택할 수 있습니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let sequence = selectedSequence {
                Section("행동 이름") {
                    TextField("행동 이름", text: displayNameBinding(for: sequence))
                        .disabled(
                            BehaviorSettingsEditor.protectedSequenceIDs
                                .contains(sequence.id)
                        )
                }

                Section("‘\(selectedSequenceDisplayName)’ 재생 설정") {
                    Toggle("마지막 단계 후 처음부터 반복", isOn: repeatsBinding(for: sequence))
                }

                Section("‘\(selectedSequenceDisplayName)’ 애니메이션 단계") {
                    ForEach(Array(sequence.steps.indices), id: \.self) { index in
                        BehaviorStepEditorRow(
                            settingsSession: settingsSession,
                            sequenceID: sequence.id,
                            index: index,
                            availableMotionIDs: availableMotionIDs(for: sequence.steps[index]),
                            canMoveUp: index > sequence.steps.startIndex,
                            canMoveDown: index < sequence.steps.index(before: sequence.steps.endIndex),
                            canDelete: sequence.steps.count > 1
                        )
                    }

                    Button {
                        settingsSession.addBehaviorStep(to: sequence.id)
                    } label: {
                        Label("단계 추가", systemImage: "plus")
                    }
                    .accessibilityIdentifier("monglepet.settings.addStep")
                }
            }

            Section {
                Text("‘\(petDefinition.displayName)’가 가진 애니메이션을 순서대로 조합합니다. 행동 이름을 바꿔도 자동 규칙과 이동 설정의 연결은 유지됩니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .disabled(!settingsSession.isWritingEnabled)
        .onAppear(perform: selectAvailableSequence)
        .onChange(of: settingsSession.settings.sequences.map(\.id)) {
            selectAvailableSequence()
        }
        .sheet(isPresented: $showsSequenceCreator) {
            NewBehaviorSequenceSheet(
                motionIDs: BehaviorMotionCatalog.identifiers(
                    for: petDefinition,
                    including: PetMotionReference.currentPetDefault
                ),
                errorMessage: settingsSession.behaviorEditErrorMessage
            ) { name, motionID, repeats in
                if settingsSession.addBehaviorSequence(
                    named: name,
                    initialMotionID: motionID,
                    repeats: repeats
                ) {
                    selectedSequenceID = settingsSession.settings
                        .sequences.last?.id ?? selectedSequenceID
                    showsSequenceCreator = false
                }
            }
        }
    }

    @ViewBuilder
    private var editNotice: some View {
        if let message = settingsSession.behaviorEditErrorMessage {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.callout)
                .accessibilityIdentifier("monglepet.settings.behaviorEditError")
        }
    }

    private var selectedSequence: BehaviorSequence? {
        settingsSession.settings.sequences.first { $0.id == selectedSequenceID }
    }

    private var selectedSequenceDisplayName: String {
        selectedSequence?.displayName ?? selectedSequenceID
    }

    private func displayNameBinding(
        for sequence: BehaviorSequence
    ) -> Binding<String> {
        Binding(
            get: {
                settingsSession.settings.sequences.first(where: {
                    $0.id == sequence.id
                })?.displayName ?? sequence.displayName
            },
            set: { settingsSession.renameBehaviorSequence(id: sequence.id, to: $0) }
        )
    }

    private func repeatsBinding(for sequence: BehaviorSequence) -> Binding<Bool> {
        Binding(
            get: {
                settingsSession.settings.sequences
                    .first(where: { $0.id == sequence.id })?.repeats
                    ?? sequence.repeats
            },
            set: { settingsSession.setBehaviorSequenceRepeats($0, for: sequence.id) }
        )
    }

    private func availableMotionIDs(for step: BehaviorStep) -> [String] {
        BehaviorMotionCatalog.identifiers(
            for: petDefinition,
            including: step.motionID
        )
    }

    private func selectAvailableSequence() {
        guard !settingsSession.settings.sequences.contains(where: { $0.id == selectedSequenceID }) else {
            return
        }
        selectedSequenceID = settingsSession.settings.sequences
            .first(where: { $0.id == BuiltInBehaviorPresets.defaultSequenceID })?.id
            ?? settingsSession.settings.sequences.first?.id
            ?? ""
    }
}

private struct NewBehaviorSequenceSheet: View {
    let motionIDs: [String]
    let errorMessage: String?
    let onCreate: (String, String, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var motionID = PetMotionReference.currentPetDefault
    @State private var repeats = true

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("새 행동 추가")
                .font(.title2.bold())
            Text("이름과 첫 애니메이션을 먼저 정한 뒤, 생성된 행동에서 단계를 더 추가할 수 있습니다.")
                .foregroundStyle(.secondary)

            Form {
                TextField("행동 이름", text: $name)
                    .accessibilityIdentifier(
                        "monglepet.settings.newSequenceName"
                    )
                Picker("첫 애니메이션", selection: $motionID) {
                    ForEach(motionIDs, id: \.self) { id in
                        Text(BuiltInBehaviorPresets.motionDisplayName(for: id))
                            .tag(id)
                    }
                }
                Toggle("마지막 단계 후 처음부터 반복", isOn: $repeats)
            }
            .formStyle(.grouped)

            if let errorMessage {
                Label(
                    errorMessage,
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.callout)
                .foregroundStyle(.orange)
                .accessibilityIdentifier(
                    "monglepet.settings.newSequenceError"
                )
            }

            HStack {
                Spacer()
                Button("취소") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("만들고 편집") {
                    onCreate(name, motionID, repeats)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(
                    name.trimmingCharacters(in: .whitespacesAndNewlines)
                        .isEmpty
                )
            }
        }
        .padding(24)
        .frame(width: 480)
        .onAppear {
            if !motionIDs.contains(motionID) {
                motionID = motionIDs.first
                    ?? PetMotionReference.currentPetDefault
            }
        }
    }
}

private struct BehaviorStepEditorRow: View {
    @ObservedObject var settingsSession: AppSettingsSession
    let sequenceID: String
    let index: Int
    let availableMotionIDs: [String]
    let canMoveUp: Bool
    let canMoveDown: Bool
    let canDelete: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(index + 1)단계")
                    .font(.headline)
                Spacer()
                Button {
                    settingsSession.moveBehaviorStep(
                        in: sequenceID,
                        from: index,
                        to: index - 1
                    )
                } label: {
                    Image(systemName: "arrow.up")
                }
                .disabled(!canMoveUp)
                .help("위로 이동")

                Button {
                    settingsSession.moveBehaviorStep(
                        in: sequenceID,
                        from: index,
                        to: index + 1
                    )
                } label: {
                    Image(systemName: "arrow.down")
                }
                .disabled(!canMoveDown)
                .help("아래로 이동")

                Button(role: .destructive) {
                    settingsSession.removeBehaviorStep(from: sequenceID, at: index)
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(!canDelete)
                .help("단계 삭제")
            }

            Picker("펫 애니메이션", selection: motionIDBinding) {
                ForEach(availableMotionIDs, id: \.self) { motionID in
                    Text(BuiltInBehaviorPresets.motionDisplayName(for: motionID))
                        .tag(motionID)
                }
            }

            Stepper(
                value: repeatCountBinding,
                in: 1...AppSettingsLimits.maximumRepeatCount
            ) {
                Text("반복 횟수: \(repeatCountBinding.wrappedValue)회")
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("monglepet.settings.step.\(index)")
    }

    private var currentStep: BehaviorStep? {
        guard let sequence = settingsSession.settings.sequences.first(where: { $0.id == sequenceID }),
              sequence.steps.indices.contains(index) else {
            return nil
        }
        return sequence.steps[index]
    }

    private var motionIDBinding: Binding<String> {
        Binding(
            get: {
                currentStep?.motionID ?? PetMotionReference.currentPetDefault
            },
            set: { update(motionID: $0) }
        )
    }

    private var repeatCountBinding: Binding<Int> {
        Binding(
            get: { currentStep?.repeatCount ?? 1 },
            set: { update(repeatCount: $0) }
        )
    }

    private func update(
        motionID: String? = nil,
        repeatCount: Int? = nil
    ) {
        guard let currentStep else {
            return
        }
        settingsSession.updateBehaviorStep(
            sequenceID: sequenceID,
            index: index,
            motionID: motionID ?? currentStep.motionID,
            repeatCount: repeatCount ?? currentStep.repeatCount
        )
    }
}

struct AutomaticRulesSettingsView: View {
    @ObservedObject var settingsSession: AppSettingsSession
    let petDisplayName: String
    @StateObject private var applicationCatalog = ApplicationCatalogSession()
    @State private var bundleIdentifier = ""
    @State private var applicationSequenceID = BuiltInBehaviorPresets.defaultSequenceID
    @State private var idleSeconds = 60
    @State private var idleSequenceID = BuiltInBehaviorPresets.defaultSequenceID

    var body: some View {
        Form {
            if let message = settingsSession.behaviorEditErrorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
                    .accessibilityIdentifier("monglepet.settings.behaviorEditError")
            }

            Section {
                LabeledContent("설정 대상 펫", value: petDisplayName)
                    .accessibilityIdentifier(
                        "monglepet.settings.automaticRulesPetName"
                    )
            }
            Section("규칙 및 이동 우선순위") {
                ForEach(priorityOrder.indices, id: \.self) { index in
                    let category = priorityOrder[index]
                    HStack(spacing: 12) {
                        Image(systemName: prioritySystemImage(for: category))
                            .foregroundStyle(.secondary)
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(priorityTitle(for: category))
                                .font(.callout.weight(.semibold))
                            Text(prioritySubtitle(for: category))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)

                        Text("\(index + 1)순위")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()

                        Button {
                            movePriority(at: index, by: -1)
                        } label: {
                            Image(systemName: "arrow.up")
                        }
                        .disabled(index == priorityOrder.startIndex)
                        .help("우선순위 올리기")
                        .accessibilityIdentifier(
                            "monglepet.settings.priority.\(category.rawValue).up"
                        )

                        Button {
                            movePriority(at: index, by: 1)
                        } label: {
                            Image(systemName: "arrow.down")
                        }
                        .disabled(index == priorityOrder.index(before: priorityOrder.endIndex))
                        .help("우선순위 내리기")
                        .accessibilityIdentifier(
                            "monglepet.settings.priority.\(category.rawValue).down"
                        )
                    }
                    .padding(.vertical, 4)
                }

                Text("위에 있는 항목부터 적용합니다. 규칙이 이동보다 앞에 있으면 펫이 현재 위치에서 멈추고 해당 규칙의 행동을 표시합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("입력 없음 규칙") {
                Toggle("입력 없음 규칙 사용", isOn: idleRuleEnabledBinding)
                    .accessibilityIdentifier(
                        "monglepet.settings.idleRuleEnabled"
                    )
                HorizontalIntegerAdjuster(
                    title: "입력이 없었던 시간",
                    value: $idleSeconds,
                    range: 1...86_400,
                    suffix: "초",
                    accessibilityPrefix:
                        "monglepet.settings.newIdleRule.idleSeconds"
                )
                sequencePicker("행동", selection: $idleSequenceID)
                Button("입력 없음 규칙 변경") {
                    saveIdleRule()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("monglepet.settings.changeIdleRule")
            }

            Section("앱 사용 규칙 추가") {
                ApplicationRuleTargetPicker(
                    bundleIdentifier: $bundleIdentifier,
                    applicationCatalog: applicationCatalog,
                    accessibilityPrefix: "monglepet.settings.newApplicationRule"
                )
                sequencePicker("행동", selection: $applicationSequenceID)
                Button("앱 규칙 추가", action: addApplicationRule)
                    .buttonStyle(.borderedProminent)
                    .disabled(bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("monglepet.settings.addApplicationRule")
            }

            Section("등록된 앱 사용 규칙") {
                if applicationRules.isEmpty {
                    Text("등록된 앱 사용 규칙이 없습니다.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(applicationRules) { rule in
                        AutomaticRuleEditorRow(
                            settingsSession: settingsSession,
                            applicationCatalog: applicationCatalog,
                            rule: rule
                        )
                    }
                }
            }

        }
        .formStyle(.grouped)
        .disabled(!settingsSession.isWritingEnabled)
        .onAppear(perform: selectAvailableSequences)
        .onAppear(perform: applicationCatalog.refresh)
        .onChange(of: settingsSession.settings.sequences.map(\.id)) {
            selectAvailableSequences()
        }
    }

    @ViewBuilder
    private func sequencePicker(_ title: String, selection: Binding<String>) -> some View {
        Picker(title, selection: selection) {
            ForEach(settingsSession.settings.sequences) { sequence in
                Text(sequence.displayName)
                    .tag(sequence.id)
            }
        }
    }

    private var applicationRules: [AutomaticRule] {
        settingsSession.settings.automaticRules.filter {
            if case .application = $0.condition { return true }
            return false
        }
    }

    private var idleRule: AutomaticRule? {
        settingsSession.settings.automaticRules.first {
            if case .idleAtLeast = $0.condition { return true }
            return false
        }
    }

    private var idleRuleEnabledBinding: Binding<Bool> {
        Binding(
            get: { idleRule?.isEnabled ?? false },
            set: { isEnabled in
                settingsSession.setIdleRule(
                    seconds: idleSeconds,
                    sequenceID: idleSequenceID,
                    isEnabled: isEnabled
                )
            }
        )
    }

    private var priorityOrder: [AutomaticRuleCategory] {
        settingsSession.settings.automaticRulePriorityOrder
    }

    private func movePriority(at index: Int, by offset: Int) {
        let destination = index + offset
        guard priorityOrder.indices.contains(index),
              priorityOrder.indices.contains(destination) else {
            return
        }
        var order = priorityOrder
        order.swapAt(index, destination)
        settingsSession.setAutomaticRulePriorityOrder(order)
    }

    private func priorityTitle(
        for category: AutomaticRuleCategory
    ) -> String {
        switch category {
        case .movement:
            "이동"
        case .idle:
            "입력 없음 규칙"
        case .application:
            "앱 사용 규칙"
        }
    }

    private func prioritySubtitle(
        for category: AutomaticRuleCategory
    ) -> String {
        switch category {
        case .movement:
            "펫이 움직이는 동안 설정한 이동 행동"
        case .idle:
            "설정한 시간 동안 입력이 없을 때의 행동"
        case .application:
            "현재 사용 중인 앱에 등록된 행동"
        }
    }

    private func prioritySystemImage(
        for category: AutomaticRuleCategory
    ) -> String {
        switch category {
        case .movement:
            "arrow.up.and.down.and.arrow.left.and.right"
        case .idle:
            "clock"
        case .application:
            "app"
        }
    }

    private func addApplicationRule() {
        let normalizedIdentifier = bundleIdentifier
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if settingsSession.addApplicationRule(
            bundleIdentifier: normalizedIdentifier,
            sequenceID: applicationSequenceID
        ) {
            bundleIdentifier = ""
        }
    }

    private func saveIdleRule() {
        settingsSession.setIdleRule(
            seconds: idleSeconds,
            sequenceID: idleSequenceID,
            isEnabled: idleRule?.isEnabled ?? false
        )
    }

    private func selectAvailableSequences() {
        let ids = Set(settingsSession.settings.sequences.map(\.id))
        let fallback = settingsSession.settings.sequences.first?.id ?? ""
        if !ids.contains(applicationSequenceID) {
            applicationSequenceID = fallback
        }
        if !ids.contains(idleSequenceID) {
            idleSequenceID = fallback
        }
        if let idleRule {
            idleSequenceID = idleRule.sequenceID
            if case let .idleAtLeast(milliseconds) = idleRule.condition {
                idleSeconds = max(Int(milliseconds / 1_000), 1)
            }
        }
    }
}

private struct AutomaticRuleEditorRow: View {
    @ObservedObject var settingsSession: AppSettingsSession
    @ObservedObject var applicationCatalog: ApplicationCatalogSession
    let rule: AutomaticRule
    @State private var bundleIdentifier: String
    @State private var isExpanded = false

    init(
        settingsSession: AppSettingsSession,
        applicationCatalog: ApplicationCatalogSession,
        rule: AutomaticRule
    ) {
        self.settingsSession = settingsSession
        self.applicationCatalog = applicationCatalog
        self.rule = rule
        if case let .application(bundleIdentifier) = rule.condition {
            _bundleIdentifier = State(initialValue: bundleIdentifier)
        } else {
            _bundleIdentifier = State(initialValue: "")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Toggle("규칙 활성", isOn: enabledBinding)
                    .labelsHidden()
                    .help(rule.isEnabled ? "규칙 끄기" : "규칙 켜기")
                    .disabled(isUnsupported)

                Button {
                    isExpanded.toggle()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: conditionSystemImage)
                            .foregroundStyle(conditionTint)
                            .frame(width: 22)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(conditionTitle)
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(conditionSubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .layoutPriority(1)

                        Spacer(minLength: 8)

                        Image(
                            systemName:
                                isExpanded ? "chevron.up" : "chevron.down"
                        )
                        .foregroundStyle(.secondary)
                        .frame(width: 12)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(isExpanded ? "세부 설정 접기" : "세부 설정 펼치기")
                .accessibilityLabel(
                    "\(conditionTitle), "
                        + (isExpanded ? "세부 설정 접기" : "세부 설정 펼치기")
                )
                .accessibilityIdentifier(
                    "monglepet.settings.rule.\(rule.id.uuidString).expand"
                )

                Button(role: .destructive) {
                    settingsSession.removeAutomaticRule(id: rule.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .help("규칙 삭제")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isExpanded {
                Divider()
                    .padding(.vertical, 12)

                VStack(alignment: .leading, spacing: 12) {
                    Picker("행동", selection: sequenceIDBinding) {
                        ForEach(
                            settingsSession.settings.sequences
                        ) { sequence in
                            Text(sequence.displayName)
                            .tag(sequence.id)
                        }
                    }

                    conditionEditor
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(.separator.opacity(0.7), lineWidth: 1)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("monglepet.settings.rule.\(rule.id.uuidString)")
    }

    private var conditionTitle: String {
        switch rule.condition {
        case let .application(bundleIdentifier):
            return applicationCatalog.runningApplications.first {
                $0.bundleIdentifier == bundleIdentifier
            }?.displayName ?? bundleIdentifier
        case let .idleAtLeast(milliseconds):
            return "\(max(Int(milliseconds / 1_000), 1))초 동안 입력 없음"
        case let .unsupported(type):
            return "지원하지 않는 조건: \(type)"
        }
    }

    private var conditionSubtitle: String {
        let sequenceName = settingsSession.settings.sequences.first(where: {
            $0.id == rule.sequenceID
        })?.displayName ?? rule.sequenceID

        switch rule.condition {
        case let .application(bundleIdentifier):
            if applicationCatalog.runningApplications.contains(where: {
                $0.bundleIdentifier == bundleIdentifier
                    && $0.displayName != bundleIdentifier
            }) {
                return "\(bundleIdentifier) · 행동: \(sequenceName)"
            }
            return "행동: \(sequenceName)"
        case .idleAtLeast:
            return "행동: \(sequenceName)"
        case .unsupported:
            return "이 규칙은 실행되지 않습니다."
        }
    }

    private var conditionSystemImage: String {
        switch rule.condition {
        case .application:
            "app"
        case .idleAtLeast:
            "clock"
        case .unsupported:
            "exclamationmark.triangle"
        }
    }

    private var conditionTint: Color {
        if isUnsupported {
            return .orange
        }
        return rule.isEnabled ? .accentColor : .secondary
    }

    @ViewBuilder
    private var conditionEditor: some View {
        switch rule.condition {
        case .application:
            ApplicationRuleTargetPicker(
                bundleIdentifier: $bundleIdentifier,
                applicationCatalog: applicationCatalog,
                accessibilityPrefix:
                    "monglepet.settings.rule.\(rule.id.uuidString).application",
                onCommit: { applyBundleIdentifier($0) }
            )
        case .idleAtLeast:
            HorizontalIntegerAdjuster(
                title: "입력이 없었던 시간",
                value: idleSecondsBinding,
                range: 1...86_400,
                suffix: "초",
                accessibilityPrefix:
                    "monglepet.settings.rule.\(rule.id.uuidString).idleSeconds"
            )
        case let .unsupported(type):
            Text("지원하지 않는 조건: \(type)")
                .foregroundStyle(.secondary)
        }
    }

    private var isUnsupported: Bool {
        if case .unsupported = rule.condition {
            return true
        }
        return false
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { rule.isEnabled },
            set: { replace(isEnabled: $0) }
        )
    }

    private var priorityBinding: Binding<Int> {
        Binding(
            get: { rule.priority },
            set: { replace(priority: $0) }
        )
    }

    private var sequenceIDBinding: Binding<String> {
        Binding(
            get: { rule.sequenceID },
            set: { replace(sequenceID: $0) }
        )
    }

    private var idleSecondsBinding: Binding<Int> {
        Binding(
            get: {
                guard case let .idleAtLeast(milliseconds) = rule.condition else {
                    return 1
                }
                return max(Int(milliseconds / 1_000), 1)
            },
            set: {
                replace(condition: .idleAtLeast(milliseconds: Int64($0) * 1_000))
            }
        )
    }

    private func applyBundleIdentifier(_ selectedIdentifier: String? = nil) {
        replace(
            condition: .application(
                bundleIdentifier: (selectedIdentifier ?? bundleIdentifier)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
        )
    }

    private func replace(
        isEnabled: Bool? = nil,
        priority: Int? = nil,
        condition: RuleCondition? = nil,
        sequenceID: String? = nil
    ) {
        settingsSession.updateAutomaticRule(
            AutomaticRule(
                id: rule.id,
                isEnabled: isEnabled ?? rule.isEnabled,
                priority: priority ?? rule.priority,
                condition: condition ?? rule.condition,
                sequenceID: sequenceID ?? rule.sequenceID
            )
        )
    }
}
