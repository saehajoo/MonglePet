import SwiftUI

struct PetOverlayView: View {
    var body: some View {
        Image("PlaceholderPet")
            .resizable()
            .scaledToFit()
            .accessibilityLabel("몽글이")
            .accessibilityIdentifier("monglepet.overlay.pet")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.clear)
    }
}

#Preview {
    PetOverlayView()
        .frame(width: 192, height: 208)
}
