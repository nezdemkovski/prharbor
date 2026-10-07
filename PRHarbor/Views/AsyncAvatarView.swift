import SwiftUI

struct AsyncAvatarView: View, Equatable {
    let url: URL?
    @State private var image: NSImage?
    @State private var loadedURL: URL?

    nonisolated static func == (lhs: AsyncAvatarView, rhs: AsyncAvatarView) -> Bool {
        lhs.url == rhs.url
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .foregroundStyle(.quaternary)
            }
        }
        .clipShape(Circle())
        .task(id: url) {
            // Lazy rows may reappear with their state intact. Reuse the decoded
            // image instead of clearing it and scheduling another UI update.
            if image != nil, loadedURL == url { return }
            image = nil
            loadedURL = nil
            guard let url else { return }
            let loaded = await NSImage.loadImage(from: url)
            guard !Task.isCancelled else { return }
            image = loaded
            loadedURL = url
        }
    }
}
