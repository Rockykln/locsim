import CoreLocation
import Foundation
import MapKit
import SwiftUI

/// Sample data for App Store screenshots, without a device connection.
/// Debug builds only, started with the launch argument `-demo map|search|favorites`.
enum Demo {
    enum Screen: String {
        case map, search, favorites
    }

    #if DEBUG
    static let screen = UserDefaults.standard.string(forKey: "demo").flatMap(Screen.init(rawValue:))
    #else
    static let screen: Screen? = nil
    #endif

    static var isOn: Bool { screen != nil }

    private static let german = Locale.preferredLanguages.first?.hasPrefix("de") == true

    // Typical test locations instead of landmarks; public places only.
    private static let places: [(en: String, de: String, latitude: Double, longitude: Double)] = [
        ("Office, Amsterdam", "Büro, Amsterdam", 52.37020, 4.88620),
        ("Client, Munich", "Kunde, München", 48.13230, 11.60310),
        ("Airport, Frankfurt", "Flughafen, Frankfurt", 50.05110, 8.57060),
        ("Train station, Zurich", "Bahnhof, Zürich", 47.37820, 8.54020),
        ("Hotel, Lisbon", "Hotel, Lissabon", 38.71100, -9.13700),
        ("Conference, San Francisco", "Konferenz, San Francisco", 37.78410, -122.40130),
        ("Test drive, Berlin", "Teststrecke, Berlin", 52.47330, 13.40150),
    ]

    static var favorites: [Favorite] {
        places.map { Favorite(name: german ? $0.de : $0.en, latitude: $0.latitude, longitude: $0.longitude) }
    }

    static var place: Favorite { favorites[0] }

    static var query: String {
        UserDefaults.standard.string(forKey: "demoQuery") ?? (german ? "Hauptbahnhof" : "Central Station")
    }

    struct Suggestion {
        let title: String
        let subtitle: String
        let coordinate: CLLocationCoordinate2D
    }

    /// Fixed search results: live ones follow the simulator's language and change between runs.
    /// Five rows, so none is cut off at the bottom of the list.
    static var suggestions: [Suggestion]? {
        guard screen == .search else { return nil }
        let rows: [(String, String, Double, Double)] = german ? [
            ("Berlin Hauptbahnhof", "Europaplatz, Berlin, Deutschland", 52.52510, 13.36940),
            ("Hamburg Hauptbahnhof", "Hachmannplatz, Hamburg, Deutschland", 53.55300, 10.00670),
            ("München Hauptbahnhof", "Bayerstraße, München, Deutschland", 48.14020, 11.55870),
            ("Köln Hauptbahnhof", "Trankgasse, Köln, Deutschland", 50.94300, 6.95870),
            ("Frankfurt (Main) Hauptbahnhof", "Am Hauptbahnhof, Frankfurt am Main, Deutschland", 50.10700, 8.66380),
        ] : [
            ("Amsterdam Centraal", "Stationsplein, Amsterdam, Netherlands", 52.37890, 4.90060),
            ("Rotterdam Centraal", "Stationsplein, Rotterdam, Netherlands", 51.92490, 4.46890),
            ("Antwerpen-Centraal", "Koningin Astridplein, Antwerp, Belgium", 51.21720, 4.42110),
            ("Zürich HB", "Bahnhofplatz, Zurich, Switzerland", 47.37820, 8.54020),
            ("Brussels Central", "Carrefour de l'Europe, Brussels, Belgium", 50.84540, 4.35700),
        ]
        return rows.map { Suggestion(title: $0.0, subtitle: $0.1, coordinate: .init(latitude: $0.2, longitude: $0.3)) }
    }

    /// A bit closer than the normal start view, over the canal ring.
    static var camera: MapCameraPosition? {
        guard isOn else { return nil }
        return .camera(MapCamera(centerCoordinate: place.coordinate, distance: 3000, heading: 0, pitch: 0))
    }

    /// Matches the 9:41 status bar of the screenshots.
    static var sentTime: Date {
        Calendar.current.date(bySettingHour: 9, minute: 41, second: 0, of: Date()) ?? Date()
    }
}
