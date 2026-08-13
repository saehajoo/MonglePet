import AppKit
import SwiftUI

nonisolated enum PetSpeechBubblePlacement {
    struct Result: Equatable, Sendable {
        let origin: PetMovementPoint
        let tailEdge: PetSpeechBubbleTailEdge
        let tailAnchorX: Double?
    }

    static func origin(
        parentFrame: PetMovementRect,
        bubbleSize: PetMovementSize,
        visibleFrame: PetMovementRect,
        settings: PetSpeechBubblePlacementSettings = .default
    ) -> PetMovementPoint {
        placement(
            parentFrame: parentFrame,
            bubbleSize: bubbleSize,
            visibleFrame: visibleFrame,
            settings: settings
        ).origin
    }

    static func placement(
        parentFrame: PetMovementRect,
        bubbleSize: PetMovementSize,
        visibleFrame: PetMovementRect,
        settings: PetSpeechBubblePlacementSettings = .default
    ) -> Result {
        let naturalCenteredX = parentFrame.midX - (bubbleSize.width / 2)
        let centeredX = naturalCenteredX + settings.horizontalOffset
        let minimumX = visibleFrame.minX
        let maximumX = max(minimumX, visibleFrame.maxX - bubbleSize.width)
        let x = min(max(centeredX, minimumX), maximumX)

        let aboveY = parentFrame.maxY + settings.gap
        let belowY = parentFrame.minY - settings.gap - bubbleSize.height
        let canPlaceAbove =
            aboveY + bubbleSize.height <= visibleFrame.maxY
        let canPlaceBelow = belowY >= visibleFrame.minY
        let y: Double
        let tailEdge: PetSpeechBubbleTailEdge
        let usesAbove: Bool = switch settings.preferredPosition {
        case .automatic, .above:
            canPlaceAbove || !canPlaceBelow
        case .below:
            !canPlaceBelow && canPlaceAbove
        }
        if usesAbove, canPlaceAbove {
            y = aboveY
            tailEdge = .bottom
        } else if !usesAbove, canPlaceBelow {
            y = belowY
            tailEdge = .top
        } else {
            let maximumY = max(
                visibleFrame.minY,
                visibleFrame.maxY - bubbleSize.height
            )
            y = min(max(aboveY, visibleFrame.minY), maximumY)
            tailEdge = y >= parentFrame.midY ? .bottom : .top
        }
        return Result(
            origin: PetMovementPoint(x: x, y: y),
            tailEdge: tailEdge,
            tailAnchorX: abs(x - naturalCenteredX) > 0.001
                ? parentFrame.midX - x
                : nil
        )
    }
}

nonisolated enum PetSpeechBubbleTailEdge: Equatable, Sendable {
    case top
    case bottom
}

@MainActor
final class PetSpeechBubbleWindowController {
    private let panel: NSPanel
    private weak var parentWindow: NSWindow?
    private var hostingView: NSHostingView<PetSpeechBubbleContentView>?
    private var currentText = ""
    private var currentTheme: PetSpeechBubbleTheme = .default
    private var currentPlacement: PetSpeechBubblePlacementSettings = .default
    private var currentTailEdge: PetSpeechBubbleTailEdge = .bottom
    private var currentTailAnchorX: Double?
    private let displaysProvider: () -> [PetDesktopDisplaySnapshot]

