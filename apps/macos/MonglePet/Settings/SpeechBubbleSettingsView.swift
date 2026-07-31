import AppKit
import SwiftUI

struct SpeechBubbleSettingsView: View {
    @ObservedObject var settingsSession: AppSettingsSession
    let petItem: PetLibraryItem
    let petDisplayName: String

    @State private var editorContext: SpeechPhraseEditorContext?
    @State private var isEditingTheme = false

    var body: some View {
        Form {
            Section {
                LabeledContent("설정 대상 펫", value: petDisplayName)
                    .accessibilityIdentifier(
                        "monglepet.settings.speech.petName"
                    )
            }

            Section("사용 설정") {
                Toggle("말풍선 사용", isOn: enabledBinding)
                    .accessibilityIdentifier(
                        "monglepet.settings.speech.enabled"
                    )

                Picker(
                    "행동이 바뀌었는데 연결된 대사가 없을 때",
                    selection: behaviorChangePolicyBinding
                ) {
                    ForEach(
                        PetSpeechBehaviorChangePolicy.allCases,
                        id: \.self
                    ) { policy in
                        Text(policy.displayName).tag(policy)
                    }
                }
                .disabled(!speechSettings.isEnabled)
            }

            Section("행동 대사") {
                if speechSettings.behaviorPhrases.isEmpty {
                    ContentUnavailableView(
                        "등록된 행동 대사가 없습니다",
                        systemImage: "bolt.bubble",
                        description: Text(
                            "행동 루틴이 시작될 때 우선해서 보여 줄 대사를 추가해 보세요."
                        )
                    )
                    .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    ForEach(speechSettings.behaviorPhrases) { phrase in
                        speechPhraseRow(phrase)
                    }
                }

                Button {
                    editorContext = .new(.behavior)
                } label: {
                    Label("행동 대사 추가", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    !speechSettings.isEnabled
                        || settingsSession.settings.sequences.isEmpty
                        || speechSettings.phrases.count
                            >= AppSettingsLimits.maximumSpeechPhrases
                )
                .accessibilityIdentifier(
                    "monglepet.settings.speech.addBehaviorPhrase"
                )
            }

            Section("주기 대사") {
                Toggle("주기 대사 사용", isOn: periodicEnabledBinding)
                    .disabled(!speechSettings.isEnabled)

                Picker(
                    "재생 순서",
                    selection: periodicOrderBinding
                ) {
                    ForEach(
                        PetSpeechPeriodicOrder.allCases,
                        id: \.self
                    ) { order in
                        Text(order.displayName).tag(order)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(
                    !speechSettings.isEnabled
                        || !speechSettings.periodicIsEnabled
                )

                HStack(spacing: 12) {
                    Text("다음 대사까지 기다리기")

                    Slider(
                        value: periodicIntervalSliderBinding,
                        in: 5...3_600,
                        step: 5
                    )

                    Text(periodicIntervalDescription)
                        .monospacedDigit()
                        .frame(width: 64, alignment: .trailing)
                }
                .disabled(
                    !speechSettings.isEnabled
                        || !speechSettings.periodicIsEnabled
                )
                .accessibilityIdentifier(
                    "monglepet.settings.speech.periodicInterval"
                )

                Text(
                    "시간 지정 대사는 말풍선이 숨은 뒤부터 기다리고, 유지 대사는 표시된 시점부터 기다린 뒤 다음 대사로 교체합니다."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                if speechSettings.periodicPhrases.isEmpty {
                    ContentUnavailableView(
                        "등록된 주기 대사가 없습니다",
                        systemImage: "clock.badge.questionmark",
                        description: Text(
                            "행동 대사가 없을 때 차례로 보여 줄 대사를 추가해 보세요."
                        )
                    )
                    .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    ForEach(speechSettings.periodicPhrases) { phrase in
                        speechPhraseRow(phrase)
                    }
                }

                Button {
                    editorContext = .new(.periodic)
                } label: {
                    Label("주기 대사 추가", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    !speechSettings.isEnabled
                        || speechSettings.phrases.count
                        >= AppSettingsLimits.maximumSpeechPhrases
                )
                .accessibilityIdentifier(
                    "monglepet.settings.speech.addPeriodicPhrase"
                )
            }

            Section("말풍선 모양과 위치") {
                SpeechBubblePlacementPreview(
                    petItem: petItem,
                    text: previewText,
                    theme: speechSettings.theme,
                    placement: speechSettings.placement,
                    height: 300
                )
                .accessibilityIdentifier(
                    "monglepet.settings.speech.themePreview"
                )

                HStack {
                    LabeledContent(
                        "색상",
                        value: speechSettings.theme.colorStyle.displayName
                    )

                    Spacer()

                    Button("모양과 위치 편집") {
                        isEditingTheme = true
                    }
                    .accessibilityIdentifier(
                        "monglepet.settings.speech.editTheme"
                    )
                }
            }

            Section {
                Label(
                    "말풍선은 펫과 함께 움직이며 마우스 클릭을 가로채지 않습니다. 대사와 조건은 현재 펫에 저장됩니다.",
                    systemImage: "cursorarrow.rays"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .disabled(!settingsSession.isWritingEnabled)
        .accessibilityIdentifier("monglepet.settings.speech.root")
        .sheet(isPresented: $isEditingTheme) {
            SpeechBubbleThemeEditorView(
                theme: speechSettings.theme,
                placement: speechSettings.placement,
                petItem: petItem,
                onCancel: {
                    isEditingTheme = false
                },
                onSave: { theme, placement in
                    updateSpeech(theme: theme, placement: placement)
                    isEditingTheme = false
                }
            )
        }
        .sheet(item: $editorContext) { context in
            SpeechPhraseEditorView(
                phrase: context.phrase,
                kind: context.kind,
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

    private var previewText: String {
        speechSettings.phrases.first?.text ?? "안녕하세요! 오늘도 함께할게요."
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { speechSettings.isEnabled },
            set: { isEnabled in
                _ = settingsSession.setSpeechSettings(
                    PetSpeechSettings(
                        isEnabled: isEnabled,
                        periodicIsEnabled:
                            speechSettings.periodicIsEnabled,
                        periodicIntervalMilliseconds:
                            speechSettings.periodicIntervalMilliseconds,
                        periodicOrder: speechSettings.periodicOrder,
                        behaviorChangePolicy:
                            speechSettings.behaviorChangePolicy,
                        phrases: speechSettings.phrases,
                        theme: speechSettings.theme,
                        placement: speechSettings.placement
                    )
                )
            }
        )
    }

    private var periodicEnabledBinding: Binding<Bool> {
        Binding(
            get: { speechSettings.periodicIsEnabled },
            set: { isEnabled in
                _ = settingsSession.setSpeechSettings(
                    PetSpeechSettings(
                        isEnabled: speechSettings.isEnabled,
                        periodicIsEnabled: isEnabled,
                        periodicIntervalMilliseconds:
                            speechSettings.periodicIntervalMilliseconds,
                        periodicOrder: speechSettings.periodicOrder,
                        behaviorChangePolicy:
                            speechSettings.behaviorChangePolicy,
                        phrases: speechSettings.phrases,
                        theme: speechSettings.theme,
                        placement: speechSettings.placement
                    )
                )
            }
        )
    }

    private var periodicOrderBinding: Binding<PetSpeechPeriodicOrder> {
        Binding(
            get: { speechSettings.periodicOrder },
            set: { order in
                _ = settingsSession.setSpeechSettings(
                    PetSpeechSettings(
                        isEnabled: speechSettings.isEnabled,
                        periodicIsEnabled:
                            speechSettings.periodicIsEnabled,
                        periodicIntervalMilliseconds:
                            speechSettings.periodicIntervalMilliseconds,
                        periodicOrder: order,
                        behaviorChangePolicy:
                            speechSettings.behaviorChangePolicy,
                        phrases: speechSettings.phrases,
                        theme: speechSettings.theme,
                        placement: speechSettings.placement
                    )
                )
            }
        )
    }

    private var behaviorChangePolicyBinding:
        Binding<PetSpeechBehaviorChangePolicy>
    {
        Binding(
            get: { speechSettings.behaviorChangePolicy },
            set: { policy in
                _ = settingsSession.setSpeechSettings(
                    PetSpeechSettings(
                        isEnabled: speechSettings.isEnabled,
                        periodicIsEnabled:
                            speechSettings.periodicIsEnabled,
                        periodicIntervalMilliseconds:
                            speechSettings.periodicIntervalMilliseconds,
                        periodicOrder: speechSettings.periodicOrder,
                        behaviorChangePolicy: policy,
                        phrases: speechSettings.phrases,
                        theme: speechSettings.theme,
                        placement: speechSettings.placement
                    )
                )
            }
        )
    }

    private var periodicIntervalSliderBinding: Binding<Double> {
        Binding(
            get: {
                Double(speechSettings.periodicIntervalMilliseconds) / 1_000
            },
            set: { seconds in
                _ = settingsSession.setSpeechSettings(
                    PetSpeechSettings(
                        isEnabled: speechSettings.isEnabled,
                        periodicIsEnabled:
                            speechSettings.periodicIsEnabled,
                        periodicIntervalMilliseconds:
                            Int64(seconds.rounded()) * 1_000,
                        periodicOrder: speechSettings.periodicOrder,
                        behaviorChangePolicy:
                            speechSettings.behaviorChangePolicy,
                        phrases: speechSettings.phrases,
                        theme: speechSettings.theme,
                        placement: speechSettings.placement
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

    private func displayDescription(
        _ phrase: PetSpeechPhrase
    ) -> String {
        switch phrase.displayMode {
        case .timed:
            "\(phrase.displayDurationMilliseconds / 1_000)초"
        case .untilNextPhrase:
            "다음 대사까지"
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
                        displayDescription(phrase),
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
            .menuIndicator(.hidden)
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
                periodicIsEnabled:
                    speechSettings.periodicIsEnabled
                        || (phrase.trigger == .periodic
                            && speechSettings.periodicPhrases.isEmpty),
                periodicIntervalMilliseconds:
                    speechSettings.periodicIntervalMilliseconds,
                periodicOrder: speechSettings.periodicOrder,
                behaviorChangePolicy:
                    speechSettings.behaviorChangePolicy,
                phrases: phrases,
                theme: speechSettings.theme,
                placement: speechSettings.placement
            )
        )
    }

    private func remove(_ phrase: PetSpeechPhrase) {
        _ = settingsSession.setSpeechSettings(
            PetSpeechSettings(
                isEnabled: speechSettings.isEnabled,
                periodicIsEnabled:
                    speechSettings.periodicIsEnabled,
                periodicIntervalMilliseconds:
                    speechSettings.periodicIntervalMilliseconds,
                periodicOrder: speechSettings.periodicOrder,
                behaviorChangePolicy:
                    speechSettings.behaviorChangePolicy,
                phrases: speechSettings.phrases.filter { $0.id != phrase.id },
                theme: speechSettings.theme,
                placement: speechSettings.placement
            )
        )
    }

    private func updateSpeech(
        theme: PetSpeechBubbleTheme,
        placement: PetSpeechBubblePlacementSettings
    ) {
        _ = settingsSession.setSpeechSettings(
            PetSpeechSettings(
                isEnabled: speechSettings.isEnabled,
                periodicIsEnabled:
                    speechSettings.periodicIsEnabled,
                periodicIntervalMilliseconds:
                    speechSettings.periodicIntervalMilliseconds,
                periodicOrder: speechSettings.periodicOrder,
                behaviorChangePolicy:
                    speechSettings.behaviorChangePolicy,
                phrases: speechSettings.phrases,
                theme: theme,
                placement: placement
            )
        )
    }
}

private struct SpeechBubbleThemeEditorView: View {
    let originalTheme: PetSpeechBubbleTheme
    let originalPlacement: PetSpeechBubblePlacementSettings
    let petItem: PetLibraryItem
    let onCancel: () -> Void
    let onSave: (
        PetSpeechBubbleTheme,
        PetSpeechBubblePlacementSettings
    ) -> Void

    @State private var colorStyle: PetSpeechBubbleColorStyle
    @State private var customBackgroundColor: Color
    @State private var customTextColor: Color
    @State private var backgroundOpacity: Double
    @State private var fontSize: Double
    @State private var contentPadding: Double
    @State private var cornerRadius: Double
    @State private var showsTail: Bool
    @State private var tailAlignment: PetSpeechBubbleTailAlignment
    @State private var preferredPosition:
        PetSpeechBubblePreferredPosition
    @State private var horizontalOffset: Double
    @State private var bubbleGap: Double

    init(
        theme: PetSpeechBubbleTheme,
        placement: PetSpeechBubblePlacementSettings,
        petItem: PetLibraryItem,
        onCancel: @escaping () -> Void,
        onSave: @escaping (
            PetSpeechBubbleTheme,
            PetSpeechBubblePlacementSettings
        ) -> Void
    ) {
        originalTheme = theme
        originalPlacement = placement
        self.petItem = petItem
        self.onCancel = onCancel
        self.onSave = onSave
        _colorStyle = State(initialValue: theme.colorStyle)
        _customBackgroundColor = State(
            initialValue: Self.color(theme.customBackgroundColor)
        )
        _customTextColor = State(
            initialValue: Self.color(theme.customTextColor)
        )
        _backgroundOpacity = State(
            initialValue: theme.backgroundOpacity
        )
        _fontSize = State(initialValue: theme.fontSize)
        _contentPadding = State(initialValue: theme.contentPadding)
        _cornerRadius = State(initialValue: theme.cornerRadius)
        _showsTail = State(initialValue: theme.showsTail)
        _tailAlignment = State(initialValue: theme.tailAlignment)
        _preferredPosition = State(
            initialValue: placement.preferredPosition
        )
        _horizontalOffset = State(
            initialValue: placement.horizontalOffset
        )
        _bubbleGap = State(initialValue: placement.gap)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("말풍선 모양과 위치 편집")
                        .font(.title2.weight(.semibold))
                    Text("미리보기를 확인한 뒤 현재 펫에 적용합니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("기본값으로 복원", action: restoreDefaults)
            }
            .padding(.horizontal, 24)
            .padding(.top, 22)
            .padding(.bottom, 14)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    placementPreview

                    GroupBox("색상") {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("색상 스타일", selection: $colorStyle) {
                                ForEach(
                                    PetSpeechBubbleColorStyle.allCases,
                                    id: \.self
                                ) { style in
                                    Text(style.displayName).tag(style)
                                }
                            }

                            if colorStyle == .custom {
                                ColorPicker(
                                    "배경색",
                                    selection: $customBackgroundColor,
                                    supportsOpacity: false
                                )
                                ColorPicker(
                                    "글자색",
                                    selection: $customTextColor,
                                    supportsOpacity: false
                                )

                                Label(
                                    contrastDescription,
                                    systemImage: hasAccessibleContrast
                                        ? "checkmark.circle.fill"
                                        : "exclamationmark.triangle.fill"
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    hasAccessibleContrast
                                        ? Color.secondary
                                        : Color.orange
                                )
                            }

                            themeSlider(
                                title: "배경 불투명도",
                                value: $backgroundOpacity,
                                range: 0.65...1,
                                step: 0.05,
                                valueText:
                                    "\(Int((backgroundOpacity * 100).rounded()))%"
                            )
                        }
                        .padding(8)
                    }

                    GroupBox("크기와 모양") {
                        VStack(alignment: .leading, spacing: 14) {
                            themeSlider(
                                title: "글자 크기",
                                value: $fontSize,
                                range: 11...24,
                                step: 1,
                                valueText: "\(Int(fontSize.rounded()))pt"
                            )
                            themeSlider(
                                title: "안쪽 여백",
                                value: $contentPadding,
                                range: 6...24,
                                step: 1,
                                valueText:
                                    "\(Int(contentPadding.rounded()))pt"
                            )
                            themeSlider(
                                title: "모서리",
                                value: $cornerRadius,
                                range: 0...28,
                                step: 1,
                                valueText:
                                    "\(Int(cornerRadius.rounded()))pt"
                            )
                        }
                        .padding(8)
                    }

                    GroupBox("꼬리") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("말풍선 꼬리 표시", isOn: $showsTail)

                            if showsTail {
                                Picker(
                                    "꼬리 위치",
                                    selection: $tailAlignment
                                ) {
                                    ForEach(
                                        PetSpeechBubbleTailAlignment.allCases,
                                        id: \.self
                                    ) { alignment in
                                        Text(alignment.displayName)
                                            .tag(alignment)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }
                        }
                        .padding(8)
                    }

                    GroupBox("배치") {
                        VStack(alignment: .leading, spacing: 14) {
                            Picker(
                                "펫을 기준으로",
                                selection: $preferredPosition
                            ) {
                                ForEach(
                                    PetSpeechBubblePreferredPosition.allCases,
                                    id: \.self
                                ) { position in
                                    Text(position.displayName).tag(position)
                                }
                            }
                            .pickerStyle(.segmented)

                            themeSlider(
                                title: "좌우 위치",
                                value: $horizontalOffset,
                                range: -160...160,
                                step: 4,
                                valueText:
                                    "\(Int(horizontalOffset.rounded()))pt"
                            )
                            themeSlider(
                                title: "펫과 간격",
                                value: $bubbleGap,
                                range: 0...64,
                                step: 2,
                                valueText:
                                    "\(Int(bubbleGap.rounded()))pt"
                            )

                            Text(
                                "화면 밖으로 나가면 위치와 꼬리를 자동으로 보정합니다."
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(8)
                    }
                }
                .padding(24)
            }

            Divider()

            HStack {
                Spacer()
                Button("취소", role: .cancel, action: onCancel)
                Button("적용") {
                    onSave(draftTheme, draftPlacement)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!draftTheme.isValid || !draftPlacement.isValid)
                .accessibilityIdentifier(
                    "monglepet.settings.speech.applyTheme"
                )
            }
            .padding(18)
        }
        .frame(width: 720, height: 780)
    }

    private var placementPreview: some View {
        SpeechBubblePlacementPreview(
            petItem: petItem,
            text: "안녕하세요! 이 모습으로 표시돼요.",
            theme: draftTheme,
            placement: draftPlacement,
            height: 300
        )
    }

    private var draftTheme: PetSpeechBubbleTheme {
        PetSpeechBubbleTheme(
            colorStyle: colorStyle,
            customBackgroundColor: backgroundComponents,
            customTextColor: textComponents,
            backgroundOpacity: backgroundOpacity,
            fontSize: fontSize,
            contentPadding: contentPadding,
            cornerRadius: cornerRadius,
            showsTail: showsTail,
            tailAlignment: tailAlignment
        )
    }

    private var draftPlacement: PetSpeechBubblePlacementSettings {
        PetSpeechBubblePlacementSettings(
            preferredPosition: preferredPosition,
            horizontalOffset: horizontalOffset,
            gap: bubbleGap
        )
    }

    private var backgroundComponents: PetSpeechColor {
        Self.components(
            customBackgroundColor,
            fallback: originalTheme.customBackgroundColor
        )
    }

    private var textComponents: PetSpeechColor {
        Self.components(
            customTextColor,
            fallback: originalTheme.customTextColor
        )
    }

    private var contrastRatio: Double {
        backgroundComponents.contrastRatio(with: textComponents)
    }

    private var hasAccessibleContrast: Bool {
        contrastRatio
            >= AppSettingsLimits.minimumSpeechBubbleTextContrastRatio
    }

    private var contrastDescription: String {
        String(
            format: "글자 대비 %.1f:1 · 최소 4.5:1",
            contrastRatio
        )
    }

    private func themeSlider(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        valueText: String
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(width: 104, alignment: .leading)
            Slider(value: value, in: range, step: step)
            Text(valueText)
                .monospacedDigit()
                .frame(width: 56, alignment: .trailing)
        }
    }

    private func restoreDefaults() {
        let defaults = PetSpeechBubbleTheme.default
        colorStyle = defaults.colorStyle
        customBackgroundColor = Self.color(
            defaults.customBackgroundColor
        )
        customTextColor = Self.color(defaults.customTextColor)
        backgroundOpacity = defaults.backgroundOpacity
        fontSize = defaults.fontSize
        contentPadding = defaults.contentPadding
        cornerRadius = defaults.cornerRadius
        showsTail = defaults.showsTail
        tailAlignment = defaults.tailAlignment
        preferredPosition =
            PetSpeechBubblePlacementSettings.default.preferredPosition
        horizontalOffset =
            PetSpeechBubblePlacementSettings.default.horizontalOffset
        bubbleGap = PetSpeechBubblePlacementSettings.default.gap
    }

    private static func color(_ color: PetSpeechColor) -> Color {
        Color(
            .sRGB,
            red: color.red,
            green: color.green,
            blue: color.blue
        )
    }

    private static func components(
        _ color: Color,
        fallback: PetSpeechColor
    ) -> PetSpeechColor {
        guard
            let converted = NSColor(color).usingColorSpace(.sRGB)
        else {
            return fallback
        }
        return PetSpeechColor(
            red: Double(converted.redComponent),
            green: Double(converted.greenComponent),
            blue: Double(converted.blueComponent)
        )
    }
}

private struct SpeechBubblePlacementPreview: View {
    let petItem: PetLibraryItem
    let text: String
    let theme: PetSpeechBubbleTheme
    let placement: PetSpeechBubblePlacementSettings
    let height: Double

    var body: some View {
        GeometryReader { geometry in
            let appliedOffset = clampedHorizontalOffset(
                availableWidth: geometry.size.width
            )
            let isHorizontallyAdjusted =
                abs(appliedOffset - placement.horizontalOffset) > 0.5

            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.quaternary.opacity(0.18))

                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Label(
                            "현재 펫과의 위치",
                            systemImage: "rectangle.and.hand.point.up.left"
                        )
                        .font(.caption.weight(.semibold))

                        Spacer()

                        if isHorizontallyAdjusted {
                            Label(
                                "경계 보정",
                                systemImage: "arrow.left.and.right"
                            )
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.secondary)
                            .help(
                                "말풍선이 잘리지 않도록 미리보기 경계 안으로 조정했습니다."
                            )
                        }

                        Text(positionDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.top, 11)

                    previewContent(horizontalOffset: appliedOffset)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(.separator.opacity(0.45), lineWidth: 1)
            }
            .clipShape(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("현재 펫과 말풍선 위치 미리보기")
    }

    @ViewBuilder
    private func previewContent(horizontalOffset: Double) -> some View {
        let gap = min(
            max(placement.gap, AppSettingsLimits.minimumSpeechBubbleGap),
            AppSettingsLimits.maximumSpeechBubbleGap
        )

        if placement.preferredPosition == .below {
            VStack(spacing: gap) {
                petPreview
                bubblePreview(
                    tailEdge: .top,
                    horizontalOffset: horizontalOffset
                )
            }
        } else {
            VStack(spacing: gap) {
                bubblePreview(
                    tailEdge: .bottom,
                    horizontalOffset: horizontalOffset
                )
                petPreview
            }
        }
    }

    private func bubblePreview(
        tailEdge: PetSpeechBubbleTailEdge,
        horizontalOffset: Double
    ) -> some View {
        PetSpeechBubbleContentView(
            text: text,
            theme: theme,
            tailEdge: tailEdge,
            tailCenterOffset: abs(horizontalOffset) > 0.001
                ? -horizontalOffset
                : nil
        )
        .offset(x: horizontalOffset)
    }

    private var petPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.background.opacity(0.5))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            .secondary.opacity(0.28),
                            style: StrokeStyle(
                                lineWidth: 1,
                                dash: [5, 4]
                            )
                        )
                }

            Image(systemName: "pawprint.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.tertiary)

            PetAnimationPreviewView(
                item: petItem,
                motionID:
                    petItem.definition.defaultMotion?.id
                        ?? petItem.definition.defaultMotionID,
                playsAnimation: false
            )
            .padding(6)
        }
        .frame(width: 112, height: 112)
        .accessibilityLabel("\(petItem.metadata.displayName) 정지 미리보기")
    }

    private var positionDescription: String {
        let position = switch placement.preferredPosition {
        case .automatic:
            "자동 · 위쪽 미리보기"
        case .above:
            "위쪽"
        case .below:
            "아래쪽"
        }
        return "\(position) · 간격 \(Int(placement.gap.rounded()))pt"
    }

    private func clampedHorizontalOffset(
        availableWidth: Double
    ) -> Double {
        let estimatedBubbleHalfWidth = 172.0
        let sidePadding = 16.0
        let maximumMagnitude = max(
            0,
            (availableWidth / 2)
                - estimatedBubbleHalfWidth
                - sidePadding
        )
        return min(
            max(placement.horizontalOffset, -maximumMagnitude),
            maximumMagnitude
        )
    }
}

private enum SpeechPhraseEditorContext: Identifiable {
    case new(SpeechPhraseEditorKind)
    case existing(PetSpeechPhrase)

    var id: String {
        switch self {
        case let .new(kind):
            return "new-\(kind.id)"
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

    var kind: SpeechPhraseEditorKind {
        switch self {
        case let .new(kind):
            kind
        case let .existing(phrase):
            phrase.trigger == .periodic ? .periodic : .behavior
        }
    }
}

private enum SpeechPhraseEditorKind {
    case behavior
    case periodic

    var id: String {
        switch self {
        case .behavior: "behavior"
        case .periodic: "periodic"
        }
    }
}

private struct SpeechPhraseEditorView: View {
    let originalPhrase: PetSpeechPhrase?
    let kind: SpeechPhraseEditorKind
    let sequences: [BehaviorSequence]
    let onCancel: () -> Void
    let onSave: (PetSpeechPhrase) -> Void

    @State private var text: String
    @State private var durationSeconds: Int
    @State private var displayMode: PetSpeechDisplayMode
    @State private var sequenceID: String

    init(
        phrase: PetSpeechPhrase?,
        kind: SpeechPhraseEditorKind,
        sequences: [BehaviorSequence],
        onCancel: @escaping () -> Void,
        onSave: @escaping (PetSpeechPhrase) -> Void
    ) {
        originalPhrase = phrase
        self.kind = kind
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
        _displayMode = State(
            initialValue: phrase?.displayMode ?? .timed
        )
        switch phrase?.trigger {
        case let .sequence(sequenceID):
            _sequenceID = State(initialValue: sequenceID)
        case .periodic, nil:
            _sequenceID = State(initialValue: sequences.first?.id ?? "")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(editorTitle)
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

            if kind == .behavior {
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

            Picker("표시 방식", selection: $displayMode) {
                ForEach(PetSpeechDisplayMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if displayMode == .timed {
                HStack(spacing: 12) {
                    Text("표시 시간")

                    Slider(
                        value: durationSecondsSliderBinding,
                        in: 1...30,
                        step: 1
                    )

                    Text("\(durationSeconds)초")
                        .monospacedDigit()
                        .frame(width: 48, alignment: .trailing)
                }
            } else {
                Text(
                    kind == .behavior
                        ? "현재 행동이 유지되는 동안 표시하며, 행동 전환 정책이나 새 대사에 따라 교체됩니다."
                        : "다음 주기 대사나 행동 대사가 나타날 때까지 표시됩니다."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
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
                            trigger: selectedTrigger,
                            displayMode: displayMode
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
        switch kind {
        case .behavior:
            .sequence(sequenceID)
        case .periodic:
            .periodic
        }
    }

    private var editorTitle: String {
        let type = kind == .behavior ? "행동 대사" : "주기 대사"
        return originalPhrase == nil ? "\(type) 추가" : "\(type) 수정"
    }

    private var durationSecondsSliderBinding: Binding<Double> {
        Binding(
            get: { Double(durationSeconds) },
            set: { durationSeconds = Int($0.rounded()) }
        )
    }

    private var canSave: Bool {
        !normalizedText.isEmpty
            && normalizedText.count <= AppSettingsLimits.maximumSpeechTextLength
            && (kind == .periodic
                || sequences.contains(where: { $0.id == sequenceID }))
    }
}
