import Foundation

/// What the Home Screen widget shows. The app writes it into the shared app group whenever the
/// simulated location or the favorites change; the widget only reads it.
struct WidgetSnapshot: Codable, Equatable {
    struct Place: Codable, Equatable, Identifiable {
        var id: UUID
        var name: String
        var coordinate: String
    }

    /// The simulated location; nil while nothing is simulated.
    var active: Place?
    var since: Date?
    /// After this the app may have ended without saying so; the widget then asks to check.
    var freshUntil: Date?
    var favorites: [Place]

    static let empty = WidgetSnapshot(active: nil, since: nil, favorites: [])
    static let group = "group.com.rockykln.locsim"
    static let kind = "LocSimStatus"
    private static let key = "widgetSnapshot"

    static func load() -> WidgetSnapshot {
        guard let data = UserDefaults(suiteName: group)?.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data) else { return .empty }
        return snapshot
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.group)?.set(data, forKey: Self.key)
    }

    /// Opens LocSim and sets that favorite.
    static func url(forFavorite id: UUID) -> URL {
        URL(string: "locsim://favorite/\(id.uuidString)")!
    }
}
