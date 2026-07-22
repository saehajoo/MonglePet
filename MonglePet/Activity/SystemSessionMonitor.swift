import AppKit

@MainActor
final class SystemSessionMonitor: NSObject, SystemSessionMonitoring {
    private let notificationCenter: NotificationCenter
    private var onChange: ((SystemSessionState) -> Void)?
    private var isRunning = false
    private(set) var currentState: SystemSessionState

    init(
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        initialState: SystemSessionState = .active
    ) {
        self.notificationCenter = notificationCenter
        currentState = initialState
    }

    func start(onChange: @escaping (SystemSessionState) -> Void) {
        guard !isRunning else {
            return
        }

        self.onChange = onChange
        for name in Self.observedNotificationNames {
            notificationCenter.addObserver(
                self,
                selector: #selector(systemStateDidChange),
                name: name,
                object: nil
            )
        }
        isRunning = true
    }

    func stop() {
        guard isRunning else {
            return
        }

        for name in Self.observedNotificationNames {
            notificationCenter.removeObserver(self, name: name, object: nil)
        }
        onChange = nil
        isRunning = false
    }

    @objc
    private func systemStateDidChange(_ notification: Notification) {
        var nextState = currentState

        switch notification.name {
        case NSWorkspace.sessionDidResignActiveNotification:
            nextState.isSessionInactive = true
        case NSWorkspace.sessionDidBecomeActiveNotification:
            nextState.isSessionInactive = false
        case NSWorkspace.screensDidSleepNotification:
            nextState.isScreenAsleep = true
        case NSWorkspace.screensDidWakeNotification:
            nextState.isScreenAsleep = false
        case NSWorkspace.willSleepNotification:
            nextState.isSystemSleeping = true
        case NSWorkspace.didWakeNotification:
            nextState.isSystemSleeping = false
        default:
            return
        }

        guard nextState != currentState else {
            return
        }

        currentState = nextState
        onChange?(nextState)
    }

    private static let observedNotificationNames: [Notification.Name] = [
        NSWorkspace.sessionDidResignActiveNotification,
        NSWorkspace.sessionDidBecomeActiveNotification,
        NSWorkspace.screensDidSleepNotification,
        NSWorkspace.screensDidWakeNotification,
        NSWorkspace.willSleepNotification,
        NSWorkspace.didWakeNotification
    ]
}
