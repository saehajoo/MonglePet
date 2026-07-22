import AppKit
import SwiftUI

struct PetAnimationPreviewView: NSViewRepresentable {
    let item: PetLibraryItem
    let motionID: String

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
        context.coordinator.update(item: item, motionID: motionID, view: view)
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

        func attach(to view: PetOverlayView) {
            framePlayer = FramePlayer { [weak view] frame in
                view?.display(frame)
            }
        }

        func update(
            item: PetLibraryItem,
            motionID: String,
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
                } catch {
                    framePlayer?.stop()
                    currentSelection = nil
                    currentDefinition = nil
                    currentMotionID = nil
                    return
                }
            }

            guard currentMotionID != motionID,
                  let motion = item.definition.motion(id: motionID)
                    ?? item.definition.defaultMotion else {
                return
            }
            currentMotionID = motion.id
            framePlayer?.play(motion)
        }

        func stop() {
            framePlayer?.stop()
        }
    }
}
