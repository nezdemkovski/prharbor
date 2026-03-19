import AppKit

private actor ImageCache {
    static let shared = ImageCache()
    private var cache: [URL: NSImage] = [:]

    func get(_ url: URL) -> NSImage? { cache[url] }
    func set(_ url: URL, image: NSImage) { cache[url] = image }
}

extension NSImage {
    static func loadImage(from url: URL) async -> NSImage? {
        if let cached = await ImageCache.shared.get(url) {
            return cached
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else {
            return nil
        }
        guard let image = NSImage(data: data) else { return nil }
        await ImageCache.shared.set(url, image: image)
        return image
    }
}

func prefetchAvatars(_ edges: [Edge]) {
    var seen = Set<String>()
    for edge in edges {
        guard let url = edge.node.author?.avatarUrl,
              seen.insert(url.absoluteString).inserted else { continue }
        Task.detached(priority: .low) {
            _ = await NSImage.loadImage(from: url)
        }
    }
}
