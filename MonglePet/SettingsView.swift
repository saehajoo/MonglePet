import SwiftUI

struct SettingsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "pawprint.fill")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("MonglePet")
                .font(.title.bold())

            Text("몽글펫 설정은 다음 개발 단계에서 추가됩니다.")
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 420, minHeight: 240)
        .padding(32)
        .accessibilityIdentifier("monglepet.settings.root")
    }
}

#Preview {
    SettingsView()
}
