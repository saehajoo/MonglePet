import AppKit

@MainActor
final class PetPresentationResources {
    let atlases: [PetAtlasImage]

    private var alphaMasks: [PetAlphaMaskCacheKey: PetFrameAlphaMask] = [:]
    private var alphaMaskOrder: [PetAlphaMaskCacheKey] = []
    private let maximumAlphaMaskCount: Int
    private let alphaMaskBuilder: (CGImage, PixelRect) -> PetFrameAlphaMask?

    init(
        atlases: [PetAtlasImage],
        maximumAlphaMaskCount: Int = 256,
        alphaMaskBuilder: @escaping (CGImage, PixelRect)
            -> PetFrameAlphaMask? = { image, sourceRect in
                PetFrameAlphaMaskBuilder.make(
                    atlasImage: image,
                    sourceRect: sourceRect
                )
            }
    ) {
        self.atlases = atlases
        self.maximumAlphaMaskCount = max(maximumAlphaMaskCount, 1)
        self.alphaMaskBuilder = alphaMaskBuilder
    }

    func alphaMask(
        for frame: MotionFrame,
        atlas: PetAtlasImage
    ) -> PetFrameAlphaMask? {
        let key = PetAlphaMaskCacheKey(
            atlasID: frame.atlasID,
            sourceRect: frame.sourceRect
        )
        if let cached = alphaMasks[key] {
            return cached
        }
        guard let mask = alphaMaskBuilder(atlas.image, frame.sourceRect) else {
            return nil
        }
        if alphaMasks.count >= maximumAlphaMaskCount,
           let oldestKey = alphaMaskOrder.first {
            alphaMasks.removeValue(forKey: oldestKey)
            alphaMaskOrder.removeFirst()
        }
        alphaMasks[key] = mask
        alphaMaskOrder.append(key)
        return mask
    }

    var cachedAlphaMaskCount: Int {
        alphaMasks.count
    }
}

private nonisolated struct PetAlphaMaskCacheKey: Hashable, Sendable {
    let atlasID: String
    let x: Int
    let y: Int
    let width: Int
    let height: Int

    init(atlasID: String, sourceRect: PixelRect) {
        self.atlasID = atlasID
        x = sourceRect.x
        y = sourceRect.y
        width = sourceRect.width
        height = sourceRect.height
    }
}

@MainActor
final class PetPresentationResourceCache {
    private final class WeakResources {
        weak var value: PetPresentationResources?

        init(_ value: PetPresentationResources) {
            self.value = value
        }
    }

    private var resourcesBySelection:
        [PetLibrarySelection: WeakResources] = [:]
    private(set) var resourceLoadCount = 0

    func builtInResources() throws -> PetPresentationResources {
        if let cached = resourcesBySelection[.builtIn]?.value {
            return cached
        }
        let resources = PetPresentationResources(
            atlases: try PetPresentationResourceLoader.loadBuiltInAtlases()
        )
        resourcesBySelection[.builtIn] = WeakResources(resources)
        resourceLoadCount += 1
        return resources
    }

    func resources(for item: PetLibraryItem) throws
        -> PetPresentationResources {
        if item.isBuiltIn {
            return try builtInResources()
        }
        if let cached = resourcesBySelection[item.selection]?.value {
            return cached
        }
        let resources = PetPresentationResources(
            atlases: try PetPresentationResourceLoader.loadAtlases(for: item)
        )
        resourcesBySelection[item.selection] = WeakResources(resources)
        resourceLoadCount += 1
        return resources
    }

    func invalidate(_ selection: PetLibrarySelection) {
        resourcesBySelection.removeValue(forKey: selection)
    }

    func removeReleasedEntries() {
        resourcesBySelection = resourcesBySelection.filter {
            $0.value.value != nil
        }
    }

    var liveResourceCount: Int {
        resourcesBySelection.values.reduce(into: 0) { count, box in
            if box.value != nil {
                count += 1
            }
        }
    }
}
