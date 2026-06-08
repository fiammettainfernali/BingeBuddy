import Foundation

enum MediaType: String, Codable, CaseIterable, Hashable, Sendable {
    case movie
    case tv
    case anime

    var label: String {
        switch self {
        case .movie: return "Movie"
        case .tv: return "TV"
        case .anime: return "Anime"
        }
    }
}

enum WatchState: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case wantToWatch
    case watching
    case finished
    case dropped

    var id: String { rawValue }

    var label: String {
        switch self {
        case .wantToWatch: return "Want"
        case .watching: return "Watching"
        case .finished: return "Finished"
        case .dropped: return "Dropped"
        }
    }

    var systemImage: String {
        switch self {
        case .wantToWatch: return "bookmark"
        case .watching: return "play.circle"
        case .finished: return "checkmark.circle"
        case .dropped: return "xmark.circle"
        }
    }
}
