import AppKit
import Combine
import SwiftUI

nonisolated enum EditorWindowPlacement {
    static func adjustedFrame(
        proposedFrame: CGRect?,
        idealSize: CGSize,
        minimumSize: CGSize,
        visibleFrame: CGRect,
        fallbackCenter: CGPoint
    ) -> CGRect {
        guard visibleFrame.isUsable else {
            return CGRect(origin: .zero, size: idealSize)
        }

        let minimumWidth = min(minimumSize.width, visibleFrame.width)
        let minimumHeight = min(minimumSize.height, visibleFrame.height)
        let proposedIsValid = proposedFrame.map {
            $0.isFinite
                && $0.width >= minimumWidth
                && $0.height >= minimumHeight
        } ?? false
        let sourceSize = proposedIsValid
            ? proposedFrame!.size
            : idealSize
        let size = CGSize(
            width: min(
                visibleFrame.width,
                max(minimumWidth, sourceSize.width)
            ),
            height: min(
                visibleFrame.height,
                max(minimumHeight, sourceSize.height)
            )
        )
        let sourceOrigin = proposedIsValid
            ? proposedFrame!.origin
            : CGPoint(
                x: fallbackCenter.x - size.width / 2,
                y: fallbackCenter.y - size.height / 2
            )
        let maximumX = visibleFrame.maxX - size.width
        let maximumY = visibleFrame.maxY - size.height

        return CGRect(
            x: min(max(sourceOrigin.x, visibleFrame.minX), maximumX),
            y: min(max(sourceOrigin.y, visibleFrame.minY), maximumY),
            width: size.width,
            height: size.height
        )
    }
}

nonisolated private extension CGRect {
    var isFinite: Bool {
        origin.x.isFinite
            && origin.y.isFinite
            && size.width.isFinite
            && size.height.isFinite
    }

    var isUsable: Bool {
        isFinite && width > 0 && height > 0
    }
}

@MainActor
final class ImageEditorWindowCloseRequests: ObservableObject {
    @Published private(set) var revision = 0

    func requestClose() {
        revision += 1
    }
}

@MainActor
final class EditorWindowPresenter: ObservableObject {
    @Published private(set) var isPresenting = false

    private var windowController: EditorWindowController?

    func presentSpriteSheet(
        _ document: SpriteSheetDocument,
        onImport: @escaping ([UserPetSourceImage]) -> Void
    ) {
        let closeRequests = ImageEditorWindowCloseRequests()
        let editor = SpriteSheetImportView(
            document: document,
            onImport: onImport,
            onDismiss: { [weak self] in
                self?.close()
            },
            closeRequests: closeRequests
        )
        presentWindow(
            editor,
            title: "스프라이트 시트 가져오기",
            autosaveName: "MonglePet.SpriteSheetImportWindow",
            idealSize: NSSize(
                width: SpriteSheetEditorLayout.idealWindowWidth,
                height: SpriteSheetEditorLayout.idealWindowHeight
            ),
            minimumSize: NSSize(
                width: SpriteSheetEditorLayout.minimumWindowWidth,
                height: SpriteSheetEditorLayout.minimumWindowHeight
            ),
            closeRequests: closeRequests
        )
    }

    func presentPNGCrop(
        _ images: [UserPetSourceImage],
        onImport: @escaping ([UserPetSourceImage]) -> Void
    ) {
        let closeRequests = ImageEditorWindowCloseRequests()
        let editor = PNGFrameCropEditorView(
            images: images,
            onImport: onImport,
            onDismiss: { [weak self] in
                self?.close()
            },
            closeRequests: closeRequests
        )
        presentWindow(
            editor,
            title: "PNG 프레임 자르기",
            autosaveName: "MonglePet.PNGFrameCropWindow",
            idealSize: NSSize(
                width: PNGFrameCropEditorLayout.idealWindowWidth,
                height: PNGFrameCropEditorLayout.idealWindowHeight
            ),
            minimumSize: NSSize(
                width: PNGFrameCropEditorLayout.minimumWindowWidth,
                height: PNGFrameCropEditorLayout.minimumWindowHeight
            ),
            closeRequests: closeRequests
        )
    }

    func presentExistingFrames(
        petName: String,
        groups: [ExistingPetFrameGroup],
        onImport: @escaping ([ExistingPetFrameSelection]) -> Void
    ) {
        let editor = ExistingPetFramePickerView(
            petName: petName,
            groups: groups,
            onDismiss: { [weak self] in
                self?.close()
            },
            onImport: onImport
        )
        presentWindow(
            editor,
            title: "현재 펫 프레임에서 추가",
            autosaveName: "MonglePet.ExistingPetFramePickerWindow",
            idealSize: NSSize(width: 1_080, height: 760),
            minimumSize: NSSize(width: 880, height: 620),
            closeRequests: nil
        )
    }