    init(
        parentWindow: NSWindow,
        displaysProvider: @escaping () -> [PetDesktopDisplaySnapshot] = {
            AppKitDisplayLayoutReader.currentDisplaySnapshots()
        }
    ) {
        self.parentWindow = parentWindow
        self.displaysProvider = displaysProvider
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

    func show(
        text: String,
        theme: PetSpeechBubbleTheme = .default,
        placement: PetSpeechBubblePlacementSettings = .default
    ) {
        guard let parentWindow, parentWindow.isVisible else {
            return
        }

        currentText = text
        currentTheme = theme
        currentPlacement = placement
        let bubbleView = PetSpeechBubbleContentView(
            text: text,
            theme: theme,
            tailEdge: .bottom
        )
        let hostingView = NSHostingView(rootView: bubbleView)
        let fittingSize = hostingView.fittingSize
        let size = NSSize(
            width: min(max(fittingSize.width, 72), 360),
            height: min(max(fittingSize.height, 44), 260)
        )
        let placement = bubblePlacement(
            parentFrame: parentWindow.frame,
            bubbleSize: size
        )
        currentTailEdge = placement.tailEdge
        currentTailAnchorX = placement.tailAnchorX
        hostingView.rootView = PetSpeechBubbleContentView(
            text: text,
            theme: theme,
            tailEdge: placement.tailEdge,
            tailAnchorX: placement.tailAnchorX
        )
        hostingView.frame = NSRect(origin: .zero, size: size)
        self.hostingView = hostingView
        panel.contentView = hostingView
        panel.setContentSize(size)
        panel.setFrameOrigin(placement.origin)
        panel.setAccessibilityLabel(text)

        if panel.parent !== parentWindow {
            panel.parent?.removeChildWindow(panel)
            parentWindow.addChildWindow(panel, ordered: .above)
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    private func bubblePlacement(
        parentFrame: NSRect,
        bubbleSize: NSSize
    ) -> (
        origin: NSPoint,
        tailEdge: PetSpeechBubbleTailEdge,
        tailAnchorX: Double?
    ) {
        let displays = displaysProvider()
        let intersectingDisplay = displays.max { lhs, rhs in
            Self.nsRect(lhs.frame).intersection(parentFrame).area
                < Self.nsRect(rhs.frame).intersection(parentFrame).area
        }
        let targetDisplay: PetDesktopDisplaySnapshot?
        if let intersectingDisplay,
           Self.nsRect(intersectingDisplay.frame)
            .intersection(parentFrame).area > 0 {
            targetDisplay = intersectingDisplay
        } else {
            targetDisplay = displays.first
        }
        let visibleFrame = targetDisplay.map {
            Self.nsRect($0.visibleFrame)
        } ?? parentFrame
        let placement = PetSpeechBubblePlacement.placement(
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
            ),
            settings: currentPlacement
        )
        return (
            NSPoint(
                x: placement.origin.x,
                y: placement.origin.y
            ),
            placement.tailEdge,
            placement.tailAnchorX
        )
    }

    private static func nsRect(_ rect: PetMovementRect) -> NSRect {
        NSRect(
            x: rect.minX,
            y: rect.minY,
            width: rect.size.width,
            height: rect.size.height
        )
    }

    @objc
    private func parentWindowDidMove() {
        guard let parentWindow, panel.isVisible else {
            return
        }
        let placement = bubblePlacement(
            parentFrame: parentWindow.frame,
            bubbleSize: panel.frame.size
        )
        if placement.tailEdge != currentTailEdge
            || placement.tailAnchorX != currentTailAnchorX {
            currentTailEdge = placement.tailEdge
            currentTailAnchorX = placement.tailAnchorX
            hostingView?.rootView = PetSpeechBubbleContentView(
                text: currentText,
                theme: currentTheme,
                tailEdge: placement.tailEdge,
                tailAnchorX: placement.tailAnchorX
            )
        }
        guard
            abs(panel.frame.minX - placement.origin.x) > 0.5
                || abs(panel.frame.minY - placement.origin.y) > 0.5
        else {
            return
        }
        panel.setFrameOrigin(placement.origin)
    }
}

struct PetSpeechBubbleContentView: View {
    private let tailWidth = 26.0
    private let tailHeight = 13.0

    let text: String
    let theme: PetSpeechBubbleTheme
    let tailEdge: PetSpeechBubbleTailEdge
    var tailAnchorX: Double? = nil
    var tailCenterOffset: Double? = nil

    var body: some View {
        Text(text)
            .font(.system(size: theme.fontSize, weight: .medium))
            .foregroundStyle(textColor)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .lineLimit(6)
            .padding(theme.contentPadding)
            .frame(maxWidth: 320, alignment: .leading)
            .padding(
                .top,
                theme.showsTail && tailEdge == .top ? tailHeight : 0
            )
            .padding(
                .bottom,
                theme.showsTail && tailEdge == .bottom ? tailHeight : 0
            )
            .background(
                bubbleShape
                    .fill(backgroundColor)
                    .shadow(
                        color: .black.opacity(0.18),
                        radius: 6,
                        y: 2
                    )
            )
            .overlay(
                bubbleShape
                    .stroke(textColor.opacity(0.16), lineWidth: 1)
            )
        .padding(7)
    }

    private var bubbleShape: SpeechBubbleContainerShape {
        SpeechBubbleContainerShape(
            cornerRadius: theme.cornerRadius,
            showsTail: theme.showsTail,
            tailEdge: tailEdge,
            tailAlignment: theme.tailAlignment,
            tailAnchorX: tailAnchorX.map { $0 - 7 },
            tailCenterOffset: tailCenterOffset,
            tailWidth: tailWidth,
            tailHeight: tailHeight,
            tailInset: max(theme.contentPadding, 12)
        )
    }

    private var backgroundColor: Color {
        if theme.colorStyle == .system {
            return Color(nsColor: .windowBackgroundColor)
                .opacity(theme.backgroundOpacity)
        }
        let color = theme.presetColors?.background
            ?? theme.customBackgroundColor
        return Color(
            .sRGB,
            red: color.red,
            green: color.green,
            blue: color.blue,
            opacity: theme.backgroundOpacity
        )
    }

    private var textColor: Color {
        if theme.colorStyle == .system {
            return Color(nsColor: .labelColor)
        }
        let color = theme.presetColors?.text ?? theme.customTextColor
        return Color(
            .sRGB,
            red: color.red,
            green: color.green,
            blue: color.blue
        )
    }
}

private struct SpeechBubbleContainerShape: Shape {
    let cornerRadius: Double
    let showsTail: Bool
    let tailEdge: PetSpeechBubbleTailEdge
    let tailAlignment: PetSpeechBubbleTailAlignment
    let tailAnchorX: Double?
    let tailCenterOffset: Double?
    let tailWidth: Double
    let tailHeight: Double
    let tailInset: Double

    func path(in rect: CGRect) -> Path {
        let topTailHeight = showsTail && tailEdge == .top
            ? tailHeight
            : 0
        let bottomTailHeight = showsTail && tailEdge == .bottom
            ? tailHeight
            : 0
        let body = CGRect(
            x: rect.minX,
            y: rect.minY + topTailHeight,
            width: rect.width,
            height: max(
                rect.height - topTailHeight - bottomTailHeight,
                1
            )
        )
        let radius = min(
            max(cornerRadius, 0),
            body.width / 2,
            body.height / 2
        )
        let tailCenter = tailCenterX(in: body, cornerRadius: radius)
        let tailHalfWidth = min(
            tailWidth / 2,
            max((body.width - (radius * 2)) / 2, 0)
        )
        let tailLeft = tailCenter - tailHalfWidth
        let tailRight = tailCenter + tailHalfWidth

        var path = Path()
        path.move(
            to: CGPoint(x: body.minX + radius, y: body.minY)
        )

        if showsTail, tailEdge == .top {
            path.addLine(to: CGPoint(x: tailLeft, y: body.minY))
            path.addLine(to: CGPoint(x: tailCenter, y: rect.minY))
            path.addLine(to: CGPoint(x: tailRight, y: body.minY))
        }

        path.addLine(
            to: CGPoint(x: body.maxX - radius, y: body.minY)
        )
        path.addQuadCurve(
            to: CGPoint(x: body.maxX, y: body.minY + radius),
            control: CGPoint(x: body.maxX, y: body.minY)
        )
        path.addLine(
            to: CGPoint(x: body.maxX, y: body.maxY - radius)
        )
        path.addQuadCurve(
            to: CGPoint(x: body.maxX - radius, y: body.maxY),
            control: CGPoint(x: body.maxX, y: body.maxY)
        )

        if showsTail, tailEdge == .bottom {
            path.addLine(to: CGPoint(x: tailRight, y: body.maxY))
            path.addLine(to: CGPoint(x: tailCenter, y: rect.maxY))
            path.addLine(to: CGPoint(x: tailLeft, y: body.maxY))
        }

        path.addLine(
            to: CGPoint(x: body.minX + radius, y: body.maxY)
        )
        path.addQuadCurve(
            to: CGPoint(x: body.minX, y: body.maxY - radius),
            control: CGPoint(x: body.minX, y: body.maxY)
        )
        path.addLine(
            to: CGPoint(x: body.minX, y: body.minY + radius)
        )
        path.addQuadCurve(
            to: CGPoint(x: body.minX + radius, y: body.minY),
            control: CGPoint(x: body.minX, y: body.minY)
        )
        path.closeSubpath()
        return path
    }

    private func tailCenterX(
        in body: CGRect,
        cornerRadius: Double
    ) -> Double {
        let halfWidth = tailWidth / 2
        let minimum = body.minX + cornerRadius + halfWidth
        let maximum = body.maxX - cornerRadius - halfWidth
        guard minimum <= maximum else {
            return body.midX
        }

        let preferred: Double
        if let tailAnchorX {
            preferred = tailAnchorX
        } else if let tailCenterOffset {
            preferred = body.midX + tailCenterOffset
        } else {
            preferred = switch tailAlignment {
            case .leading:
                body.minX + tailInset + halfWidth
            case .center:
                body.midX
            case .trailing:
                body.maxX - tailInset - halfWidth
            }
        }
        return min(max(preferred, minimum), maximum)
    }
}

private extension NSRect {
    var area: CGFloat {
        isNull ? 0 : width * height
    }
}
