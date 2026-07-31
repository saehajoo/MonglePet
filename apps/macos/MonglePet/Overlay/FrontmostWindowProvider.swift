import AppKit
import CoreGraphics
import Foundation

nonisolated struct PetWindowSnapshot: Equatable, Sendable {
    let ownerPID: Int32
    let layer: Int
    let alpha: Double
    let bounds: PetMovementRect
}

nonisolated struct PetMovementDisplayLayout: Equatable, Sendable {
    let screens: [PetMovementScreen]
    let mainScreenMaxY: Double
}

nonisolated struct PetMovementDisplayOption: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
}

nonisolated enum FrontmostWindowResolver {
    static let minimumWindowDimension = 64.0
    static let fullScreenCoverageThreshold = 0.98

    static func representativeWindow(
        frontmostPID: Int32?,
        snapshots: [PetWindowSnapshot],
        displayLayout: PetMovementDisplayLayout
    ) -> PetMovementWindow? {
        guard let frontmostPID,
              frontmostPID > 0,
              displayLayout.mainScreenMaxY.isFinite else {
            return nil
        }

        let screens = displayLayout.screens.filter { $0.visibleFrame.isValid }
        guard !screens.isEmpty else {
            return nil
        }

        let candidates = snapshots.compactMap { snapshot -> Candidate? in
            guard snapshot.ownerPID == frontmostPID,
                  snapshot.layer == 0,
                  snapshot.alpha.isFinite,
                  snapshot.alpha > 0,
                  snapshot.bounds.isValid,
                  snapshot.bounds.size.width >= minimumWindowDimension,
                  snapshot.bounds.size.height >= minimumWindowDimension else {
                return nil
            }

            let convertedFrame = appKitFrame(
                fromCoreGraphicsFrame: snapshot.bounds,
                mainScreenMaxY: displayLayout.mainScreenMaxY
            )
            let visibleArea = screens.reduce(0.0) { partialResult, screen in
                partialResult + intersectionArea(
                    convertedFrame,
                    screen.visibleFrame
                )
            }
            guard visibleArea > 0 else {
                return nil
            }
            return Candidate(
                window: PetMovementWindow(frame: convertedFrame),
                visibleArea: visibleArea,
                isFullScreen: screens.contains {
                    isFullScreen(convertedFrame, on: $0.visibleFrame)
                }
            )
        }

        guard !candidates.contains(where: \.isFullScreen) else {
            return nil
        }
        return candidates.max { lhs, rhs in
            lhs.visibleArea < rhs.visibleArea
        }?.window
    }

    static func appKitFrame(
        fromCoreGraphicsFrame frame: PetMovementRect,
        mainScreenMaxY: Double
    ) -> PetMovementRect {
        PetMovementRect(
            x: frame.minX,
            y: mainScreenMaxY - frame.maxY,
            width: frame.size.width,
            height: frame.size.height
        )
    }

    private struct Candidate {
        let window: PetMovementWindow
        let visibleArea: Double
        let isFullScreen: Bool
    }

    private static func isFullScreen(
        _ windowFrame: PetMovementRect,
        on visibleFrame: PetMovementRect
    ) -> Bool {
        let visibleFrameArea = visibleFrame.size.width * visibleFrame.size.height
        let windowArea = windowFrame.size.width * windowFrame.size.height
        guard visibleFrameArea > 0,
              windowArea >= visibleFrameArea * fullScreenCoverageThreshold else {
            return false
        }
        return intersectionArea(windowFrame, visibleFrame) / visibleFrameArea
            >= fullScreenCoverageThreshold
    }

    private static func intersectionArea(
        _ lhs: PetMovementRect,
        _ rhs: PetMovementRect
    ) -> Double {
        let width = max(0, min(lhs.maxX, rhs.maxX) - max(lhs.minX, rhs.minX))
        let height = max(0, min(lhs.maxY, rhs.maxY) - max(lhs.minY, rhs.minY))
        return width * height
    }
}

@MainActor
protocol FrontmostWindowProviding: AnyObject {
    func representativeWindow() -> PetMovementWindow?
    func invalidate()
}

@MainActor
final class FrontmostWindowProvider: FrontmostWindowProviding {
    static let defaultMinimumRefreshInterval: TimeInterval = 1

    private let minimumRefreshInterval: TimeInterval
    private let frontmostPIDProvider: () -> Int32?
    private let windowSnapshotsProvider: () -> [PetWindowSnapshot]
    private let displayLayoutProvider: () -> PetMovementDisplayLayout?
    private let uptimeProvider: () -> TimeInterval
    private var cachedPID: Int32?
    private var cachedWindow: PetMovementWindow?
    private var cachedAt: TimeInterval?
    private var hasCachedValue = false

