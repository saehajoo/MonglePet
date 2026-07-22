import SwiftUI

struct SettingsView: View {
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
        .frame(minWidth: 500, minHeight: 400)
        .accessibilityIdentifier("monglepet.settings.root")
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

    private var clickThroughBinding: Binding<Bool> {
        Binding(
            get: { settingsSession.settings.overlay.clickThrough },
            set: { settingsSession.setClickThrough($0) }
        )
    }

    private var modeDescription: String {
        switch settingsSession.settings.behaviorMode {
        case .automatic:
            "앱과 쉬는 시간에 맞춘 자동 행동입니다. 규칙 편집은 다음 단계에서 추가됩니다."
        case .manual:
            "선택한 행동 목록을 유지합니다. 행동 목록 편집은 다음 단계에서 추가됩니다."
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
        )
    )
}
