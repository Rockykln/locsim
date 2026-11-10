import CoreLocation
import Foundation
import LocSimCore

enum SettingsKey {
    static let hostname = "pairingHostname"
    static let port = "portOverride"
    static let resend = "resendSeconds"
    static let keepAlive = "keepAlive"
    static let autoMount = "autoMountDDI"
    static let mapStyle = "mapStyle"
    static let precision = "coordinatePrecision"
    static let coordinateFormat = "coordinateFormat"
    static let zoom = "zoomDistance"
    static let autoApply = "autoApply"
    static let haptics = "haptics"
    static let favorites = "favorites"
    static let last = "lastCoordinate"
    static let lastName = "lastCoordinateName"
    static let ddiDownloadAllowed = "ddiDownloadAllowed"
    static let recents = "recentLocations"
    static let recentsEnabled = "recentsEnabled"
    static let liveActivity = "liveActivity"
    /// Off unless turned on: favorites shared through the person's iCloud.
    static let iCloudFavorites = "iCloudFavorites"
    /// Whether this device has merged with the list in iCloud since it was turned on.
    static let iCloudFavoritesJoined = "iCloudFavoritesJoined"
}

enum Defaults {
    static let hostname = "locsim"
    // The location stays while the connection is open; resending is a safeguard, so it can be rare.
    // 60 s plus tolerance stays well inside the tunnel's heartbeat timeout of 120 s.
    static let resend = 60
    static let coordinate = CLLocationCoordinate2D(latitude: 48.85660, longitude: 2.35220)

    static func register() {
        UserDefaults.standard.register(defaults: [
            SettingsKey.hostname: hostname,
            SettingsKey.port: "",
            SettingsKey.resend: resend,
            SettingsKey.keepAlive: true,
            SettingsKey.autoMount: true,
            SettingsKey.mapStyle: MapStyleOption.standard.rawValue,
            SettingsKey.precision: 5,
            SettingsKey.coordinateFormat: CoordinateFormat.decimal.rawValue,
            SettingsKey.zoom: ZoomOption.district.rawValue,
            SettingsKey.autoApply: false,
            SettingsKey.haptics: true,
            SettingsKey.recentsEnabled: true,
            SettingsKey.liveActivity: true,
        ])
    }
}

struct Favorite: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

extension Favorite {
    // Fields added later get defaults, so older and newer data both still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        latitude = try c.decode(Double.self, forKey: .latitude)
        longitude = try c.decode(Double.self, forKey: .longitude)
    }
}

/// Decodes a stored list entry by entry: one unreadable entry must not cost all the others.
private struct Lossy<Element: Decodable>: Decodable {
    let elements: [Element]

    // Accepts any value, so the container always moves on past a bad entry.
    private struct Skip: Decodable {
        init(from decoder: Decoder) {}
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        var result: [Element] = []
        while !container.isAtEnd {
            if let element = try? container.decode(Element.self) {
                result.append(element)
            } else {
                _ = try? container.decode(Skip.self)
            }
        }
        elements = result
    }
}

enum StoredList {
    /// nil when there is data that cannot be read at all; the caller then keeps it untouched.
    static func load<Element: Decodable>(_ key: String) -> [Element]? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode(Lossy<Element>.self, from: data))?.elements
    }

    static func save<Element: Encodable>(_ items: [Element], _ key: String) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

@MainActor
final class FavoriteList: ObservableObject {
    static let shared = FavoriteList()

    // Data that could not be read at all stays as it is until the list is changed on purpose.
    private var unreadable = false
    // Set while a list from iCloud is applied, so it is not sent straight back.
    private var fromICloud = false

    @Published var items: [Favorite] {
        didSet {
            guard !Demo.isOn else { return }
            if unreadable {
                UserDefaults.standard.set(UserDefaults.standard.data(forKey: SettingsKey.favorites),
                                          forKey: SettingsKey.favorites + ".unreadable")
                unreadable = false
            }
            StoredList.save(items, SettingsKey.favorites)
            // So Siri knows the favorite names in "Set LocSim to …".
            LocSimShortcuts.updateAppShortcutParameters()
            WidgetSync.setFavorites(items)
            if !fromICloud { FavoriteSync.push(items) }
        }
    }

