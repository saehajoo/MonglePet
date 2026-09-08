import AppKit
import Combine
import SwiftUI

nonisolated enum EditorWindowPlacement {
    static func frame(
        idealSize: CGSize,
        minimumSize: CGSize,
        visibleFrame: CGRect,
        parentFrame: CGRect?
    ) -> CGRect {
        guard visibleFrame.isUsable else {
            return CGRect(origin: .zero, size: idealSize)
        }

        let minimumWidth = min(minimumSize.width, visibleFrame.width)
        let minimumHeight = min(minimumSize.height, visibleFrame.height)
        let size = CGSize(
            width: min(
                visibleFrame.width,
                max(minimumWidth, idealSize.width)
            ),
            height: min(
                visibleFrame.height,
                max(minimumHeight, idealSize.height)
            )
        )
        let center = parentFrame.map {
            CGPoint(x: $0.midX + 24, y: $0.midY - 24)
        } ?? CGPoint(x: visibleFrame.midX, y: visibleFrame.midY)
        let sourceOrigin = CGPoint(
            x: center.x - size.width / 2,
            y: center.y - size.height / 2
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
    private var isFinite: Bool {
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

nonisolated struct EditorDraftCloseGate<Snapshot: Equatable> {
    let initialSnapshot: Snapshot
    private(set) var isConfirmingDiscard = false

    mutating func requestClose(currentSnapshot: Snapshot) -> Bool {
        isConfirmingDiscard = currentSnapshot != initialSnapshot
        return !isConfirmingDiscard
    }

    mutating func continueEditing() {
        isConfirmingDiscard = false
    }
}

private struct EditorDraftProtection<Snapshot: Equatable>: ViewModifier {
    @EnvironmentObject private var closeRequests: ImageEditorWindowCloseRequests
    let snapshot: Snapshot
    let message: String
    let onDiscard: () -> Void
    @State private var closeGate: EditorDraftCloseGate<Snapshot>

    init(snapshot: Snapshot, message: String, onDiscard: @escaping () -> Void) {
        self.snapshot = snapshot
        self.message = message
        self.onDiscard = onDiscard
        _closeGate = State(initialValue: .init(initialSnapshot: snapshot))
    }

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "편집 중인 변경사항을 버릴까요?",
                isPresented: Binding(
                    get: { closeGate.isConfirmingDiscard },
                    set: { if !$0 { closeGate.continueEditing() } }
                )
            ) {
                Button("변경사항 버리기", role: .destructive, action: onDiscard)
                    .accessibilityIdentifier("monglepet.editor.discardChanges")
                Button("계속 편집", role: .cancel) {
                    closeGate.continueEditing()
                }
                .accessibilityIdentifier("monglepet.editor.continueEditing")
            } message: {
                Text(message)
            }
            .onChange(of: closeRequests.revision) {
                if closeGate.requestClose(currentSnapshot: snapshot) {
                    onDiscard()
                }
            }
    }
}

extension View {
    func protectingEditorDraft<Snapshot: Equatable>(
        _ snapshot: Snapshot,
        message: String,
        onDiscard: @escaping () -> Void
    ) -> some View {
        modifier(EditorDraftProtection(
            snapshot: snapshot,
            message: message,
            onDiscard: onDiscard
        ))
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
        let closeRequests = ImageEditorWindowCloseRequests()
        let editor = ExistingPetFramePickerView(
            petName: petName,
            groups: groups,
            onDismiss: { [weak self] in
                self?.close()
            },
            onImport: onImport
        )
        presentWindow(
            editor.environmentObject(closeRequests),
            title: "현재 펫 프레임에서 추가",
            idealSize: NSSize(width: 1_080, height: 760),
            minimumSize: NSSize(width: 880, height: 620),
            closeRequests: closeRequests
        )
    }

    func presentEditor<Content: View>(
        _ content: Content,
        title: String,
        idealSize: NSSize,
        minimumSize: NSSize
    ) {
        let closeRequests = ImageEditorWindowCloseRequests()
        presentWindow(
            content.environmentObject(closeRequests),
            title: title,
            idealSize: idealSize,
            minimumSize: minimumSize,
            closeRequests: closeRequests
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
        idealSize: NSSize,
        minimumSize: NSSize,
        closeRequests: ImageEditorWindowCloseRequests?
    ) {
        close()

        let ownerWindow = NSApplication.shared.keyWindow
            ?? NSApplication.shared.mainWindow
        let controller = EditorWindowController(
            content: content,
            title: title,
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
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        let targetScreen = ownerWindow?.screen
            ?? NSScreen.main
            ?? NSScreen.screens.first
        let visibleFrame = targetScreen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? CGRect(origin: .zero, size: idealSize)
        window.minSize = NSSize(
            width: min(minimumSize.width, visibleFrame.width),
            height: min(minimumSize.height, visibleFrame.height)
        )
        let parentFrame = ownerWindow?.screen == targetScreen
            ? ownerWindow?.frame
            : nil
        let adjustedFrame = EditorWindowPlacement.frame(
            idealSize: idealSize,
            minimumSize: minimumSize,
            visibleFrame: visibleFrame,
            parentFrame: parentFrame
        )
        window.setFrame(adjustedFrame, display: false)

        super.init(window: window)
        window.delegate = self
        ownerWindow?.addChildWindow(window, ordered: .above)
    }

    required init?(coder: NSCoder) {
        nil
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
