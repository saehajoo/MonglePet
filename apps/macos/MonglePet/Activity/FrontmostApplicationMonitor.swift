import AppKit

@MainActor
final class FrontmostApplicationMonitor: NSObject, FrontmostApplicationMonitoring {
    private let notificationCenter: NotificationCenter
    private let currentApplicationIDProvider: () -> String?
    private let activatedApplicationIDProvider: (Notification) -> String?
    private var onChange: ((String?) -> Void)?
    private(set) var currentApplicationID: String?
    private var isRunning = false

    init(
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        currentApplicationIDProvider: @escaping () -> String? = {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        },
        activatedApplicationIDProvider: @escaping (Notification) -> String? = { notification in
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            return application?.bundleIdentifier
        }
    ) {
        self.notificationCenter = notificationCenter
        self.currentApplicationIDProvider = currentApplicationIDProvider
        self.activatedApplicationIDProvider = activatedApplicationIDProvider
        currentApplicationID = currentApplicationIDProvider()
    }

    func start(onChange: @escaping (String?) -> Void) {
        guard !isRunning else {
            return
        }

        currentApplicationID = currentApplicationIDProvider()
        self.onChange = onChange
        notificationCenter.addObserver(
            self,
            selector: #selector(applicationDidActivate),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        isRunning = true
    }

    func stop() {
        guard isRunning else {
            return
        }

        notificationCenter.removeObserver(
            self,
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        onChange = nil
        isRunning = false
    }

    @objc
    private func applicationDidActivate(_ notification: Notification) {
        let applicationID = activatedApplicationIDProvider(notification)
            ?? currentApplicationIDProvider()
        guard applicationID != currentApplicationID else {
            return
        }

        currentApplicationID = applicationID
        onChange?(applicationID)
    }
}