    init(
        minimumRefreshInterval: TimeInterval = defaultMinimumRefreshInterval,
        frontmostPIDProvider: @escaping () -> Int32? = {
            guard let processIdentifier = NSWorkspace.shared
                .frontmostApplication?.processIdentifier,
                  processIdentifier != Int32(ProcessInfo.processInfo.processIdentifier)
            else {
                return nil
            }
            return processIdentifier
        },
        windowSnapshotsProvider: @escaping () -> [PetWindowSnapshot] = {
            WindowServerSnapshotReader.snapshots()
        },
        displayLayoutProvider: @escaping () -> PetMovementDisplayLayout? = {
            AppKitDisplayLayoutReader.currentLayout()
        },
        uptimeProvider: @escaping () -> TimeInterval = {
            ProcessInfo.processInfo.systemUptime
        }
    ) {
        self.minimumRefreshInterval = max(minimumRefreshInterval, 0.1)
        self.frontmostPIDProvider = frontmostPIDProvider
        self.windowSnapshotsProvider = windowSnapshotsProvider
        self.displayLayoutProvider = displayLayoutProvider
        self.uptimeProvider = uptimeProvider
    }

    func representativeWindow() -> PetMovementWindow? {
        let frontmostPID = frontmostPIDProvider()
        let now = uptimeProvider()
        if hasCachedValue,
           cachedPID == frontmostPID,
           let cachedAt,
           now.isFinite,
           now >= cachedAt,
           now - cachedAt < minimumRefreshInterval {
            return cachedWindow
        }

        let window: PetMovementWindow?
        if let displayLayout = displayLayoutProvider() {
            let snapshots = frontmostPID == nil ? [] : windowSnapshotsProvider()
            window = FrontmostWindowResolver.representativeWindow(
                frontmostPID: frontmostPID,
                snapshots: snapshots,
                displayLayout: displayLayout
            )
        } else {
            window = nil
        }

        cachedPID = frontmostPID
        cachedWindow = window
        cachedAt = now.isFinite ? now : nil
        hasCachedValue = true
        return window
    }

    func invalidate() {
        cachedPID = nil
        cachedWindow = nil
        cachedAt = nil
        hasCachedValue = false
    }
}

@MainActor
private enum WindowServerSnapshotReader {
    static func snapshots() -> [PetWindowSnapshot] {
        let options: CGWindowListOption = [
            .optionOnScreenOnly,
            .excludeDesktopElements
        ]
        guard let windowList = CGWindowListCopyWindowInfo(
            options,
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return []
        }

        return windowList.compactMap { entry in
            guard let ownerPID = (entry[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let layer = (entry[kCGWindowLayer as String] as? NSNumber)?.intValue,
                  let boundsDictionary = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(
                      dictionaryRepresentation: boundsDictionary as CFDictionary
                  ) else {
                return nil
            }
            let alpha = (entry[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            return PetWindowSnapshot(
                ownerPID: ownerPID,
                layer: layer,
                alpha: alpha,
                bounds: PetMovementRect(
                    x: Double(bounds.minX),
                    y: Double(bounds.minY),
                    width: Double(bounds.width),
                    height: Double(bounds.height)
                )
            )
        }
    }
}

@MainActor
enum AppKitDisplayLayoutReader {
    static func currentLayout() -> PetMovementDisplayLayout? {
        let appKitScreens = NSScreen.screens
        guard let mainScreen = appKitScreens.first else {
            return nil
        }
        return PetMovementDisplayLayout(
            screens: movementScreens(from: appKitScreens),
            mainScreenMaxY: Double(mainScreen.frame.maxY)
        )
    }

    static func currentMovementScreens() -> [PetMovementScreen] {
        movementScreens(from: NSScreen.screens)
    }

    static func currentDisplayOptions() -> [PetMovementDisplayOption] {
        NSScreen.screens.enumerated().map { index, screen in
            PetMovementDisplayOption(
                id: screenIdentifier(for: screen, fallbackIndex: index),
                name: "디스플레이 \(index + 1) · \(screen.localizedName)"
            )
        }
    }

    private static func movementScreens(
        from appKitScreens: [NSScreen]
    ) -> [PetMovementScreen] {
        appKitScreens.enumerated().map { index, screen in
            let visibleFrame = screen.visibleFrame
            return PetMovementScreen(
                id: screenIdentifier(for: screen, fallbackIndex: index),
                visibleFrame: PetMovementRect(
                    x: Double(visibleFrame.minX),
                    y: Double(visibleFrame.minY),
                    width: Double(visibleFrame.width),
                    height: Double(visibleFrame.height)
                )
            )
        }
    }

    private static func screenIdentifier(
        for screen: NSScreen,
        fallbackIndex: Int
    ) -> String {
        PetWindowController.screenIdentifier(for: screen)
            ?? "screen-\(fallbackIndex)"
    }
}
