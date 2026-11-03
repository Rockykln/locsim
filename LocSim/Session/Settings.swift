import CoreLocation
import Foundation

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
}

enum Defaults {
    static let hostname = "locsim"
    static let resend = 10
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
            SettingsKey.zoom: 900.0,
            SettingsKey.autoApply: false,
            SettingsKey.haptics: true,
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

@MainActor
final class FavoriteList: ObservableObject {
    @Published var items: [Favorite] {
        didSet {
            guard !Demo.isOn else { return }
            UserDefaults.standard.set(try? JSONEncoder().encode(items), forKey: SettingsKey.favorites)
        }
    }

    init() {
        if Demo.isOn {
            items = Demo.favorites
            return
        }
        let data = UserDefaults.standard.data(forKey: SettingsKey.favorites)
        items = data.flatMap { try? JSONDecoder().decode([Favorite].self, from: $0) } ?? []
    }
}

enum LastCoordinate {
    static func load() -> CLLocationCoordinate2D {
        guard let pair = UserDefaults.standard.array(forKey: SettingsKey.last) as? [Double], pair.count == 2 else {
            return Defaults.coordinate
        }
        return .init(latitude: pair[0], longitude: pair[1])
    }

    static func save(_ c: CLLocationCoordinate2D) {
        UserDefaults.standard.set([c.latitude, c.longitude], forKey: SettingsKey.last)
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
