import SwiftUI

/// Loads a poster from a URL with a graceful placeholder.
struct PosterImage: View {
    let url: String?
    var width: CGFloat = 60
    var height: CGFloat = 90

    var body: some View {
        Group {
            if let url, let resolved = URL(string: url) {
                AsyncImage(url: resolved) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholder
                    case .empty:
                        ProgressView()
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: width, height: height)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var placeholder: some View {
        Image(systemName: "film")
            .font(.title2)
            .foregroundStyle(.secondary)
    }
}
