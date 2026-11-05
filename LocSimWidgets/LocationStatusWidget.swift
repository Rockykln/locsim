import SwiftUI
import WidgetKit

/// Home Screen widget: whether a location is simulated and where; the medium size also lists
/// favorites that open LocSim and set them. Widgets cannot reach the device themselves, so
/// every action goes through the app.
struct LocationStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.kind, provider: SnapshotProvider()) { entry in
            LocationStatusView(snapshot: entry.snapshot)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Location Status")
        .description("Shows whether a location is simulated. Tap a favorite to set it in LocSim.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

/// The app reloads the widget when something changes, so one entry is enough.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(SnapshotEntry(date: Date(), snapshot: WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        completion(Timeline(entries: [SnapshotEntry(date: Date(), snapshot: WidgetSnapshot.load())], policy: .never))
    }
}

private struct LocationStatusView: View {
    let snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .systemMedium {
            HStack(alignment: .top, spacing: 14) {
                status
                    .frame(maxWidth: .infinity, alignment: .leading)
                favorites
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            status
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var status: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: snapshot.active == nil ? "location.slash" : "location.fill")
                .font(.title3)
                .foregroundStyle(snapshot.active == nil ? Color.secondary : Color.blue)
                .accessibilityHidden(true)
            Spacer(minLength: 4)
            if let active = snapshot.active {
                Text("Simulated location")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                Text(active.name)
                    .font(.headline)
                    .lineLimit(2)
                Text(active.coordinate)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Text("Not simulated")
                    .font(.headline)
                Text("The real location is in use.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var favorites: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Favorites")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            if snapshot.favorites.isEmpty {
                Text("No Favorites")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(snapshot.favorites.prefix(3)) { favorite in
                    Link(destination: WidgetSnapshot.url(forFavorite: favorite.id)) {
                        Label {
                            Text(favorite.name)
                                .font(.subheadline)
                                .lineLimit(1)
                        } icon: {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                        }
                    }
                    .accessibilityHint(Text("Opens LocSim and sets this location"))
                }
            }
        }
    }
}
