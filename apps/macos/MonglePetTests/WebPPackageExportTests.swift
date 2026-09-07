import Foundation
import ImageIO
import XCTest
@testable import MonglePet

final class WebPPackageExportTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func testExportImportEditAndReexportPreservesFramesProfileAndOriginal() throws {
        let source = try fixture()
        let originalManifest = try Data(contentsOf: source.rootURL.appendingPathComponent("pet.json"))
        let originalAtlas = try Data(contentsOf: source.package.atlases[0].fileURL)
        let originalDate = try source.package.atlases[0].fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let profile = RecommendedPetProfile(
            mode: .manual, manualSequenceID: "default",
            sequences: [BehaviorSequence(id: "default", steps: [BehaviorStep(motionID: "idle", repeatCount: 2)], repeats: true)],
            automaticRules: [], movement: .default, pettingMotionID: nil
        )
        let archive = root.appendingPathComponent("webp.monglepet")
        try exporter().export(source, recommendedProfile: profile, to: archive)
        let extracted = try extract(archive, name: "roundtrip")
        let loaded = try PetPackageLoader().loadPackage(at: extracted)
        XCTAssertEqual(loaded.definition, source.package.definition)
        XCTAssertEqual(loaded.metadata, source.package.metadata)
        XCTAssertEqual(loaded.atlases.map(\.format), [.webP])
        XCTAssertEqual(loaded.previewURL.pathExtension, "png")
        XCTAssertNotEqual(loaded.atlases[0].fileURL.deletingLastPathComponent().lastPathComponent, "_monglepet_webp")
        XCTAssertEqual(LosslessWebPCodec.renderedPixels(originalAtlas),
                       LosslessWebPCodec.renderedPixels(try Data(contentsOf: loaded.atlases[0].fileURL)))
        XCTAssertEqual(try RecommendedPetProfileCodec.decode(
            Data(contentsOf: extracted.appendingPathComponent("recommended-profile.json")), for: loaded.definition
        ), profile)
        if let fixturePath = ProcessInfo.processInfo.environment["MONGLEPET_WEBP_QA_FIXTURE_DIRECTORY"] {
            let fixtureRoot = URL(fileURLWithPath: fixturePath, isDirectory: true)
            try FileManager.default.createDirectory(at: fixtureRoot, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: source.rootURL, to: fixtureRoot.appendingPathComponent("source"))
            try FileManager.default.copyItem(at: archive, to: fixtureRoot.appendingPathComponent("lossless-webp.monglepet"))
        }

