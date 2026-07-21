import AppKit
import SwiftUI

final class PetOverlayHostingView: NSHostingView<PetOverlayView> {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
