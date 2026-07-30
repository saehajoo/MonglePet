import SwiftUI

struct SpeechBubbleSettingsView: View {
    @ObservedObject var settingsSession: AppSettingsSession
    let petDisplayName: String

    @State private var editorContext: SpeechPhraseEditorContext?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label("말풍선", systemImage: "text.bubble")
                        .font(.title3.weight(.semibold))
                    Text("\(petDisplayName)에게 보여 줄 대사와 나타나는 조건을 설정합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("사용 설정") {
                Toggle("말풍선 사용", isOn: enabledBinding)
                    .accessibilityIdentifier(
                        "monglepet.settings.speech.enabled"
                    )

                Stepper(
                    value: periodicIntervalSecondsBinding,
                    in: 5...3_600,
                    step: 5
                ) {
                    LabeledContent("주기 대사 간격") {
                        Text(periodicIntervalDescription)
                            .monospacedDigit()
                    }
                }
                .disabled(!speechSettings.isEnabled)
                .accessibilityIdentifier(
                    "monglepet.settings.speech.periodicInterval"
                )

                Text("주기 대사가 하나 이상 있을 때만 타이머가 동작합니다.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("등록된 대사") {
                if speechSettings.phrases.isEmpty {
                    ContentUnavailableView(
                        "등록된 대사가 없습니다",
                        systemImage: "text.bubble",
                        description: Text(
                            "주기적으로 나타나거나 행동 루틴이 시작될 때 보여 줄 대사를 추가해 보세요."
                        )
                    )
                    .frame(maxWidth: .infinity, minHeight: 130)
                } else {
                    ForEach(speechSettings.phrases) { phrase in
                        speechPhraseRow(phrase)
                    }
                }

                Button {
                    editorContext = .new
                } label: {
                    Label("대사 추가", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    speechSettings.phrases.count
                        >= AppSettingsLimits.maximumSpeechPhrases
                )
                .accessibilityIdentifier(
                    "monglepet.settings.speech.addPhrase"
                )
            }

            Section {
                Label(
                    "말풍선은 펫과 함께 움직이며 마우스 클릭을 가로채지 않습니다.",
                    systemImage: "cursorarrow.rays"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .sheet(item: $editorContext) { context in
            SpeechPhraseEditorView(
                phrase: context.phrase,
                sequences: settingsSession.settings.sequences,
                onCancel: {
                    editorContext = nil
                },
                onSave: { phrase in
                    save(phrase, replacing: context.phrase?.id)
                    editorContext = nil
                }
            )
        }
    }

    private var speechSettings: PetSpeechSettings {
        settingsSession.settings.speechSettings
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { speechSettings.isEnabled },
            set: { isEnabled in
                _ = settingsSession.setSpeechSettings(
                    PetSpeechSettings(
                        isEnabled: isEnabled,
                        periodicIntervalMilliseconds:
                            speechSettings.periodicIntervalMilliseconds,
                        phrases: speechSettings.phrases
                    )
                )
            }
        )
    }

    private var periodicIntervalSecondsBinding: Binding<Int> {
        Binding(
            get: {
                Int(speechSettings.periodicIntervalMilliseconds / 1_000)
            },
            set: { seconds in
                _ = settingsSession.setSpeechSettings(
                    PetSpeechSettings(
                        isEnabled: speechSettings.isEnabled,
                        periodicIntervalMilliseconds: Int64(seconds) * 1_000,
                        phrases: speechSettings.phrases
                    )
                )
            }
        )
    }

    private var periodicIntervalDescription: String {
        let seconds = speechSettings.periodicIntervalMilliseconds / 1_000
        if seconds >= 60, seconds.isMultiple(of: 60) {
            return "\(seconds / 60)분"
        }
        return "\(seconds)초"
    }

    private func triggerDescription(_ trigger: PetSpeechTrigger) -> String {
        switch trigger {
        case .periodic:
            return "주기적으로"
        case let .sequence(sequenceID):
            return "‘\(BuiltInBehaviorPresets.displayName(for: sequenceID))’ 시작 시"
        }
    }

    private func speechPhraseRow(
        _ phrase: PetSpeechPhrase
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(phrase.text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 10) {
                    Label(
                        triggerDescription(phrase.trigger),
                        systemImage: "bolt"
                    )
                    Label(
                        "\(phrase.displayDurationMilliseconds / 1_000)초",
                        systemImage: "clock"
                    )
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Menu {
                Button("수정") {
                    editorContext = .existing(phrase)
                }
                Button("삭제", role: .destructive) {
                    remove(phrase)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .imageScale(.large)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("대사 메뉴")
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }

    private func save(
        _ phrase: PetSpeechPhrase,
        replacing phraseID: UUID?
    ) {
        var phrases = speechSettings.phrases
        if let phraseID,
           let index = phrases.firstIndex(where: { $0.id == phraseID }) {
            phrases[index] = phrase
        } else {
            phrases.append(phrase)
        }
        _ = settingsSession.setSpeechSettings(
            PetSpeechSettings(
                isEnabled: speechSettings.isEnabled,
                periodicIntervalMilliseconds:
                    speechSettings.periodicIntervalMilliseconds,
                phrases: phrases
            )
        )
    }

    private func remove(_ phrase: PetSpeechPhrase) {
        _ = settingsSession.setSpeechSettings(
            PetSpeechSettings(
                isEnabled: speechSettings.isEnabled,
                periodicIntervalMilliseconds:
                    speechSettings.periodicIntervalMilliseconds,
                phrases: speechSettings.phrases.filter { $0.id != phrase.id }
            )
        )
    }
}

private enum SpeechPhraseEditorContext: Identifiable {
    case new
    case existing(PetSpeechPhrase)

    var id: String {
        switch self {
        case .new:
            return "new"
        case let .existing(phrase):
            return phrase.id.uuidString
        }
    }

    var phrase: PetSpeechPhrase? {
        guard case let .existing(phrase) = self else {
            return nil
        }
        return phrase
    }
}

private struct SpeechPhraseEditorView: View {
    private enum TriggerKind: Hashable {
        case periodic
        case sequence
    }

    let originalPhrase: PetSpeechPhrase?
    let sequences: [BehaviorSequence]
    let onCancel: () -> Void
    let onSave: (PetSpeechPhrase) -> Void

    @State private var text: String
    @State private var durationSeconds: Int
    @State private var triggerKind: TriggerKind
    @State private var sequenceID: String

    init(
        phrase: PetSpeechPhrase?,
        sequences: [BehaviorSequence],
        onCancel: @escaping () -> Void,
        onSave: @escaping (PetSpeechPhrase) -> Void
    ) {
        originalPhrase = phrase
        self.sequences = sequences
        self.onCancel = onCancel
        self.onSave = onSave
        _text = State(initialValue: phrase?.text ?? "")
        _durationSeconds = State(
            initialValue: Int(
                (phrase?.displayDurationMilliseconds
                    ?? AppSettingsLimits
                        .defaultSpeechDisplayDurationMilliseconds) / 1_000
            )
        )
        switch phrase?.trigger {
        case let .sequence(sequenceID):
            _triggerKind = State(initialValue: .sequence)
            _sequenceID = State(initialValue: sequenceID)
        case .periodic, nil:
            _triggerKind = State(initialValue: .periodic)
            _sequenceID = State(initialValue: sequences.first?.id ?? "")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(originalPhrase == nil ? "대사 추가" : "대사 수정")
                .font(.title2.weight(.semibold))

            VStack(alignment: .leading, spacing: 6) {
                Text("대사")
                    .font(.headline)
                TextField(
                    "펫이 말할 내용을 입력해 주세요.",
                    text: $text,
                    axis: .vertical
                )
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
                Text(
                    "\(normalizedText.count) / "
                        + "\(AppSettingsLimits.maximumSpeechTextLength)"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }

            Picker("나타나는 때", selection: $triggerKind) {
                Text("주기적으로").tag(TriggerKind.periodic)
                Text("행동 루틴 시작 시").tag(TriggerKind.sequence)
            }
            .pickerStyle(.segmented)

            if triggerKind == .sequence {
                Picker("행동 루틴", selection: $sequenceID) {
                    ForEach(sequences) { sequence in
                        Text(
                            BuiltInBehaviorPresets.displayName(
                                for: sequence.id
                            )
                        )
                        .tag(sequence.id)
                    }
                }
                .disabled(sequences.isEmpty)
            }

            Stepper(value: $durationSeconds, in: 1...30) {
                LabeledContent("표시 시간") {
                    Text("\(durationSeconds)초")
                        .monospacedDigit()
                }
            }

            HStack {
                Spacer()
                Button("취소", role: .cancel, action: onCancel)
                Button("저장") {
                    onSave(
                        PetSpeechPhrase(
                            id: originalPhrase?.id ?? UUID(),
                            text: normalizedText,
                            displayDurationMilliseconds:
                                Int64(durationSeconds) * 1_000,
                            trigger: selectedTrigger
                        )
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .padding(24)
        .frame(width: 480)
    }

    private var normalizedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedTrigger: PetSpeechTrigger {
        switch triggerKind {
        case .periodic:
            return .periodic
        case .sequence:
            return .sequence(sequenceID)
        }
    }

    private var canSave: Bool {
        !normalizedText.isEmpty
            && normalizedText.count <= AppSettingsLimits.maximumSpeechTextLength
            && (triggerKind == .periodic
                || sequences.contains(where: { $0.id == sequenceID }))
    }
}