        let store = PetLibraryStore(libraryRootURL: root.appendingPathComponent("Library"))
        let imported = try store.install(packageAt: extracted, validatedPackage: loaded, mode: .rejectDuplicate)
        let editor = UserPetPackageEditor(store: store)
        let editable = try editor.makeEditable(imported)
        let edited = try editor.updateAnimation(.init(
            animationID: "idle", animationName: "idle", loops: true,
            frames: [
                .init(source: .existing(index: 0), durationMilliseconds: 450),
                .init(source: .existing(index: 1), durationMilliseconds: 275)
            ]
        ), for: editable)
        let editedMotion = try XCTUnwrap(edited.package.definition.motion(id: "idle"))
        XCTAssertEqual(editedMotion.frames.map(\.duration), [.milliseconds(450), .milliseconds(275)])
        // Existing WebP frames use the normal PNG editor; compare rendered frame results.
        let oldImage = try image(at: loaded.atlases[0].fileURL)
        for (index, frame) in editedMotion.frames.enumerated() {
            let atlas = try XCTUnwrap(edited.package.atlases.first { $0.id == frame.atlasID })
            let updatedImage = try image(at: atlas.fileURL)
            let oldRect = CGRect(x: index * 64, y: 0, width: 64, height: 128)
            let oldFrame = try XCTUnwrap(oldImage.cropping(to: oldRect))
            let newFrame = try XCTUnwrap(updatedImage.cropping(to: CGRect(
                x: frame.sourceRect.x, y: frame.sourceRect.y,
                width: frame.sourceRect.width, height: frame.sourceRect.height
            )))
            XCTAssertEqual(oldFrame.width, newFrame.width)
            XCTAssertEqual(oldFrame.height, newFrame.height)
            XCTAssertEqual(render(oldFrame), render(newFrame))
        }
        let again = root.appendingPathComponent("again.monglepet")
        try exporter().export(edited, recommendedProfile: profile, to: again)
        let againRoot = try extract(again, name: "again")
        XCTAssertEqual(try PetPackageLoader().loadPackage(at: againRoot).definition, edited.package.definition)
        XCTAssertEqual(try Data(contentsOf: source.rootURL.appendingPathComponent("pet.json")), originalManifest)
        XCTAssertEqual(try Data(contentsOf: source.package.atlases[0].fileURL), originalAtlas)
        XCTAssertEqual(try source.package.atlases[0].fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, originalDate)
    }

    func testPNGOnlyPolicyAndFailedWebPCandidateKeepPNGPaths() throws {
        let source = try fixture()
        for (name, policy) in [("disabled", PetExportImagePolicy.pngOnly), ("failure", .losslessWebP)] {
            let file = root.appendingPathComponent("\(name).monglepet")
            try PetPackageExporter(
                imagePolicy: policy,
                webPOptimizer: WebPExportOptimizer(cacheDirectory: nil, encoder: { _ in throw CocoaError(.coderInvalidValue) }),
                temporaryDirectoryURL: root
            ).export(source, to: file)
            let loaded = try PetPackageLoader().loadPackage(at: extract(file, name: name))
            XCTAssertEqual(loaded.atlases.map(\.format), [.png])
            XCTAssertEqual(loaded.atlases[0].fileURL.lastPathComponent, "source.png")
            XCTAssertEqual(loaded.definition, source.package.definition)
        }
    }

    func testOptionalLocalPackageAudit() throws {
        guard let path = ProcessInfo.processInfo.environment["MONGLEPET_WEBP_QA_PACKAGE"] else {
            throw XCTSkip("Optional local package audit; no user asset is stored in the repository.")
        }
        let archiveURL = URL(fileURLWithPath: path)
        let original = try Data(contentsOf: archiveURL)
        let input = try extract(archiveURL, name: "input")
        let loaded = try PetPackageLoader().loadPackage(at: input)
        let installed = InstalledPetPackage(installationID: UUID(), rootURL: input, package: loaded)
        let profileURL = input.appendingPathComponent("recommended-profile.json")
        let profile = FileManager.default.fileExists(atPath: profileURL.path)
            ? try RecommendedPetProfileCodec.decode(Data(contentsOf: profileURL), for: loaded.definition) : nil
        let destination = root.appendingPathComponent("audit.monglepet")
        let start = Date()
        try exporter().export(installed, recommendedProfile: profile, to: destination)
        let elapsed = Date().timeIntervalSince(start)
        let repeated = root.appendingPathComponent("audit-repeated.monglepet")
        let repeatStart = Date()
        try exporter().export(installed, recommendedProfile: profile, to: repeated)
        let repeatElapsed = Date().timeIntervalSince(repeatStart)
        let output = try PetPackageLoader().loadPackage(at: extract(destination, name: "output"))
        XCTAssertEqual(output.definition, loaded.definition)
        XCTAssertTrue(output.atlases.contains { $0.format == .webP })
        for atlas in loaded.atlases {
            let target = try XCTUnwrap(output.atlases.first { $0.id == atlas.id })
            XCTAssertEqual(LosslessWebPCodec.renderedPixels(try Data(contentsOf: atlas.fileURL)),
                           LosslessWebPCodec.renderedPixels(try Data(contentsOf: target.fileURL)))
        }
        XCTAssertEqual(try Data(contentsOf: archiveURL), original)
        let bytes = try Data(contentsOf: destination).count
        print("WebP local audit: \(original.count) -> \(bytes) bytes; first \(elapsed)s, cached \(repeatElapsed)s; \(output.atlases.filter { $0.format == .webP }.count) WebP atlases")
    }

    private func fixture() throws -> InstalledPetPackage {
        let package = root.appendingPathComponent("source")
        try FileManager.default.createDirectory(at: package.appendingPathComponent("assets/_monglepet_webp"), withIntermediateDirectories: true)
        try WebPExportFixture.png(width: 16, height: 16).write(to: package.appendingPathComponent("preview.png"))
        try WebPExportFixture.png().write(to: package.appendingPathComponent("assets/_monglepet_webp/source.png"))
        let manifest = PetPackageManifest(
            formatVersion: 1, id: "com.example.webp", displayName: "WebP 검증", version: "1.0.0", author: "테스트",
            description: nil, previewPath: "preview.png", defaultMotion: "idle",
            atlases: [.init(id: "main", path: "assets/_monglepet_webp/source.png", pixelWidth: 128, pixelHeight: 128)],
            motions: [.init(id: "idle", atlas: "main", loop: true, frames: [
                .init(x: 0, y: 0, width: 64, height: 128, durationMs: 450),
                .init(x: 64, y: 0, width: 64, height: 128, durationMs: 275)
            ])]
        )
        try JSONEncoder().encode(manifest).write(to: package.appendingPathComponent("pet.json"))
        return InstalledPetPackage(installationID: UUID(), rootURL: package, package: try PetPackageLoader().loadPackage(at: package))
    }

    private func exporter() -> PetPackageExporter {
        PetPackageExporter(imagePolicy: .losslessWebP,
                           webPOptimizer: WebPExportOptimizer(cacheDirectory: root.appendingPathComponent("cache")),
                           temporaryDirectoryURL: root)
    }

    private func extract(_ archive: URL, name: String) throws -> URL {
        let workspace = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false)
        return try PetPackageArchiveExtractor().extractArchive(at: archive, into: workspace)
    }

    private func image(at url: URL) throws -> CGImage {
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    private func render(_ image: CGImage) -> Data? {
        var data = Data(count: image.width * image.height * 4)
        let ok = data.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                                          bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        return ok ? data : nil
    }
}
