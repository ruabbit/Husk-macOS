// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Resolve the base manifest against every split's resource table. Drawables
/// and their layers may live in different APKs; a label in base is not a stop condition.
enum APKIcon {
    static let version = 1
    typealias ReadEntry = (URL, String, Int) -> Data?

    static func png(apks: [URL], fixtureEntry: String? = nil, read: ReadEntry) -> Data? {
        func entry(_ name: String, limit: Int = 16 << 20) -> Data? {
            for apk in apks { if let bytes = read(apk, name, limit) { return bytes } }
            return nil
        }
        if let fixtureEntry, let data = entry(fixtureEntry), let image = decode(data) { return encode(image) }
        guard let base = apks.first, let manifest = read(base, "AndroidManifest.xml", 8 << 20) else { return nil }
        var tables = [Data](), total = 0
        for apk in apks {
            guard let data = read(apk, "resources.arsc", 64 << 20) else { continue }
            total += data.count
            guard total <= 128 << 20 else { return nil }
            tables.append(data)
        }
        func picture(_ id: UInt32?) -> CGImage? {
            guard let id else { return nil }
            for table in tables {
                if let path = ApkMetadata.bitmap(for: id, resources: table), !path.hasSuffix(".xml"),
                   let data = entry(path), let image = decode(data) { return image }
            }
            return nil
        }
        var attempted = Set<String>()
        for table in tables {
            guard let path = ApkMetadata.read(manifest: manifest, resources: table).iconEntry,
                  attempted.insert(path).inserted, let data = entry(path) else { continue }
            if !path.hasSuffix(".xml") {
                if let image = decode(data) { return encode(image) }
                continue
            }
            guard ApkMetadata.elements(data).contains(where: { $0.name == "adaptive-icon" }) else { continue }
            let layers = ApkMetadata.adaptiveLayers(data)
            let fore = picture(layers.foreground), back = picture(layers.background)
            var color = layers.backgroundColor
            if color == nil, back == nil, let id = layers.background {
                color = tables.lazy.compactMap { ApkMetadata.color(for: id, resources: $0) }.first
            }
            // Do not turn an unresolved foreground into a misleading blank tile.
            guard fore != nil || (layers.foreground == nil && back != nil) else { continue }
            if let composed = compose(foreground: fore, background: back, color: color) { return encode(composed) }
        }
        return nil
    }

    static func decode(_ data: Data) -> CGImage? {
        guard data.count <= 16 << 20, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        // Creating an image source alone does not prove that XML or corrupt data
        // is a picture. Decode an actual bounded thumbnail before caching it.
        return CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 432,
            kCGImageSourceShouldCacheImmediately: true
        ] as CFDictionary)
    }

    private static func encode(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    private static func compose(foreground: CGImage?, background: CGImage?, color: UInt32?) -> CGImage? {
        // Same 108-unit canvas / central 72-unit crop as the upstream launcher.
        guard let context = CGContext(data: nil, width: 288, height: 288, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        if let color = color ?? (background == nil ? 0xffffffff : nil) {
            context.setFillColor(red: CGFloat((color >> 16) & 255) / 255, green: CGFloat((color >> 8) & 255) / 255,
                                 blue: CGFloat(color & 255) / 255, alpha: CGFloat(color >> 24) / 255)
            context.fill(CGRect(x: 0, y: 0, width: 288, height: 288))
        }
        context.interpolationQuality = .high
        let canvas = CGRect(x: -72, y: -72, width: 432, height: 432)
        if let background { context.draw(background, in: canvas) }
        if let foreground { context.draw(foreground, in: canvas) }
        return context.makeImage()
    }
}
