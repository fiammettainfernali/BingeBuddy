import WidgetKit
import SwiftUI
import UIKit

struct UpNextEntry: TimelineEntry {
    let date: Date
    let shows: [UpNextShow]
}

struct UpNextProvider: TimelineProvider {
    func placeholder(in context: Context) -> UpNextEntry {
        UpNextEntry(date: .now, shows: [
            UpNextShow(key: "placeholder", title: "Your show",
                       subtitle: "Next: Episode 5", posterFile: nil)
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (UpNextEntry) -> Void) {
        completion(UpNextEntry(date: .now, shows: WidgetStore.loadShows()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UpNextEntry>) -> Void) {
        let entry = UpNextEntry(date: .now, shows: WidgetStore.loadShows())
        // The app pushes reloads on changes; this is just a staleness fallback.
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(4 * 3600))))
    }
}

struct UpNextWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UpNextEntry

    var body: some View {
        Group {
            if entry.shows.isEmpty {
                emptyView
            } else if family == .systemSmall {
                smallView(entry.shows[0])
            } else {
                mediumView
            }
        }
        .containerBackground(for: .widget) { Color(.systemBackground) }
    }

    private var emptyView: some View {
        VStack(spacing: 6) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Start watching something!")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func smallView(_ show: UpNextShow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            poster(show, width: 44, height: 66)
            Spacer(minLength: 0)
            Text(show.title)
                .font(.footnote.bold())
                .lineLimit(2)
            Text(show.subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private var mediumView: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(entry.shows.prefix(3)) { show in
                HStack(spacing: 10) {
                    poster(show, width: 26, height: 39)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(show.title)
                            .font(.footnote.weight(.semibold))
                            .lineLimit(1)
                        Text(show.subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func poster(_ show: UpNextShow, width: CGFloat, height: CGFloat) -> some View {
        if let file = show.posterFile,
           let url = WidgetStore.posterURL(file),
           let image = UIImage(contentsOfFile: url.path) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            // Diagnostic placeholders: gray = the app never cached a poster for this show;
            // orange = a poster file was recorded but this extension can't load it.
            RoundedRectangle(cornerRadius: 6)
                .fill(.quaternary)
                .frame(width: width, height: height)
                .overlay {
                    Image(systemName: "film")
                        .font(.caption)
                        .foregroundStyle(show.posterFile == nil ? Color.secondary : Color.orange)
                }
        }
    }
}

struct UpNextWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "UpNextWidget", provider: UpNextProvider()) { entry in
            UpNextWidgetView(entry: entry)
        }
        .configurationDisplayName("Up Next")
        .description("Where you are in the shows you're watching.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct BingeBuddyWidgetBundle: WidgetBundle {
    var body: some Widget {
        UpNextWidget()
    }
}
