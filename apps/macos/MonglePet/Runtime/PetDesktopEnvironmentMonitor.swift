import AppKit

nonisolated struct PetDesktopDisplaySnapshot: Equatable, Sendable {
    let id: String
    let name: String
    let frame: PetMovementRect
    let visibleFrame: PetMovementRect

    var movementScreen: PetMovementScreen {
        PetMovementScreen(id: id, visibleFrame: visibleFrame)
    }
}

nonisolated struct PetDesktopEnvironmentSnapshot: Equatable, Sendable {
    let pointerLocation: PetMovementPoint?
    let displays: [PetDesktopDisplaySnapshot]
    let movementScreens: [PetMovementScreen]

    init(
        pointerLocation: PetMovementPoint?,
        displays: [PetDesktopDisplaySnapshot]
    ) {
        self.pointerLocation = pointerLocation
        self.displays = displays
        movementScreens = displays.map(\.movementScreen)
    }

    var displayLayout: PetMovementDisplayLayout? {
        guard let mainDisplay = displays.first else {
            return nil
        }
        return PetMovementDisplayLayout(
            screens: movementScreens,
            mainScreenMaxY: mainDisplay.frame.maxY
        )
    }
}

@MainActor
protocol PetDesktopEnvironmentProviding: AnyObject {
    var currentSnapshot: PetDesktopEnvironmentSnapshot { get }
}

@MainActor
final class PetDesktopEnvironmentMonitor: NSObject,
    PetDesktopEnvironmentProviding {
    static let pointerRefreshInterval: TimeInterval = 1.0 / 30.0

    private let notificationCenter: NotificationCenter
    private let pointerProvider: () -> PetMovementPoint?
    private let displaysProvider: () -> [PetDesktopDisplaySnapshot]
    private var pointerTimer: Timer?
    private var onDisplaysChange: (() -> Void)?
    private(set) var isStarted = false
    private(set) var isPointerMonitoringEnabled = true
    private(set) var currentSnapshot: PetDesktopEnvironmentSnapshot

    init(
        notificationCenter: NotificationCenter = .default,
        pointerProvider: @escaping () -> PetMovementPoint? = {
            let location = NSEvent.mouseLocation
            return PetMovementPoint(
                x: Double(location.x),
                y: Double(location.y)
            )
        },
        displaysProvider: @escaping () -> [PetDesktopDisplaySnapshot] = {
            AppKitDisplayLayoutReader.currentDisplaySnapshots()
        }
    ) {
        self.notificationCenter = notificationCenter
        self.pointerProvider = pointerProvider
        self.displaysProvider = displaysProvider
        currentSnapshot = PetDesktopEnvironmentSnapshot(
            pointerLocation: pointerProvider(),
            displays: displaysProvider()
        )
        super.init()
    }

    var isRunning: Bool {
        pointerTimer != nil
    }

    func start(onDisplaysChange: @escaping () -> Void) {
        guard !isStarted else {
            self.onDisplaysChange = onDisplaysChange
            return
        }
        isStarted = true
        self.onDisplaysChange = onDisplaysChange
        currentSnapshot = PetDesktopEnvironmentSnapshot(
            pointerLocation: pointerProvider(),
            displays: displaysProvider()
        )
        notificationCenter.addObserver(
            self,
            selector: #selector(screenParametersDidChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        if isPointerMonitoringEnabled {
            startPointerTimer()
        }
    }

    func setPointerMonitoringEnabled(_ isEnabled: Bool) {
        guard isEnabled != isPointerMonitoringEnabled else {
            return
        }
        isPointerMonitoringEnabled = isEnabled
        guard isStarted else {
            return
        }
        guard isEnabled else {
            pointerTimer?.invalidate()
            pointerTimer = nil
            return
        }
        refreshPointer()
        startPointerTimer()
    }

    private func startPointerTimer() {
        guard pointerTimer == nil else {
            return
        }
        let timer = Timer(
            timeInterval: Self.pointerRefreshInterval,
            target: self,
            selector: #selector(refreshPointer),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        pointerTimer = timer
    }

    func stop() {
        notificationCenter.removeObserver(
            self,
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        pointerTimer?.invalidate()
        pointerTimer = nil
        onDisplaysChange = nil
        isStarted = false
    }

    @objc
    func refreshPointer() {
        currentSnapshot = PetDesktopEnvironmentSnapshot(
            pointerLocation: pointerProvider(),
            displays: currentSnapshot.displays
        )
    }

    @objc
    private func screenParametersDidChange() {
        let displays = displaysProvider()
        guard displays != currentSnapshot.displays else {
            return
        }
        currentSnapshot = PetDesktopEnvironmentSnapshot(
            pointerLocation: pointerProvider(),
            displays: displays
        )
        onDisplaysChange?()
    }
}

@MainActor
final class StaticPetDesktopEnvironmentProvider:
    PetDesktopEnvironmentProviding {
    var currentSnapshot: PetDesktopEnvironmentSnapshot

    init(
        snapshot: PetDesktopEnvironmentSnapshot =
            PetDesktopEnvironmentSnapshot(
                pointerLocation: nil,
                displays: AppKitDisplayLayoutReader.currentDisplaySnapshots()
            )
    ) {
        currentSnapshot = snapshot
    }
}
