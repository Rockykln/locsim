import Foundation
import WidgetKit

/// Keeps the Home Screen widget in step with the app. Writes only when something the widget
/// shows has changed, so resends in the background cause no widget reloads.
@MainActor
enum WidgetSync {
    private static var shown = WidgetSnapshot.load()

    static func setActive(name: String, coordinate: String, since: Date) {
        let active = WidgetSnapshot.Place(id: shown.active?.id ?? UUID(), name: name, coordinate: coordinate)
        guard shown.active?.name != name || shown.active?.coordinate != coordinate || shown.since != since else { return }
        shown.active = active
        shown.since = since
        publish()
    }

    static func clearActive() {
        guard shown.active != nil else { return }
        shown.active = nil
        shown.since = nil
        publish()
    }

    static func setFavorites(_ favorites: [Favorite]) {
        let places = favorites.map {
            WidgetSnapshot.Place(id: $0.id, name: $0.name, coordinate: CoordinateParser.format($0.coordinate))
        }
        guard places != shown.favorites else { return }
        shown.favorites = places
        publish()
    }

    private static func publish() {
        shown.save()
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetSnapshot.kind)
    }

    /// A tap on a favorite in the widget: show it on the map and set it.
    static func open(_ url: URL) async {
        guard url.scheme == "locsim", url.host == "favorite", let id = UUID(uuidString: url.lastPathComponent),
              let favorite = FavoriteList.shared.items.first(where: { $0.id == id }) else { return }
        let session = SimulationSession.shared
        session.target = favorite.coordinate
        session.targetName = favorite.name
        // Without the one-time setup the app shows its setup steps; the pin is already in place.
        guard session.hasPairing else { return }
        await session.apply()
    }
}
