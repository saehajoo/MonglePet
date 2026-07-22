import SwiftUI

struct SettingsView: View {
    @ObservedObject var settingsSession: AppSettingsSession
    let petDefinition: PetDefinition

    var body: some View {
        TabView {
            GeneralSettingsView(settingsSession: settingsSession)
                .tabItem {
                    Label("일반", systemImage: "gearshape")
                }

            BehaviorSequencesSettingsView(
                settingsSession: settingsSession,
                petDefinition: petDefinition
            )
                .tabItem {
                    Label("행동 루틴", systemImage: "list.bullet.rectangle")
                }

            AutomaticRulesSettingsView(settingsSession: settingsSession)
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

    var body: some View {
        Form {
            if let loadNotice = settingsSession.loadNotice {
                noticeLabel(loadNotice, systemImage: "exclamationmark.triangle.fill")
            }
            if let saveErrorMessage = settingsSession.saveErrorMessage {
                noticeLabel(saveErrorMessage, systemImage: "xmark.circle.fill")
            }

            Section("몽글이") {
                Toggle("몽글이 깨우기", isOn: awakeBinding)
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
    }

    private var awakeBinding: Binding<Bool> {
        Binding(
            get: { settingsSession.settings.lastUserPresentation == .awake },
            set: {
                settingsSession.setUserPresentation($0 ? .awake : .tuckedAway)
            }
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

    @ViewBuilder
    private func noticeLabel(_ message: String, systemImage: String) -> some View {
        Label(message, systemImage: systemImage)
            .foregroundStyle(.orange)
            .font(.callout)
            .accessibilityIdentifier("monglepet.settings.notice")
    }
}

#Preview {
    SettingsView(
        settingsSession: AppSettingsSession(
            store: AppSettingsStore(
                settingsURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("MonglePet-Preview-settings.json")
            )
        ),
        petDefinition: BuiltInPet.mongleDefinition(
            atlasPixelSize: PixelSize(width: 192, height: 208)
        )
    )
}
