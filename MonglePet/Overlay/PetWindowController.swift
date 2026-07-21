import AppKit

@MainActor
final class PetWindowController: NSWindowController {
    static let defaultContentSize = NSSize(width: 192, height: 208)
    static let defaultScreenInset: CGFloat = 32

    private(set) var isAwake = false
    private var hasPositionedPanel = false

    init() {
        let contentRect = NSRect(origin: .zero, size: Self.defaultContentSize)
        let panel = PetWindow(contentRect: contentRect)
        let hostingView = PetOverlayHostingView(rootView: PetOverlayView())
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        panel.contentView = hostingView
        panel.setContentSize(Self.defaultContentSize)

        super.init(window: panel)
        shouldCascadeWindows = false
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var panel: PetWindow? {
        window as? PetWindow
    }

    func wake(on screen: NSScreen? = NSScreen.main) {
        guard let panel, let targetScreen = screen ?? NSScreen.screens.first else {
            return
        }

        if hasPositionedPanel {
            correctPanelPosition()
        } else {
            let origin = Self.defaultOrigin(in: targetScreen.visibleFrame)
            panel.setFrameOrigin(origin)
            hasPositionedPanel = true
        }

        panel.orderFrontRegardless()
        isAwake = true
    }

    func sleep() {
        panel?.orderOut(nil)
        isAwake = false
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

    static func correctedOrigin(
        for windowFrame: NSRect,
        within visibleFrames: [NSRect]
    ) -> NSPoint {
        guard let firstVisibleFrame = visibleFrames.first else {
            return windowFrame.origin
        }

        if visibleFrames.contains(where: { $0.contains(windowFrame) }) {
            return windowFrame.origin
        }

        var targetVisibleFrame = firstVisibleFrame
        var largestIntersectionArea = intersectionArea(
            between: windowFrame,
            and: firstVisibleFrame
        )

        for visibleFrame in visibleFrames.dropFirst() {
            let area = intersectionArea(between: windowFrame, and: visibleFrame)
            if area > largestIntersectionArea {
                targetVisibleFrame = visibleFrame
                largestIntersectionArea = area
            }
        }

        let maximumX = max(
            targetVisibleFrame.minX,
            targetVisibleFrame.maxX - windowFrame.width
        )
        let maximumY = max(
            targetVisibleFrame.minY,
            targetVisibleFrame.maxY - windowFrame.height
        )

        return NSPoint(
            x: min(max(windowFrame.minX, targetVisibleFrame.minX), maximumX),
            y: min(max(windowFrame.minY, targetVisibleFrame.minY), maximumY)
        )
    }

    private func correctPanelPosition() {
        guard let panel else {
            return
        }

        let visibleFrames = NSScreen.screens.map(\.visibleFrame)
        let correctedOrigin = Self.correctedOrigin(
            for: panel.frame,
            within: visibleFrames
        )
        panel.setFrameOrigin(correctedOrigin)
    }

    private static func intersectionArea(between lhs: NSRect, and rhs: NSRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else {
            return 0
        }

        return intersection.width * intersection.height
    }

    @objc
    private func screenParametersDidChange(_ notification: Notification) {
        correctPanelPosition()
    }
}
