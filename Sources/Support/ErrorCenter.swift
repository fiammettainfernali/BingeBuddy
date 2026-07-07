import Foundation

/// One shared surface for "a background write failed" so cloud errors are never silent.
/// Stores report into it; RootView shows a single alert.
@MainActor
final class ErrorCenter: ObservableObject {
    static let shared = ErrorCenter()
    @Published var message: String?

    func report(_ text: String) {
        message = text
    }
}