    init() {
        if Demo.isOn {
            items = Demo.favorites
            return
        }
        let loaded: [Favorite]? = StoredList.load(SettingsKey.favorites)
        items = loaded ?? []
        unreadable = loaded == nil
        // didSet does not run in init; the widget may still list favorites from an older version.
        let current = items
        Task { @MainActor in
            WidgetSync.setFavorites(current)
            FavoriteSync.start(self)
        }
    }

    /// The list changed on another device. Unreadable data here is replaced too: iCloud has a copy.
    func applyFromICloud(_ remote: [Favorite]) {
        guard remote != items else { return }
        fromICloud = true
        items = remote
        fromICloud = false
    }

    /// The favorite at this spot, within a meter, so the star shows it is already saved.
    func favorite(at c: CLLocationCoordinate2D) -> Favorite? {
        items.first { $0.coordinate.distance(to: c) < 1 }
    }
}

struct RecentLocation: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String?
    var latitude: Double
    var longitude: Double

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

/// The last locations that were set, newest first. Stays on the device like the favorites.
@MainActor
final class RecentList: ObservableObject {
    static let limit = 5

    @Published private(set) var items: [RecentLocation] {
        didSet {
            guard !Demo.isOn else { return }
            StoredList.save(items, SettingsKey.recents)
        }
    }

    init() {
        items = Demo.isOn ? Demo.recents : StoredList.load(SettingsKey.recents) ?? []
    }

    func add(_ c: CLLocationCoordinate2D, name: String?) {
        guard UserDefaults.standard.bool(forKey: SettingsKey.recentsEnabled) else { return }
        // The same spot moves to the top instead of appearing twice.
        var list = items.filter { $0.coordinate.distance(to: c) >= 10 }
        list.insert(RecentLocation(name: name, latitude: c.latitude, longitude: c.longitude), at: 0)
        items = Array(list.prefix(Self.limit))
    }

    func remove(_ item: RecentLocation) {
        items.removeAll { $0.id == item.id }
    }

    func clear() {
        items = []
    }
}

extension CLLocationCoordinate2D {
    func distance(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
}

enum LastCoordinate {
    static func load() -> CLLocationCoordinate2D {
        guard let pair = UserDefaults.standard.array(forKey: SettingsKey.last) as? [Double], pair.count == 2 else {
            return Defaults.coordinate
        }
        return .init(latitude: pair[0], longitude: pair[1])
    }

    /// Whether a location was ever set; until then `load()` returns the default place.
    static var isSaved: Bool { UserDefaults.standard.array(forKey: SettingsKey.last) != nil }

    /// The place name that went with it, so a restart does not turn it into a dropped pin.
    static func loadName() -> String? {
        UserDefaults.standard.string(forKey: SettingsKey.lastName)
    }

    static func save(_ c: CLLocationCoordinate2D, name: String?) {
        UserDefaults.standard.set([c.latitude, c.longitude], forKey: SettingsKey.last)
        UserDefaults.standard.set(name, forKey: SettingsKey.lastName)
    }
}

enum MapStyleOption: String, CaseIterable, Identifiable {
    case standard, hybrid, imagery

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return String(localized: "Standard")
        case .hybrid: return String(localized: "Hybrid")
        case .imagery: return String(localized: "Satellite")
        }
    }
}

enum ZoomOption: Double, CaseIterable, Identifiable {
    case street = 300
    case block = 900
    case district = 3000
    case city = 12000

    var id: Double { rawValue }

    var title: String {
        switch self {
        case .street: return String(localized: "Street")
        case .block: return String(localized: "Block")
        case .district: return String(localized: "District")
        case .city: return String(localized: "City")
        }
    }
}
