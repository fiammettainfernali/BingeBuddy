import SwiftUI

struct InboxView: View {
    @EnvironmentObject private var suggestions: SuggestionStore
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var session: Session

    private var pending: [Suggestion] {
        suggestions.incoming.filter { $0.status == "pending" }
    }

    var body: some View {
        NavigationStack {
            Group {
                if session.household == nil {
                    ContentUnavailableView(
                        "Set up your household",
                        systemImage: "person.2",
                        description: Text("Create or join a household in the Profile tab first."))
                } else if pending.isEmpty {
                    ContentUnavailableView(
                        "No suggestions",
                        systemImage: "tray",
                        description: Text("Show ideas your partner sends you will land here."))
                } else {
                    List(pending) { suggestion in
                        SuggestionRow(
                            suggestion: suggestion,
                            onAccept: {
                                library.add(result: suggestion.asSearchResult, state: .wantToWatch, details: nil)
                                suggestions.dismiss(suggestion)
                            },
                            onDismiss: {
                                // A dismissal is a taste signal: don't recommend this later.
                                library.hide(mediaKey: suggestion.mediaKey)
                                suggestions.dismiss(suggestion)
                            })
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Inbox")
        }
    }
}

private struct SuggestionRow: View {
    let suggestion: Suggestion
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                PosterImage(url: suggestion.posterURL)
                VStack(alignment: .leading, spacing: 4) {
                    Text(suggestion.title).font(.headline).lineLimit(2)
                    Text(suggestion.mediaType.label + (suggestion.year.map { " · \($0)" } ?? ""))
                        .font(.caption).foregroundStyle(.secondary)
                    Text("From \(suggestion.fromName)")
                        .font(.caption2).foregroundStyle(.secondary)
                    if !suggestion.message.isEmpty {
                        Text("“\(suggestion.message)”")
                            .font(.caption).italic()
                    }
                }
                Spacer(minLength: 0)
            }

            HStack {
                Button(action: onAccept) {
                    Label("Add to Want", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(role: .cancel, action: onDismiss) {
                    Label("Dismiss", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.vertical, 6)
    }
}
