import AppKit
import ImageIO

nonisolated enum PetPresentationLoadingError: Error, Equatable, Sendable {
    case missingAtlas(String)
    case invalidAtlas(String)
}

extension PetPresentationLoadingError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case let .missingAtlas(atlasID):
            "펫 애니메이션 이미지가 없습니다: \(atlasID)"
        case let .invalidAtlas(filename):
            "펫 애니메이션 이미지를 읽을 수 없습니다: \(filename)"
        }
    }
}

@MainActor
enum PetPresentationResourceLoader {
    static func loadAtlases(for item: PetLibraryItem) throws -> [PetAtlasImage] {
        if item.isBuiltIn {
            return try loadBuiltInAtlases()
        }

        guard let installedPackage = item.installedPackage else {
            throw PetPresentationLoadingError.missingAtlas(item.definition.id)
        }
        return try loadAtlases(from: installedPackage.package.atlases)
    }

    static func loadBuiltInAtlases() throws -> [PetAtlasImage] {
        try BuiltInPet.atlasDescriptors.map { descriptor in
            guard let image = NSImage(
                named: NSImage.Name(descriptor.imageName)
            ) else {
                throw PetPresentationLoadingError.missingAtlas(descriptor.id)
            }
            var proposedRect = NSRect(origin: .zero, size: image.size)
            guard
                let cgImage = image.cgImage(
                    forProposedRect: &proposedRect,
                    context: nil,
                    hints: nil
                ),
                cgImage.width == descriptor.pixelSize.width,
                cgImage.height == descriptor.pixelSize.height
            else {
                throw PetPresentationLoadingError.invalidAtlas(
                    descriptor.imageName
                )
            }
            return PetAtlasImage(
                id: descriptor.id,
                image: cgImage,
                pixelSize: descriptor.pixelSize
            )
        }
    }

    private static func loadAtlases(
        from resources: [PetAtlasResource]
    ) throws -> [PetAtlasImage] {
        try resources.map { resource in
            guard
                let source = CGImageSourceCreateWithURL(resource.fileURL as CFURL, nil),
                let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                image.width == resource.pixelSize.width,
                image.height == resource.pixelSize.height
            else {
                throw PetPresentationLoadingError.invalidAtlas(
                    resource.fileURL.lastPathComponent
                )
            }
            return PetAtlasImage(
                id: resource.id,
                image: image,
                pixelSize: resource.pixelSize
            )
        }
    }
}

@MainActor
final class PetWindowController: NSWindowController {
    static let defaultContentSize = NSSize(width: 192, height: 208)
    static let defaultScreenInset: CGFloat = 32

    private(set) var isAwake = false
    private(set) var isSystemSuspended = false
    private(set) var isUserDragging = false
    var onOverlayGeometryDidChange: (() -> Void)?
    var onUserDragStateDidChange: ((Bool) -> Void)?
    var onMovementEnvironmentDidChange: (() -> Void)?
    var onPettingRequested: (() -> Void)?

    private var hasPositionedPanel = false
    private(set) var petDefinition: PetDefinition
    private(set) var activeInstallationID: UUID?
    private var appliedOverlaySettings: OverlaySettings = .default
    private let framePlayer: FramePlayer
    private let petOverlayView: PetOverlayView
    private let pointerOverlapLifecycle: PetPointerOverlapLifecycle
    private let speechBubbleController: PetSpeechBubbleWindowController
    private let environmentProvider: any PetDesktopEnvironmentProviding
    private let resourceCache: PetPresentationResourceCache
    private var contentAspectRatio = PetWindowController.defaultContentSize.height
        / PetWindowController.defaultContentSize.width
    private(set) var scheduledMotion: ScheduledMotion?

