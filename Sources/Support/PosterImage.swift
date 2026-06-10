import SwiftUI
import UIKit

/// In-memory cache of decoded posters so they don't reload/disappear while browsing.
private enum PosterCache {
    static let shared = NSCache<NSURL, UIImage>()
}

/// Loads a poster from a URL with caching and a graceful placeholder.
struct PosterImage: View {
    let url: String?
    var width: CGFloat = 60
    var height: CGFloat = 90

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if failed || url == nil {
                placeholder
            } else {
                ProgressView()
            }
        }
        .frame(width: width, height: height)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: url) { await load() }
    }

    private var placeholder: some View {
        Image(systemName: "film")
            .font(.title2)
            .foregroundStyle(.secondary)
    }

    private func load() async {
        failed = false
        guard let urlString = url, let resolved = URL(string: urlString) else {
            image = nil
            failed = true
            return
        }
        let key = resolved as NSURL
        if let cached = PosterCache.shared.object(forKey: key) {
            image = cached
            return
        }
        image = nil
        do {
            let (data, _) = try await URLSession.shared.data(from: resolved)
            if let loaded = UIImage(data: data) {
                PosterCache.shared.setObject(loaded, forKey: key)
                image = loaded
            } else {
                failed = true
            }
        } catch {
            failed = true
        }
    }
}