    func presentEditor<Content: View>(
        _ content: Content,
        title: String,
        autosaveName: String,
        idealSize: NSSize,
        minimumSize: NSSize
    ) {
        presentWindow(
            content,
            title: title,
            autosaveName: autosaveName,
            idealSize: idealSize,
            minimumSize: minimumSize,
            closeRequests: nil
        )
    }

    func close() {
        windowController?.closeImmediately()
        windowController = nil
        isPresenting = false
    }

    private func presentWindow<Content: View>(
        _ content: Content,
        title: String,
        autosaveName: String,
        idealSize: NSSize,
        minimumSize: NSSize,
        closeRequests: ImageEditorWindowCloseRequests?
    ) {
        close()

        let ownerWindow = NSApplication.shared.keyWindow
        let controller = EditorWindowController(
            content: content,
            title: title,
            autosaveName: autosaveName,
            idealSize: idealSize,
            minimumSize: minimumSize,
            ownerWindow: ownerWindow,
            closeRequests: closeRequests
        ) { [weak self] in
            self?.windowController = nil
            self?.isPresenting = false
        }
        windowController = controller
        isPresenting = true
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

@MainActor
private final class EditorWindowController: NSWindowController, NSWindowDelegate {
    private weak var ownerWindow: NSWindow?
    private let closeRequests: ImageEditorWindowCloseRequests?
    private let onDidClose: () -> Void
    private var allowsImmediateClose = false

    init<Content: View>(
        content: Content,
        title: String,
        autosaveName: String,
        idealSize: NSSize,
        minimumSize: NSSize,
        ownerWindow: NSWindow?,
        closeRequests: ImageEditorWindowCloseRequests?,
        onDidClose: @escaping () -> Void
    ) {
        self.ownerWindow = ownerWindow
        self.closeRequests = closeRequests
        self.onDidClose = onDidClose

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: idealSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentViewController = NSHostingController(rootView: content)
        window.minSize = minimumSize
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        let didRestoreFrame = window.setFrameUsingName(autosaveName)
        let proposedFrame = didRestoreFrame ? window.frame : nil
        let targetScreen = Self.targetScreen(
            for: proposedFrame,
            ownerWindow: ownerWindow
        )
        let visibleFrame = targetScreen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? CGRect(origin: .zero, size: idealSize)
        let fallbackCenter: CGPoint
        if let ownerWindow, ownerWindow.screen == targetScreen {
            fallbackCenter = CGPoint(
                x: ownerWindow.frame.midX,
                y: ownerWindow.frame.midY
            )
        } else {
            fallbackCenter = CGPoint(
                x: visibleFrame.midX,
                y: visibleFrame.midY
            )
        }
        let adjustedFrame = EditorWindowPlacement.adjustedFrame(
            proposedFrame: proposedFrame,
            idealSize: idealSize,
            minimumSize: minimumSize,
            visibleFrame: visibleFrame,
            fallbackCenter: fallbackCenter
        )
        window.setFrame(adjustedFrame, display: false)
        window.setFrameAutosaveName(autosaveName)
        window.saveFrame(usingName: autosaveName)

        super.init(window: window)
        window.delegate = self
        ownerWindow?.addChildWindow(window, ordered: .above)
    }

    required init?(coder: NSCoder) {
        nil
    }

    private static func targetScreen(
        for proposedFrame: CGRect?,
        ownerWindow: NSWindow?
    ) -> NSScreen? {
        if let proposedFrame {
            let bestMatch = NSScreen.screens.max { lhs, rhs in
                proposedFrame.intersection(lhs.visibleFrame).area
                    < proposedFrame.intersection(rhs.visibleFrame).area
            }
            if let bestMatch,
               proposedFrame.intersection(bestMatch.visibleFrame).area > 0 {
                return bestMatch
            }
        }
        return ownerWindow?.screen ?? NSScreen.main ?? NSScreen.screens.first
    }

    func closeImmediately() {
        allowsImmediateClose = true
        close()
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if allowsImmediateClose {
            return true
        }
        guard let closeRequests else {
            return true
        }
        closeRequests.requestClose()
        return false
    }

    func windowWillClose(_ notification: Notification) {
        if let window {
            ownerWindow?.removeChildWindow(window)
        }
        onDidClose()
        ownerWindow?.makeKeyAndOrderFront(nil)
    }
}

nonisolated private extension CGRect {
    var area: CGFloat {
        isNull || isInfinite ? 0 : max(0, width) * max(0, height)
    }
}
