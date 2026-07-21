import AppKit
import SwiftUI

@MainActor
final class PetWindowController: NSWindowController {
    static let defaultContentSize = NSSize(width: 192, height: 208)
    static let defaultScreenInset: CGFloat = 32

    init() {
        let contentRect = NSRect(origin: .zero, size: Self.defaultContentSize)
        let panel = PetWindow(contentRect: contentRect)
        let hostingController = NSHostingController(rootView: PetOverlayView())
        hostingController.view.wantsLayer = true
        hostingController.view.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentViewController = hostingController
        panel.setContentSize(Self.defaultContentSize)

        super.init(window: panel)
        shouldCascadeWindows = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var panel: PetWindow? {
        window as? PetWindow
    }

    func show(on screen: NSScreen? = NSScreen.main) {
        guard let panel, let targetScreen = screen ?? NSScreen.screens.first else {
            return
        }

        let origin = Self.defaultOrigin(in: targetScreen.visibleFrame)
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
    }

    static func defaultOrigin(
        in visibleFrame: NSRect,
        contentSize: NSSize = defaultContentSize,
        inset: CGFloat = defaultScreenInset
    ) -> NSPoint {
        NSPoint(
            x: visibleFrame.maxX - contentSize.width - inset,
            y: visibleFrame.minY + inset
        )
    }
}
