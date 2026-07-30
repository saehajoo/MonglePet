import AppKit
import SwiftUI

nonisolated enum PetSpeechBubblePlacement {
    static let gap = 8.0

    static func origin(
        parentFrame: PetMovementRect,
        bubbleSize: PetMovementSize,
        visibleFrame: PetMovementRect
    ) -> PetMovementPoint {
        let centeredX = parentFrame.midX - (bubbleSize.width / 2)
        let minimumX = visibleFrame.minX
        let maximumX = max(minimumX, visibleFrame.maxX - bubbleSize.width)
        let x = min(max(centeredX, minimumX), maximumX)

        let aboveY = parentFrame.maxY + gap
        let belowY = parentFrame.minY - gap - bubbleSize.height
        let y: Double
        if aboveY + bubbleSize.height <= visibleFrame.maxY {
            y = aboveY
        } else if belowY >= visibleFrame.minY {
            y = belowY
        } else {
            let maximumY = max(
                visibleFrame.minY,
                visibleFrame.maxY - bubbleSize.height
            )
            y = min(max(aboveY, visibleFrame.minY), maximumY)
        }
        return PetMovementPoint(x: x, y: y)
    }
}

@MainActor
final class PetSpeechBubbleWindowController {
    private let panel: NSPanel
    private weak var parentWindow: NSWindow?
    private var hideTimer: Timer?

    init(parentWindow: NSWindow) {
        self.parentWindow = parentWindow
        panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary
        ]
        panel.isReleasedWhenClosed = false
        panel.setAccessibilityRole(.group)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(parentWindowDidMove),
            name: NSWindow.didMoveNotification,
            object: parentWindow
        )
    }

    var isVisible: Bool {
        panel.isVisible
    }

    var ignoresMouseEvents: Bool {
        panel.ignoresMouseEvents
    }

    func show(text: String, durationMilliseconds: Int64) {
        guard let parentWindow, parentWindow.isVisible else {
            return
        }

        let bubbleView = PetSpeechBubbleView(text: text)
        let hostingView = NSHostingView(rootView: bubbleView)
        let fittingSize = hostingView.fittingSize
        let size = NSSize(
            width: min(max(fittingSize.width, 72), 280),
            height: min(max(fittingSize.height, 44), 180)
        )
        hostingView.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hostingView
        panel.setContentSize(size)
        panel.setFrameOrigin(
            placementOrigin(
                parentFrame: parentWindow.frame,
                bubbleSize: size
            )
        )
        panel.setAccessibilityLabel(text)

        if panel.parent !== parentWindow {
            panel.parent?.removeChildWindow(panel)
            parentWindow.addChildWindow(panel, ordered: .above)
        }
        panel.orderFrontRegardless()
        scheduleHide(after: durationMilliseconds)
    }

    func hide() {
        hideTimer?.invalidate()
        hideTimer = nil
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    private func placementOrigin(
        parentFrame: NSRect,
        bubbleSize: NSSize
    ) -> NSPoint {
        let intersectingScreen = NSScreen.screens.max { lhs, rhs in
            lhs.frame.intersection(parentFrame).area
                < rhs.frame.intersection(parentFrame).area
        }
        let targetScreen: NSScreen?
        if let intersectingScreen,
           intersectingScreen.frame.intersection(parentFrame).area > 0 {
            targetScreen = intersectingScreen
        } else {
            targetScreen = parentWindow?.screen
        }
        let visibleFrame = targetScreen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? parentFrame
        let origin = PetSpeechBubblePlacement.origin(
            parentFrame: PetMovementRect(
                x: parentFrame.minX,
                y: parentFrame.minY,
                width: parentFrame.width,
                height: parentFrame.height
            ),
            bubbleSize: PetMovementSize(
                width: bubbleSize.width,
                height: bubbleSize.height
            ),
            visibleFrame: PetMovementRect(
                x: visibleFrame.minX,
                y: visibleFrame.minY,
                width: visibleFrame.width,
                height: visibleFrame.height
            )
        )
        return NSPoint(x: origin.x, y: origin.y)
    }

    private func scheduleHide(after durationMilliseconds: Int64) {
        hideTimer?.invalidate()
        let timer = Timer(
            timeInterval: max(
                TimeInterval(durationMilliseconds) / 1_000,
                0.001
            ),
            target: self,
            selector: #selector(hideTimerDidFire),
            userInfo: nil,
            repeats: false
        )
        RunLoop.main.add(timer, forMode: .common)
        hideTimer = timer
    }

    @objc
    private func hideTimerDidFire() {
        hide()
    }

    @objc
    private func parentWindowDidMove() {
        guard let parentWindow, panel.isVisible else {
            return
        }
        let origin = placementOrigin(
            parentFrame: parentWindow.frame,
            bubbleSize: panel.frame.size
        )
        guard
            abs(panel.frame.minX - origin.x) > 0.5
                || abs(panel.frame.minY - origin.y) > 0.5
        else {
            return
        }
        panel.setFrameOrigin(origin)
    }
}

private struct PetSpeechBubbleView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(.primary)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .lineLimit(6)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: 280, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.96))
                    .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.primary.opacity(0.14), lineWidth: 1)
            )
            .padding(7)
    }
}

private extension NSRect {
    var area: CGFloat {
        isNull ? 0 : width * height
    }
}
