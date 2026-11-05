import CoreLocation
import Foundation

/// How often and how long each favorite was simulated, so the Home Screen quick actions can
/// offer the ones in real use. Stays on this device, in the app's own settings.
@MainActor
enum FavoriteUsage {
    private struct Usage: Codable {
        /// Times it stayed active for at least `minimum`.
        var uses = 0
        var seconds: TimeInterval = 0
    }

    /// A short look at a place is no real use.
    static let minimum: TimeInterval = 30 * 60
    private static let key = "favoriteUsage"
    private static var running: (id: UUID, since: Date)?

    private static var stored: [UUID: Usage] {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let map = try? JSONDecoder().decode([UUID: Usage].self, from: data) else { return [:] }
            return map
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: key) }
    }

    /// Called whenever the simulated location changes; nil when it ended.
    static func activeChanged(to coordinate: CLLocationCoordinate2D?) {
        end()
        guard let coordinate, let favorite = FavoriteList.shared.items.first(where: { same($0.coordinate, coordinate) })
        else { return }
        running = (favorite.id, Date())
    }

    /// The simulation ended, also when LocSim quits.
    static func end() {
        guard let run = running else { return }
        running = nil
        let duration = Date().timeIntervalSince(run.since)
        var map = stored
        var usage = map[run.id] ?? Usage()
        usage.seconds += duration
        if duration >= minimum { usage.uses += 1 }
        map[run.id] = usage
        // Favorites deleted since are dropped.
        let ids = Set(FavoriteList.shared.items.map(\.id))
        stored = map.filter { ids.contains($0.key) }
    }

    /// The most used favorites first; until any counts, the order of the favorites list.
    static func ranked(_ favorites: [Favorite]) -> [Favorite] {
        let map = stored
        return favorites.enumerated().sorted { a, b in
            let ua = map[a.element.id] ?? Usage(), ub = map[b.element.id] ?? Usage()
            if ua.uses != ub.uses { return ua.uses > ub.uses }
            if ua.seconds != ub.seconds { return ua.seconds > ub.seconds }
            return a.offset < b.offset
        }.map(\.element)
    }

    private static func same(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Bool {
        abs(a.latitude - b.latitude) < 1e-5 && abs(a.longitude - b.longitude) < 1e-5
    }
}
