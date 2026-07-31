import AppKit
import SwiftUI

struct PetAnimationPreviewView: NSViewRepresentable {
    let item: PetLibraryItem
    let motionID: String
    let playsAnimation: Bool

    init(
        item: PetLibraryItem,
        motionID: String,
        playsAnimation: Bool = true
    ) {
        self.item = item
        self.motionID = motionID
        self.playsAnimation = playsAnimation
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PetOverlayView {
        guard
            let placeholderImage = NSImage(named: "PlaceholderPet"),
            let view = PetOverlayView(
                atlasID: BuiltInPet.atlasID,
                image: placeholderImage
            )
        else {
            fatalError("The built-in MonglePet preview image is missing or invalid.")
        }
        view.allowsWindowDragging = false
        view.setAccessibilityIdentifier("monglepet.settings.petPreview")
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ view: PetOverlayView, context: Context) {
        context.coordinator.update(
            item: item,
            motionID: motionID,
            playsAnimation: playsAnimation,
            view: view
        )
    }

    static func dismantleNSView(_ view: PetOverlayView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator {
        private var framePlayer: FramePlayer?
        private var currentSelection: PetLibrarySelection?
        private var currentDefinition: PetDefinition?
        private var currentMotionID: String?
        private var currentPlaysAnimation: Bool?

        func attach(to view: PetOverlayView) {
            framePlayer = FramePlayer { [weak view] frame in
                view?.display(frame)
            }
        }

        func update(
            item: PetLibraryItem,
            motionID: String,
            playsAnimation: Bool,
            view: PetOverlayView
        ) {
            let needsResources = currentSelection != item.selection
                || currentDefinition != item.definition
            if needsResources {
                do {
                    let atlases = try PetPresentationResourceLoader.loadAtlases(for: item)
                    view.replaceAtlases(
                        atlases,
                        accessibilityLabel: "\(item.metadata.displayName) 애니메이션 미리보기"
                    )
                    currentSelection = item.selection
                    currentDefinition = item.definition
                    currentMotionID = nil
                    currentPlaysAnimation = nil
                } catch {
                    framePlayer?.stop()
                    view.replaceAtlases(
                        [],
                        accessibilityLabel:
                            "\(item.metadata.displayName) 미리보기를 불러올 수 없음"
                    )
                    currentSelection = nil
                    currentDefinition = nil
                    currentMotionID = nil
                    currentPlaysAnimation = nil
                    return
                }
            }

            guard
                currentMotionID != motionID
                    || currentPlaysAnimation != playsAnimation,
                let motion = item.definition.motion(id: motionID)
                    ?? item.definition.defaultMotion
            else {
                return
            }
            currentMotionID = motion.id
            currentPlaysAnimation = playsAnimation
            if playsAnimation {
                framePlayer?.play(motion)
            } else {
                framePlayer?.stop()
                if let firstFrame = motion.frames.first {
                    _ = view.display(firstFrame)
                }
            }
        }

        func stop() {
            framePlayer?.stop()
        }
    }
}
