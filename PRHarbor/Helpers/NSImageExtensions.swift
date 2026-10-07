import AppKit
import ImageIO

/// Decode at the largest avatar's display resolution before publishing to SwiftUI.
/// 96 pixels covers the 30-point avatar even at 3x without retaining a full-size JPEG.
nonisolated enum AvatarBitmap {
    static let maximumPixelSize = 96

    static func image(from data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary),
              let bitmap = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        let image = NSImage(size: NSSize(width: bitmap.width, height: bitmap.height))
        image.addRepresentation(NSBitmapImageRep(cgImage: bitmap))
        return image
    }
}

/// Bounded cache and one download per URL, shared by author and event avatars.
actor AvatarImageCache {
    static let shared = AvatarImageCache()
    private let cache = NSCache<NSURL, NSImage>()
    private var flights: [URL: Task<NSImage?, Never>] = [:]
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
        cache.countLimit = 128
        cache.totalCostLimit = 32 * 1_024 * 1_024
    }

    func image(for url: URL) async -> NSImage? {
        if let image = cache.object(forKey: url as NSURL) { return image }
        if let flight = flights[url] { return await flight.value }
        let session = session
        let flight = Task { await Self.download(url, session: session) }
        flights[url] = flight
        let image = await flight.value
        flights[url] = nil
        if let image {
            let pixels = image.representations.reduce(0) { $0 + max(1, $1.pixelsWide) * max(1, $1.pixelsHigh) * 4 }
            cache.setObject(image, forKey: url as NSURL, cost: pixels)
        }
        return image
    }

    @concurrent private static func download(_ url: URL, session: URLSession) async -> NSImage? {
        guard url.scheme == "https",
              let (data, response) = try? await session.data(from: url),
              let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { return nil }
        return AvatarBitmap.image(from: data)
    }
}

extension NSImage {
    static func loadImage(from url: URL) async -> NSImage? {
        await AvatarImageCache.shared.image(for: url)
    }
}