    init(
        environmentProvider: any PetDesktopEnvironmentProviding =
            StaticPetDesktopEnvironmentProvider(),
        resourceCache: PetPresentationResourceCache =
            PetPresentationResourceCache()
    ) {
        guard
            let resources = try? resourceCache.builtInResources(),
            !resources.atlases.isEmpty,
            let petOverlayView = PetOverlayView(
                resources: resources,
                atlasID: BuiltInPet.atlasID
            )
        else {
            fatalError("The built-in MonglePet atlas is missing or invalid.")
        }

        let petDefinition = BuiltInPet.mongleDefinition()
        guard let defaultMotion = petDefinition.defaultMotion else {
            fatalError("The built-in MonglePet definition has no playable motion.")
        }

        self.environmentProvider = environmentProvider
        self.resourceCache = resourceCache
        self.petOverlayView = petOverlayView
        self.petDefinition = petDefinition
        framePlayer = FramePlayer { [weak petOverlayView] frame in
            petOverlayView?.display(frame)
        }

        let contentRect = NSRect(origin: .zero, size: Self.defaultContentSize)
        let panel = PetWindow(contentRect: contentRect)
        panel.contentView = petOverlayView
        panel.setContentSize(Self.defaultContentSize)
        pointerOverlapLifecycle = PetPointerOverlapLifecycle(
            observePointer: {
                [weak panel, weak petOverlayView, weak environmentProvider] in
                guard let pointer = environmentProvider?.currentSnapshot
                    .pointerLocation else {
                    return PetPointerObservation(
                        screenLocation: .zero,
                        isInsidePanel: false,
                        isOverVisibleContent: false
                    )
                }
                let mouseLocation = NSPoint(x: pointer.x, y: pointer.y)
                guard let panel,
                      let petOverlayView,
                      panel.isVisible else {
                    return PetPointerObservation(
                        screenLocation: mouseLocation,
                        isInsidePanel: false,
                        isOverVisibleContent: false
                    )
                }
                let isInsidePanel = panel.frame.contains(mouseLocation)
                let windowPoint = panel.convertPoint(
                    fromScreen: mouseLocation
                )
                let viewPoint = petOverlayView.convert(windowPoint, from: nil)
                return PetPointerObservation(
                    screenLocation: mouseLocation,
                    isInsidePanel: isInsidePanel,
                    isOverVisibleContent: isInsidePanel
                        && petOverlayView.containsVisibleContent(at: viewPoint)
                )
            },
            applyOpacity: { [weak panel] opacity, animated in
                guard let panel else {
                    return
                }
                Self.applyOpacity(
                    opacity,
                    to: panel,
                    animated: animated
                )
            }
        )
        let speechBubbleController = PetSpeechBubbleWindowController(
            parentWindow: panel,
            displaysProvider: { [weak environmentProvider] in
                environmentProvider?.currentSnapshot.displays ?? []
            },
            anchorFrameProvider: { [weak panel, weak petOverlayView] in
                guard let panel, let petOverlayView,
                      let viewBounds = petOverlayView.visibleContentBounds()
                else {
                    return nil
                }
                let windowBounds = petOverlayView.convert(viewBounds, to: nil)
                return panel.convertToScreen(windowBounds)
            }
        )
        self.speechBubbleController = speechBubbleController
        petOverlayView.onDisplayedFrameChange = {
            [weak speechBubbleController] in
            speechBubbleController?.refreshPlacement()
        }

        super.init(window: panel)
        shouldCascadeWindows = false
        pointerOverlapLifecycle.setPettingRequestHandler { [weak self] in
            self?.pettingDidRequest()
        }
        petOverlayView.onDragBegan = { [weak self] in
            self?.userDragDidBegin()
        }
        petOverlayView.onDragEnded = { [weak self] didMove in
            self?.userDragDidEnd(didMove: didMove)
        }
        framePlayer.play(defaultMotion)
        framePlayer.pause()
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

    var currentMotionID: String? {
        scheduledMotion?.motion.id
    }

    var movementOrigin: PetMovementPoint? {
        guard let panel else {
            return nil
        }
        return PetMovementPoint(
            x: Double(panel.frame.minX),
            y: Double(panel.frame.minY)
        )
    }

    var movementSize: PetMovementSize? {
        guard let panel else {
            return nil
        }
        return PetMovementSize(
            width: Double(panel.frame.width),
            height: Double(panel.frame.height)
        )
    }

    var movementBoundary: MovementBoundarySettings {
        appliedOverlaySettings.movementBoundary
    }

    func setMovementOrigin(_ origin: PetMovementPoint) {
        guard let panel, origin.isFinite else {
            return
        }
        panel.setFrameOrigin(NSPoint(x: origin.x, y: origin.y))
        hasPositionedPanel = true
    }

    func moveToVisibleFrame(_ visibleFrame: NSRect) {
        guard let panel else {
            return
        }
        panel.setFrameOrigin(
            Self.defaultOrigin(
                in: visibleFrame,
                contentSize: panel.frame.size
            )
        )
        hasPositionedPanel = true
    }

    func userDragDidBegin() {
        guard !isUserDragging else {
            return
        }
        isUserDragging = true
        pointerOverlapLifecycle.setUserDragging(true)
        onUserDragStateDidChange?(true)
    }

    func userDragDidEnd(didMove: Bool = true) {
        guard isUserDragging else {
            return
        }
        isUserDragging = false
        pointerOverlapLifecycle.setUserDragging(false)
        onUserDragStateDidChange?(false)
        if didMove {
            onOverlayGeometryDidChange?()
        }
    }

    func pettingDidRequest() {
        guard isAwake, !isSystemSuspended, !isUserDragging else {
            return
        }
        onPettingRequested?()
    }

    func applyPet(_ item: PetLibraryItem) throws {
        let resources = try resourceCache.resources(for: item)

        guard let defaultMotion = item.definition.defaultMotion,
              let firstFrame = defaultMotion.frames.first else {
            throw PetPresentationLoadingError.missingAtlas(item.definition.defaultMotionID)
        }

        scheduledMotion = nil
        framePlayer.stop()
        petOverlayView.replaceResources(
            resources,
            accessibilityLabel: item.metadata.displayName
        )
        petDefinition = item.definition
        activeInstallationID = item.selection.installationID
        contentAspectRatio = CGFloat(firstFrame.sourceRect.height)
            / CGFloat(firstFrame.sourceRect.width)
        resizePanelForCurrentAspectRatio()
        framePlayer.play(defaultMotion)
        if !isAwake || isSystemSuspended {
            framePlayer.pause()
        }
    }

    func wake(on screen: NSScreen? = nil) {
        guard let panel else {
            return
        }

        if hasPositionedPanel {
            correctPanelPosition()
        } else {
            let visibleFrame = screen?.visibleFrame
                ?? environmentProvider.currentSnapshot.displays.first
                    .map(Self.nsRect(from:))
                ?? panel.frame
            let origin = Self.defaultOrigin(
                in: visibleFrame,
                contentSize: panel.frame.size
            )
            panel.setFrameOrigin(origin)
            hasPositionedPanel = true
        }

        panel.orderFrontRegardless()
        isAwake = true
        pointerOverlapLifecycle.setAwake(true)
        if !isSystemSuspended {
            framePlayer.resume()
        }
    }

    func sleep() {
        pointerOverlapLifecycle.setAwake(false)
        speechBubbleController.hide()
        framePlayer.pause()
        panel?.orderOut(nil)
        isAwake = false
    }

    func orderFront() {
        guard isAwake else {
            return
        }
        panel?.orderFrontRegardless()
    }

    func setSystemSuspended(_ isSuspended: Bool) {
        guard isSuspended != isSystemSuspended else {
            return
        }

        isSystemSuspended = isSuspended
        pointerOverlapLifecycle.setSystemSuspended(isSuspended)
        if isSuspended {
            speechBubbleController.hide()
            framePlayer.pause()
        } else if isAwake {
            framePlayer.resume()
        }
    }

    func setReduceMotion(_ shouldReduceMotion: Bool) {
        pointerOverlapLifecycle.setReduceMotion(shouldReduceMotion)
    }

    func setPettingEnabled(_ isEnabled: Bool) {
        pointerOverlapLifecycle.setPettingEnabled(isEnabled)
    }

    func showSpeechBubble(_ presentation: PetSpeechPresentation) {
        guard isAwake, !isSystemSuspended else {
            return
        }
        speechBubbleController.show(
            text: presentation.text,
            theme: presentation.theme,
            placement: presentation.placement
        )
    }

    func hideSpeechBubble() {
        speechBubbleController.hide()
    }

    func setScheduledMotion(_ scheduledMotion: ScheduledMotion?) {
        guard scheduledMotion != self.scheduledMotion else {
            return
        }

        self.scheduledMotion = scheduledMotion
        guard let scheduledMotion else {
            framePlayer.stop()
            return
        }

        framePlayer.play(
            scheduledMotion.motion,
            playbackSpeed: scheduledMotion.playbackSpeed,
            cycleElapsedDuration: scheduledMotion.cycleElapsedDuration
        )
        if !isAwake || isSystemSuspended {
            framePlayer.pause()
        }
    }

    func applyOverlaySettings(
        _ settings: OverlaySettings,
        restorePosition: Bool
    ) {
        appliedOverlaySettings = settings
        guard let panel else {
            return
        }

        let currentOrigin = panel.frame.origin
        let width = CGFloat(settings.width)
        panel.setContentSize(
            NSSize(width: width, height: width * contentAspectRatio)
        )
        panel.ignoresMouseEvents = settings.clickThrough
        petOverlayView.setPixelArtRendering(settings.pixelArtRendering)
        pointerOverlapLifecycle.setSettings(settings)

        if restorePosition {
            let storedFrame = NSRect(
                x: settings.originX,
                y: settings.originY,
                width: panel.frame.width,
                height: panel.frame.height
            )
            let displays = environmentProvider.currentSnapshot.displays
            let preferredDisplay = displays.first {
                $0.id == settings.screenIdentifier
            }
            let visibleFrames = preferredDisplay.map {
                [Self.nsRect(from: $0)]
            } ?? displays.map(Self.nsRect(from:))
            let correctedOrigin = Self.correctedOrigin(
                for: storedFrame,
                within: visibleFrames
            )
            panel.setFrameOrigin(correctedOrigin)
            hasPositionedPanel = true
        } else if hasPositionedPanel {
            panel.setFrameOrigin(currentOrigin)
            correctPanelPosition()
        }
    }

    func currentOverlaySettings() -> OverlaySettings? {
        guard let panel else {
            return nil
        }

        let targetDisplay = Self.bestDisplay(
            for: panel.frame,
            displays: environmentProvider.currentSnapshot.displays
        )
        return OverlaySettings(
            screenIdentifier: targetDisplay?.id,
            originX: panel.frame.minX,
            originY: panel.frame.minY,
            width: panel.frame.width,
            clickThrough: panel.ignoresMouseEvents,
            opacity: appliedOverlaySettings.opacity,
            pointerOverlapFadeEnabled:
                appliedOverlaySettings.pointerOverlapFadeEnabled,
            pointerOverlapOpacity:
                appliedOverlaySettings.pointerOverlapOpacity,
            pixelArtRendering: appliedOverlaySettings.pixelArtRendering,
            movementBoundary: appliedOverlaySettings.movementBoundary
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

        let visibleFrames = environmentProvider.currentSnapshot.displays.map(
            Self.nsRect(from:)
        )
        let correctedOrigin = Self.correctedOrigin(
            for: panel.frame,
            within: visibleFrames
        )
        panel.setFrameOrigin(correctedOrigin)
    }

    private func resizePanelForCurrentAspectRatio() {
        guard let panel else {
            return
        }
        panel.setContentSize(
            NSSize(
                width: panel.frame.width,
                height: panel.frame.width * contentAspectRatio
            )
        )
        if hasPositionedPanel {
            correctPanelPosition()
        }
    }

    private static func bestDisplay(
        for windowFrame: NSRect,
        displays: [PetDesktopDisplaySnapshot]
    ) -> PetDesktopDisplaySnapshot? {
        displays.max { lhs, rhs in
            intersectionArea(
                between: windowFrame,
                and: nsFrame(from: lhs)
            ) < intersectionArea(
                between: windowFrame,
                and: nsFrame(from: rhs)
            )
        }
    }

    private static func nsFrame(
        from display: PetDesktopDisplaySnapshot
    ) -> NSRect {
        NSRect(
            x: display.frame.minX,
            y: display.frame.minY,
            width: display.frame.size.width,
            height: display.frame.size.height
        )
    }

    private static func nsRect(
        from display: PetDesktopDisplaySnapshot
    ) -> NSRect {
        NSRect(
            x: display.visibleFrame.minX,
            y: display.visibleFrame.minY,
            width: display.visibleFrame.size.width,
            height: display.visibleFrame.size.height
        )
    }

    private static func intersectionArea(between lhs: NSRect, and rhs: NSRect) -> CGFloat {
        let intersection = lhs.intersection(rhs)
        guard !intersection.isNull else {
            return 0
        }

        return intersection.width * intersection.height
    }

    private static func applyOpacity(
        _ opacity: Double,
        to panel: NSPanel,
        animated: Bool
    ) {
        let alphaValue = CGFloat(opacity)
        guard animated, panel.isVisible else {
            panel.alphaValue = alphaValue
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(
                name: .easeInEaseOut
            )
            panel.animator().alphaValue = alphaValue
        }
    }

    func desktopEnvironmentDidChange() {
        correctPanelPosition()
        onMovementEnvironmentDidChange?()
    }
}
