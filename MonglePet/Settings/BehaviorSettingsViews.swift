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
    @State private var newSequenceName = ""

    var body: some View {
        Form {
            editNotice

            Section {
                LabeledContent("설정 대상 펫", value: petDisplayName)
                    .accessibilityIdentifier(
                        "monglepet.settings.behaviorPetName"
                    )
            }

            Section("행동 루틴") {
                HStack {
                    Picker("편집할 루틴", selection: $selectedSequenceID) {
                        ForEach(settingsSession.settings.sequences) { sequence in
                            Text(BuiltInBehaviorPresets.displayName(for: sequence.id))
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
                }

                HStack {
                    TextField("새 행동 루틴 이름", text: $newSequenceName)
                        .onSubmit(addSequence)
                        .accessibilityIdentifier("monglepet.settings.newSequenceName")
                    Button("추가", action: addSequence)
                        .disabled(newSequenceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("monglepet.settings.addSequence")
                }
            }

            if let sequence = selectedSequence {
                Section("재생 설정") {
                    Toggle("마지막 단계 후 처음부터 반복", isOn: repeatsBinding(for: sequence))
                }

                Section("애니메이션 단계") {
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
                Text("‘\(petDefinition.displayName)’가 가진 애니메이션을 순서대로 조합합니다. 루틴 이름은 생성 후에는 바꿀 수 없습니다.")
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

    private func addSequence() {
        if settingsSession.addBehaviorSequence(named: newSequenceName) {
            selectedSequenceID = newSequenceName.trimmingCharacters(in: .whitespacesAndNewlines)
            newSequenceName = ""
        }
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
    @State private var idleMinutes = 1
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

            Section("앱 사용 규칙 추가") {
                ApplicationRuleTargetPicker(
                    bundleIdentifier: $bundleIdentifier,
                    applicationCatalog: applicationCatalog,
                    accessibilityPrefix: "monglepet.settings.newApplicationRule"
                )
                sequencePicker("행동 루틴", selection: $applicationSequenceID)
                Button("앱 규칙 추가", action: addApplicationRule)
                    .buttonStyle(.borderedProminent)
                    .disabled(bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("monglepet.settings.addApplicationRule")
            }

            Section("입력 없음 규칙 추가") {
                HorizontalIntegerAdjuster(
                    title: "입력이 없었던 시간",
                    value: $idleMinutes,
                    range: 1...1_440,
                    suffix: "분",
                    accessibilityPrefix:
                        "monglepet.settings.newIdleRule.idleMinutes"
                )
                sequencePicker("행동 루틴", selection: $idleSequenceID)
                Button("입력 없음 규칙 추가") {
                    settingsSession.addIdleRule(
                        minutes: idleMinutes,
                        sequenceID: idleSequenceID
                    )
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("monglepet.settings.addIdleRule")
            }

            Section("등록된 규칙") {
                if settingsSession.settings.automaticRules.isEmpty {
                    Text("등록된 자동 규칙이 없습니다.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(settingsSession.settings.automaticRules) { rule in
                        AutomaticRuleEditorRow(
                            settingsSession: settingsSession,
                            applicationCatalog: applicationCatalog,
                            rule: rule
                        )
                    }
                }
            }

            Section {
                Text("숫자가 큰 우선순위부터 검사하며, 조건을 만족하는 첫 번째 규칙을 사용합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                Text(BuiltInBehaviorPresets.displayName(for: sequence.id))
                    .tag(sequence.id)
            }
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

    private func selectAvailableSequences() {
        let ids = Set(settingsSession.settings.sequences.map(\.id))
        let fallback = settingsSession.settings.sequences.first?.id ?? ""
        if !ids.contains(applicationSequenceID) {
            applicationSequenceID = fallback
        }
        if !ids.contains(idleSequenceID) {
            idleSequenceID = fallback
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

                        Text("우선순위 \(rule.priority)")
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .monospacedDigit()
                            .fixedSize()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.quaternary, in: Capsule())

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
                    HorizontalIntegerAdjuster(
                        title: "우선순위",
                        value: priorityBinding,
                        range: -10_000...10_000,
                        suffix: "",
                        accessibilityPrefix:
                            "monglepet.settings.rule."
                            + "\(rule.id.uuidString).priority"
                    )

                    Picker("행동 루틴", selection: sequenceIDBinding) {
                        ForEach(
                            settingsSession.settings.sequences
                        ) { sequence in
                            Text(
                                BuiltInBehaviorPresets.displayName(
                                    for: sequence.id
                                )
                            )
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
            return "\(max(Int(milliseconds / 60_000), 1))분 동안 입력 없음"
        case let .unsupported(type):
            return "지원하지 않는 조건: \(type)"
        }
    }

    private var conditionSubtitle: String {
        let sequenceName = BuiltInBehaviorPresets.displayName(
            for: rule.sequenceID
        )

        switch rule.condition {
        case let .application(bundleIdentifier):
            if applicationCatalog.runningApplications.contains(where: {
                $0.bundleIdentifier == bundleIdentifier
                    && $0.displayName != bundleIdentifier
            }) {
                return "\(bundleIdentifier) · 행동 루틴: \(sequenceName)"
            }
            return "행동 루틴: \(sequenceName)"
        case .idleAtLeast:
            return "행동 루틴: \(sequenceName)"
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
                value: idleMinutesBinding,
                range: 1...1_440,
                suffix: "분",
                accessibilityPrefix:
                    "monglepet.settings.rule.\(rule.id.uuidString).idleMinutes"
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

    private var idleMinutesBinding: Binding<Int> {
        Binding(
            get: {
                guard case let .idleAtLeast(milliseconds) = rule.condition else {
                    return 1
                }
                return max(Int(milliseconds / 60_000), 1)
            },
            set: {
                replace(condition: .idleAtLeast(milliseconds: Int64($0) * 60_000))
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
