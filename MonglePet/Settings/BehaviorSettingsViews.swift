import SwiftUI

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
                TextField("Bundle identifier (예: com.apple.dt.Xcode)", text: $bundleIdentifier)
                    .onSubmit(addApplicationRule)
                    .accessibilityIdentifier("monglepet.settings.bundleIdentifier")
                sequencePicker("행동 루틴", selection: $applicationSequenceID)
                Button("앱 규칙 추가", action: addApplicationRule)
                    .disabled(bundleIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("monglepet.settings.addApplicationRule")
            }

            Section("유휴 규칙 추가") {
                Stepper(value: $idleMinutes, in: 1...1_440) {
                    Text("입력이 없었던 시간: \(idleMinutes)분")
                        .monospacedDigit()
                }
                sequencePicker("행동 루틴", selection: $idleSequenceID)
                Button("유휴 규칙 추가") {
                    settingsSession.addIdleRule(
                        minutes: idleMinutes,
                        sequenceID: idleSequenceID
                    )
                }
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
    let rule: AutomaticRule
    @State private var bundleIdentifier: String

    init(settingsSession: AppSettingsSession, rule: AutomaticRule) {
        self.settingsSession = settingsSession
        self.rule = rule
        if case let .application(bundleIdentifier) = rule.condition {
            _bundleIdentifier = State(initialValue: bundleIdentifier)
        } else {
            _bundleIdentifier = State(initialValue: "")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("활성", isOn: enabledBinding)
                    .disabled(isUnsupported)
                Spacer()
                Button("삭제", role: .destructive) {
                    settingsSession.removeAutomaticRule(id: rule.id)
                }
            }

            Stepper(value: priorityBinding, in: -10_000...10_000) {
                Text("우선순위: \(rule.priority)")
                    .monospacedDigit()
            }

            Picker("행동 루틴", selection: sequenceIDBinding) {
                ForEach(settingsSession.settings.sequences) { sequence in
                    Text(BuiltInBehaviorPresets.displayName(for: sequence.id))
                        .tag(sequence.id)
                }
            }

            conditionEditor
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("monglepet.settings.rule.\(rule.id.uuidString)")
    }

    @ViewBuilder
    private var conditionEditor: some View {
        switch rule.condition {
        case .application:
            HStack {
                TextField("Bundle identifier", text: $bundleIdentifier)
                    .onSubmit(applyBundleIdentifier)
                Button("적용", action: applyBundleIdentifier)
            }
        case let .idleAtLeast(milliseconds):
            Stepper(value: idleMinutesBinding, in: 1...1_440) {
                Text("입력이 없었던 시간: \(max(Int(milliseconds / 60_000), 1))분")
                    .monospacedDigit()
            }
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

    private func applyBundleIdentifier() {
        replace(
            condition: .application(
                bundleIdentifier: bundleIdentifier
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
