import AppKit
import SwilClipCore

/// Makes and caches the small image previews shown in list rows.
///
/// ## Why a thumbnail at all
///
/// v1 rendered a preview by holding the whole base64 image in the row it drew
/// from — forty rows meant forty full screenshots resident. v2 fixed that by
/// moving the bytes to a sidecar file, and lost the preview along with it: image
/// rows showed only `1024×1024 PNG`.
///
/// Neither extreme is right. A thumbnail is the middle: a few kilobytes, made
/// once at capture, stored in the row, and cheap enough to hold for the entire
/// list. Row-rendering cost stays decoupled from the size of what was copied.
enum Thumbnail {
    /// Longest edge, in pixels.
    ///
    /// The chip is 20 pt at Small and 30 pt at Large; on a 2× display that is
    /// 60 px. 96 leaves headroom for a future larger preview without a second
    /// migration, and still encodes to a few kilobytes.
    static let maxPixelSize: CGFloat = 96

    /// JPEG rather than PNG: these are photographic previews at a size where
    /// nobody counts artefacts, and JPEG is roughly an order of magnitude
    /// smaller. Quality 0.7 is where the size curve flattens.
    private static let compressionQuality = 0.7

    /// Build a thumbnail from full image data. Returns `nil` if the bytes are
    /// not a decodable image — a corrupt payload must not take down a capture.
    static func make(from imageData: Data) -> Data? {
        guard let source = NSBitmapImageRep(data: imageData) else { return nil }

        let width = CGFloat(source.pixelsWide)
        let height = CGFloat(source.pixelsHigh)
        guard width > 0, height > 0 else { return nil }

        // Never upscale: a 16×16 favicon should stay 16×16 rather than become a
        // blurry 96×96.
        let scale = min(1, maxPixelSize / max(width, height))
        let target = NSSize(width: (width * scale).rounded(), height: (height * scale).rounded())

        guard let scaled = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(target.width),
            pixelsHigh: Int(target.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        scaled.size = target

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: scaled) else { return nil }
        NSGraphicsContext.current = context
        context.imageInterpolation = .high
        source.draw(in: NSRect(origin: .zero, size: target))
        context.flushGraphics()

        return scaled.representation(
            using: .jpeg, properties: [.compressionFactor: compressionQuality]
        )
    }
}

/// Decoded thumbnails, kept so a row does not re-decode its JPEG on every body
/// evaluation.
///
/// `LazyVStack` renders only what is visible, but SwiftUI re-evaluates those
/// bodies on every selection change — a dozen decodes per arrow key. Each is
/// only tens of microseconds, and a dozen of them every keypress is exactly the
/// kind of cost that turns into a dropped frame for no reason.
///
/// `NSCache` because it evicts under memory pressure on its own, which is the
/// correct behaviour for a pure cache: losing an entry costs one re-decode.
@MainActor
enum ThumbnailCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        // Generous: a thumbnail decodes to roughly 96×96×4 bytes ≈ 37 KB, so
        // even a full history of images is a couple of megabytes.
        cache.countLimit = 256
        return cache
    }()

    static func image(for clip: ClipItem) -> NSImage? {
        guard let data = clip.thumbnail else { return nil }
        let key = clip.id as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let image = NSImage(data: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }

    /// Drop a decoded entry. Called when a clip is deleted so the cache cannot
    /// outlive the row — the encoded bytes go with the row automatically, since
    /// they are a column rather than a separate file.
    static func forget(id: String) {
        cache.removeObject(forKey: id as NSString)
    }
}
