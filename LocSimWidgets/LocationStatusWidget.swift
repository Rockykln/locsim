import AppIntents
import SwiftUI
import WidgetKit

/// Home Screen widget: whether a location is simulated and where; the medium size also lists
/// favorites that open LocSim and set them. Widgets cannot reach the device themselves, so
/// every action goes through the app.
struct LocationStatusWidget: Widget {
    var body: some WidgetConfiguration {
        // The same kind as the earlier static widget, so widgets already placed keep working.
        AppIntentConfiguration(kind: WidgetSnapshot.kind, intent: ChooseFavoritesIntent.self, provider: SnapshotProvider()) { entry in
            LocationStatusView(snapshot: entry.snapshot, stale: entry.stale, favorites: entry.favorites)
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
    var favorites: [WidgetSnapshot.Place] = []
}

/// The app reloads the widget when something changes. A second entry turns it outdated in
/// case LocSim ends without saying so, like the Live Activity.
struct SnapshotProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .empty)
    }

    func snapshot(for configuration: ChooseFavoritesIntent, in context: Context) async -> SnapshotEntry {
        entries(WidgetSnapshot.load(), configuration)[0]
    }

    func timeline(for configuration: ChooseFavoritesIntent, in context: Context) async -> Timeline<SnapshotEntry> {
        Timeline(entries: entries(WidgetSnapshot.load(), configuration), policy: .never)
    }

    private func entries(_ snapshot: WidgetSnapshot, _ configuration: ChooseFavoritesIntent) -> [SnapshotEntry] {
        let now = Date()
        let favorites = Self.favorites(snapshot, chosen: configuration.mostUsed ? nil : configuration.favorites)
        func entry(_ date: Date, stale: Bool = false) -> SnapshotEntry {
            SnapshotEntry(date: date, snapshot: snapshot, stale: stale, favorites: favorites)
        }
        guard snapshot.active != nil, let until = snapshot.freshUntil else { return [entry(now)] }
        if until <= now { return [entry(now, stale: true)] }
        return [entry(now), entry(until, stale: true)]
    }

    /// The chosen favorites with their current names, in the chosen order; deleted ones drop out.
    /// Without a choice, or when none is left, the most used ones.
    private static func favorites(_ snapshot: WidgetSnapshot, chosen: [WidgetFavorite]?) -> [WidgetSnapshot.Place] {
        let catalog = snapshot.catalog ?? snapshot.favorites
        let picked = (chosen ?? []).compactMap { choice in catalog.first { $0.id == choice.id } }
        return picked.isEmpty ? snapshot.favorites : picked
    }
}

private struct LocationStatusView: View {
    let snapshot: WidgetSnapshot
    let stale: Bool
    let favorites: [WidgetSnapshot.Place]
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
                favoriteList
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
    private var favoriteList: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Favorites")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            if favorites.isEmpty {
                Text("No Favorites")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(favorites.prefix(3)) { favorite in
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
