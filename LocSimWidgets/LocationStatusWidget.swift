import SwiftUI
import WidgetKit

/// Home Screen widget: whether a location is simulated and where; the medium size also lists
/// favorites that open LocSim and set them. Widgets cannot reach the device themselves, so
/// every action goes through the app.
struct LocationStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.kind, provider: SnapshotProvider()) { entry in
            LocationStatusView(snapshot: entry.snapshot, stale: entry.stale)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Location Status")
        .description("Shows whether a location is simulated. Tap a favorite to set it in LocSim.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryInline, .accessoryRectangular, .accessoryCircular])
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    var stale = false
}

/// The app reloads the widget when something changes. A second entry turns it outdated in
/// case LocSim ends without saying so, like the Live Activity.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        completion(entries(WidgetSnapshot.load())[0])
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        completion(Timeline(entries: entries(WidgetSnapshot.load()), policy: .never))
    }

    private func entries(_ snapshot: WidgetSnapshot) -> [SnapshotEntry] {
        let now = Date()
        guard snapshot.active != nil, let until = snapshot.freshUntil else {
            return [SnapshotEntry(date: now, snapshot: snapshot)]
        }
        if until <= now { return [SnapshotEntry(date: now, snapshot: snapshot, stale: true)] }
        return [SnapshotEntry(date: now, snapshot: snapshot), SnapshotEntry(date: until, snapshot: snapshot, stale: true)]
    }
}

private struct LocationStatusView: View {
    let snapshot: WidgetSnapshot
    let stale: Bool
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryRectangular: rectangular
        case .accessoryCircular: circular
        default: home
        }
    }

    // MARK: Lock Screen

    private var symbol: String { snapshot.active == nil || stale ? "location.slash" : "location.fill" }

    /// LocSim may have ended since, so the place is no longer claimed as simulated.
    private var caption: LocalizedStringKey {
        stale ? "Open LocSim to check the location" : "Simulated location"
    }

    /// One line above the clock.
    private var inline: some View {
        if stale {
            Label("Open LocSim to check the location", systemImage: symbol)
        } else if let active = snapshot.active {
            Label("Simulated · \(active.name)", systemImage: symbol)
        } else {
            Label("Real location", systemImage: symbol)
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label {
                Text(snapshot.active == nil ? "Not simulated" : caption)
                    .font(.caption.weight(.semibold))
                    .lineLimit(stale ? 2 : 1)
            } icon: {
                Image(systemName: symbol)
            }
            if let active = snapshot.active {
                Text(active.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(active.coordinate)
                    .accessibilityLabel(Text(active.spokenCoordinate))
                    .font(.caption2.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Text("The real location is in use.")
                    .font(.caption)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: symbol)
                .font(.title2)
        }
        .accessibilityLabel(Text(snapshot.active == nil ? "Not simulated" : caption))
    }

    // MARK: Home Screen

    @ViewBuilder
    private var home: some View {
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
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(snapshot.active == nil || stale ? Color.secondary : Color.blue)
                .accessibilityHidden(true)
            Spacer(minLength: 4)
            if let active = snapshot.active {
                Text(caption)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(stale ? Color.primary : Color.blue)
                    .lineLimit(stale ? 3 : 1)
                Text(active.name)
                    .font(.headline)
                    .lineLimit(2)
                Text(active.coordinate)
                    .accessibilityLabel(Text(active.spokenCoordinate))
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
        VStack(alignment: .leading, spacing: 2) {
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
                        // The whole row, so a tap between rows does not miss or open the app empty.
                        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .accessibilityHint(Text("Opens LocSim and sets this location"))
                }
            }
        }
    }
}
