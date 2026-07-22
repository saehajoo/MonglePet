import AppKit

@MainActor
final class PetWindowController: NSWindowController {
    static let defaultContentSize = NSSize(width: 192, height: 208)
    static let defaultScreenInset: CGFloat = 32

    private(set) var isAwake = false
    private(set) var isSystemSuspended = false
    var onOverlayGeometryDidChange: (() -> Void)?

    private var hasPositionedPanel = false
    private let framePlayer: FramePlayer
    private let petOverlayView: PetOverlayView

    init() {
        guard
            let placeholderImage = NSImage(named: "PlaceholderPet"),
            let petOverlayView = PetOverlayView(
                atlasID: BuiltInPet.atlasID,
                image: placeholderImage
            )
        else {
            fatalError("The built-in MonglePet atlas is missing or invalid.")
        }

        let petDefinition = BuiltInPet.mongleDefinition(
            atlasPixelSize: petOverlayView.atlasPixelSize
        )
        guard let defaultMotion = petDefinition.defaultMotion else {
            fatalError("The built-in MonglePet definition has no playable motion.")
        }

        self.petOverlayView = petOverlayView
        framePlayer = FramePlayer { [weak petOverlayView] frame in
            petOverlayView?.display(frame)
        }

        let contentRect = NSRect(origin: .zero, size: Self.defaultContentSize)
        let panel = PetWindow(contentRect: contentRect)
        panel.contentView = petOverlayView
        panel.setContentSize(Self.defaultContentSize)

        super.init(window: panel)
        shouldCascadeWindows = false
        petOverlayView.onDragEnded = { [weak self] in
            self?.onOverlayGeometryDidChange?()
        }
        framePlayer.play(defaultMotion)
        framePlayer.pause()
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

    var isAnimationPlaying: Bool {
        framePlayer.isPlaying
    }

    func wake(on screen: NSScreen? = NSScreen.main) {
        guard let panel, let targetScreen = screen ?? NSScreen.screens.first else {
            return
        }

        if hasPositionedPanel {
            correctPanelPosition()
        } else {
            let origin = Self.defaultOrigin(
                in: targetScreen.visibleFrame,
                contentSize: panel.frame.size
            )
            panel.setFrameOrigin(origin)
            hasPositionedPanel = true
        }

        panel.orderFrontRegardless()
        isAwake = true
        if !isSystemSuspended {
            framePlayer.resume()
        }
    }

    func sleep() {
        framePlayer.pause()
        panel?.orderOut(nil)
        isAwake = false
    }

    func setSystemSuspended(_ isSuspended: Bool) {
        guard isSuspended != isSystemSuspended else {
            return
        }

        isSystemSuspended = isSuspended
        if isSuspended {
            framePlayer.pause()
        } else if isAwake {
            framePlayer.resume()
        }
    }

    func applyOverlaySettings(
        _ settings: OverlaySettings,
        restorePosition: Bool
    ) {
        guard let panel else {
            return
        }

        let width = CGFloat(settings.width)
        let aspectRatio = Self.defaultContentSize.height / Self.defaultContentSize.width
        panel.setContentSize(
            NSSize(width: width, height: width * aspectRatio)
        )
        panel.ignoresMouseEvents = settings.clickThrough

        if restorePosition {
            let storedFrame = NSRect(
                x: settings.originX,
                y: settings.originY,
                width: panel.frame.width,
                height: panel.frame.height
            )
            let preferredScreen = NSScreen.screens.first {
                Self.screenIdentifier(for: $0) == settings.screenIdentifier
            }
            let visibleFrames = preferredScreen.map { [$0.visibleFrame] }
                ?? NSScreen.screens.map(\.visibleFrame)
            let correctedOrigin = Self.correctedOrigin(
                for: storedFrame,
                within: visibleFrames
            )
            panel.setFrameOrigin(correctedOrigin)
            hasPositionedPanel = true
        } else if hasPositionedPanel {
            correctPanelPosition()
        }
    }

    func currentOverlaySettings() -> OverlaySettings? {
        guard let panel else {
            return nil
        }

        let targetScreen = panel.screen ?? Self.bestScreen(for: panel.frame)
        return OverlaySettings(
            screenIdentifier: targetScreen.flatMap(Self.screenIdentifier(for:)),
            originX: panel.frame.minX,
            originY: panel.frame.minY,
            width: panel.frame.width,
            clickThrough: panel.ignoresMouseEvents
        )
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

    static func screenIdentifier(for screen: NSScreen) -> String? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        guard let screenNumber = screen.deviceDescription[key] as? NSNumber else {
            return nil
        }
        let displayID = CGDirectDisplayID(screenNumber.uint32Value)
        guard let unmanagedDisplayUUID = CGDisplayCreateUUIDFromDisplayID(displayID) else {
            return "display-id-\(displayID)"
        }
        let displayUUID = unmanagedDisplayUUID.takeRetainedValue()
        let uuidString = CFUUIDCreateString(nil, displayUUID) as String
        return "display-\(uuidString.lowercased())"
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

    private static func bestScreen(for windowFrame: NSRect) -> NSScreen? {
        NSScreen.screens.max { lhs, rhs in
            intersectionArea(between: windowFrame, and: lhs.frame)
                < intersectionArea(between: windowFrame, and: rhs.frame)
        }
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
        if hasPositionedPanel {
            onOverlayGeometryDidChange?()
        }
    }
}
