import AppKit
import ImageIO
import TopsideCore

/// Downloads and downsamples Spotify album art to the size it is drawn at. Bounded cache, one in-flight request,
/// cancelled when the track changes. Only Spotify's own CDN hosts are fetched.
struct LoadedArtwork {
    let image: NSImage
    /// Plain average colour of the artwork (see `ArtworkTint`); nil when it could not be sampled.
    let average: TintColor?
}

@MainActor
final class ArtworkLoader {
    private var cache = BoundedCache<URL, LoadedArtwork>(capacity: 6)
    private var task: Task<Void, Never>?

    func cancel() { task?.cancel(); task = nil }

    func load(_ url: URL, points: CGFloat, scale: CGFloat, apply: @escaping @MainActor (NSImage, TintColor?) -> Void) {
        cancel()
        guard ArtworkFetcher.isAllowed(url) else { Log.info("artwork host not allowed"); return }
        if let hit = cache.value(for: url) { apply(hit.image, hit.average); return }
        let maxPixel = Int(ceil(points * max(scale, 1)))
        task = Task { [weak self] in
            guard let cg = await ArtworkFetcher.fetch(url, maxPixel: maxPixel), !Task.isCancelled else { return }
            let image = NSImage(cgImage: cg, size: NSSize(width: points, height: points))
            // Sampled once per artwork, from the already-downsampled thumbnail (at most ~112 px a side).
            let average = ArtworkTintSampler.average(of: cg)
            self?.cache.insert(LoadedArtwork(image: image, average: average), for: url)
            apply(image, average)
        }
    }
}

enum ArtworkFetcher {
    private static let session = URLSession(configuration: .ephemeral)   // no disk cache

    static func isAllowed(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return host == "scdn.co" || host.hasSuffix(".scdn.co") || host.hasSuffix(".spotifycdn.com")
    }

    static func fetch(_ url: URL, maxPixel: Int) async -> CGImage? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              data.count < 3_000_000,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}

enum ArtworkTintSampler {
    /// Draws the artwork into a small premultiplied RGBA buffer and averages it. Nothing is read back
    /// from disk or the network, and nothing is kept: only the resulting colour.
    static func average(of image: CGImage, side: Int = 32) -> TintColor? {
        var bytes = [UInt8](repeating: 0, count: side * side * 4)
        let drew = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8,
                                          bytesPerRow: side * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drew else { return nil }
        return ArtworkTint.average(rgba: bytes, width: side, height: side)
    }
}
