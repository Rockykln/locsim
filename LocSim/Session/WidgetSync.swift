import CoreLocation
import Foundation
import WidgetKit

/// Keeps the Home Screen widget in step with the app. Writes only when something the widget
/// shows has changed, so resends in the background cause no widget reloads.
@MainActor
enum WidgetSync {
    private static var shown = WidgetSnapshot.load()

    static func setActive(name: String, at c: CLLocationCoordinate2D, since: Date) {
        let active = WidgetSnapshot.Place(
            id: shown.active?.id ?? UUID(), name: name, coordinate: CoordinateParser.format(c),
            spoken: CoordinateParser.spoken(c))
        guard shown.active?.name != name || shown.active?.coordinate != active.coordinate || shown.since != since
        else { return }
        shown.active = active
        shown.since = since
        shown.freshUntil = Date().addingTimeInterval(freshFor)
        publish()
    }

    /// Longer than the Live Activity's: every renewal reloads the widget, which iOS limits.
    static let freshFor: TimeInterval = 3600

    /// Like the Live Activity: outdated from then on unless LocSim renews it.
    static func markStale(after seconds: TimeInterval) {
        guard shown.active != nil else { return }
        shown.freshUntil = Date().addingTimeInterval(seconds)
        publish()
    }

    static func keepFresh() {
        guard shown.active != nil, (shown.freshUntil?.timeIntervalSinceNow ?? 0) < freshFor / 2 else { return }
        markStale(after: freshFor)
    }

    static func clearActive() {
        guard shown.active != nil else { return }
        shown.active = nil
        shown.since = nil
        shown.freshUntil = nil
        publish()
    }

    /// The widget lists the most used favorites first, like the Home Screen quick actions.
    static func setFavorites(_ favorites: [Favorite]) {
        let places = FavoriteUsage.ranked(favorites).prefix(3).map {
            WidgetSnapshot.Place(
                id: $0.id, name: $0.name, coordinate: CoordinateParser.format($0.coordinate),
                spoken: CoordinateParser.spoken($0.coordinate))
        }
        guard places != shown.favorites else { return }
        shown.favorites = places
        publish()
    }

    private static func publish() {
        shown.save()
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.kind)
        // The quick actions show the same: Clear while simulating and the most used favorites.
        // iOS may end LocSim in the background before the scene resigns again.
        QuickActions.refresh()
    }

    /// A tap on a favorite in the widget: show it on the map and set it.
    static func open(_ url: URL) {
        guard url.scheme == "locsim", url.host == "favorite", let id = UUID(uuidString: url.lastPathComponent),
              let favorite = FavoriteList.shared.items.first(where: { $0.id == id }) else { return }
        ExternalRequests.shared.post(
            .set(latitude: favorite.coordinate.latitude, longitude: favorite.coordinate.longitude, name: favorite.name))
    }
}
