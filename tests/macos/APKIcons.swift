// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import CoreGraphics
import SharedLibrary

@main struct APKIcons {
    static func check(_ yes: Bool, _ message: String) throws {
        guard yes else { throw LibraryFailure(message) }; print("PASS \(message)")
    }
    static func pixel(_ image: CGImage, _ x: Int, _ y: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { p in
            let ctx = CGContext(data: p.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return Array(bytes[(y * image.width + x) * 4 ..< (y * image.width + x) * 4 + 4])
    }
    static func main() async {
        do {
            let args = CommandLine.arguments
            if args.count == 5, args[1] == "--library", args[3] == "--output" {
                let root = LibraryPaths(root: URL(fileURLWithPath: args[2])), output = URL(fileURLWithPath: args[4])
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                let index = try JSONDecoder().decode(LibraryIndex.self, from: Data(contentsOf: root.index))
                for game in index.games {
                    let apks = game.apkNames.map { root.game(game.id).appendingPathComponent($0) }
                    if let bytes = APKIcon.png(apks: apks, fixtureEntry: game.fixture?.icon, read: LibraryRepository.entry),
                       let image = APKIcon.decode(bytes) {
                        try bytes.write(to: output.appendingPathComponent(game.id + ".png"))
                        print("DECODED \(game.title) \(image.width)x\(image.height)")
                    } else { print("UNRESOLVED \(game.title)") }
                }
                return
            }
            guard args.count == 2 else { throw LibraryFailure("Expected icon fixture directory") }
            let cases = URL(fileURLWithPath: args[1])
            func render(_ files: [String]) -> Data? {
                APKIcon.png(apks: files.map { cases.appendingPathComponent($0) }, read: LibraryRepository.entry)
            }
            let bitmap = try render(["manifest-only.apk", "density.apk"]).unwrap("split bitmap")
            let flat = try APKIcon.decode(bitmap).unwrap("bitmap decode")
            try check(flat.width == 108 && pixel(flat, 20, 20) == [0,0,255,255], "density-split-bitmap-resolves-from-base-manifest")
            let adaptive = try render(["base.apk", "layers.apk"]).unwrap("adaptive layers")
            let composed = try APKIcon.decode(adaptive).unwrap("composed decode")
            try check(composed.width == 288 && composed.height == 288, "adaptive-central-72-unit-crop")
            try check(pixel(composed, 144, 144) == [255,0,0,255] && pixel(composed, 10, 10) == [0,0,255,255] &&
                      pixel(composed, 10, 270) == [0,255,0,255], "adaptive-foreground-background-and-orientation")
            let colored = try APKIcon.decode(try render(["base.apk", "color.apk"]).unwrap("color icon")).unwrap("color decode")
            try check(pixel(colored, 10, 10) == [0,0,255,255], "split-background-color-reference")
            try check(render(["base.apk"]) == nil && APKIcon.decode(Data("<xml/>".utf8)) == nil, "unresolved-xml-never-cached-as-image")
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("HuskIconTests-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }
            let paths = LibraryPaths(root: root), repository = try LibraryRepository(paths: paths, trustedFixtureHash: "")
            let game = try await repository.importGame(cases.appendingPathComponent("bitmap.apk"))
            let icon = paths.game(game.id).appendingPathComponent("icon.data")
            try check(APKIcon.decode(try Data(contentsOf: icon)) != nil, "new-import-writes-decodable-png")
            try await repository.update(game.id, muted: true, pauseWhenInactive: true)
            let original = try Data(contentsOf: paths.index)
            try FileManager.default.createDirectory(at: paths.save(game.id), withIntermediateDirectories: true)
            let save = paths.save(game.id).appendingPathComponent("preserve.dat"), saveBytes = Data("existing save".utf8)
            try saveBytes.write(to: save)
            try Data("old binary XML cache".utf8).write(to: icon)
            try FileManager.default.removeItem(at: paths.game(game.id).appendingPathComponent("icon-version.txt"))
            _ = try await repository.games()
            try check(APKIcon.decode(try Data(contentsOf: icon)) != nil && (try Data(contentsOf: paths.index)) == original &&
                      (try Data(contentsOf: save)) == saveBytes, "old-cache-refresh-preserves-index-settings-and-save")
            let date = try icon.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            let reopened = try LibraryRepository(paths: paths, trustedFixtureHash: "")
            _ = try await reopened.games()
            try check(try icon.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate == date,
                      "current-cache-does-not-rewrite-on-reopen")
        } catch { print("FAIL \(error)"); exit(1) }
    }
}
private extension Optional {
    func unwrap(_ message: String) throws -> Wrapped {
        guard let value = self else { throw LibraryFailure(message) }; return value
    }
}
