import AppKit
import ImageIO
import TopsideCore

/// Downloads and downsamples Spotify album art to the size it is drawn at. Bounded cache, one in-flight request,
/// cancelled when the track changes. Only Spotify's own CDN hosts are fetched.
@MainActor
final class ArtworkLoader {
    private var cache = BoundedCache<URL, NSImage>(capacity: 6)
    private var task: Task<Void, Never>?

    func cancel() { task?.cancel(); task = nil }

    func load(_ url: URL, points: CGFloat, scale: CGFloat, apply: @escaping @MainActor (NSImage) -> Void) {
        cancel()
        guard ArtworkFetcher.isAllowed(url) else { Log.info("artwork host not allowed"); return }
        if let hit = cache.value(for: url) { apply(hit); return }
        let maxPixel = Int(ceil(points * max(scale, 1)))
        task = Task { [weak self] in
            guard let cg = await ArtworkFetcher.fetch(url, maxPixel: maxPixel), !Task.isCancelled else { return }
            let image = NSImage(cgImage: cg, size: NSSize(width: points, height: points))
            self?.cache.insert(image, for: url)
            apply(image)
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
