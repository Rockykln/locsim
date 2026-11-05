import CoreLocation
import Foundation
import MapKit
import SwiftUI

/// Sample data for App Store screenshots, without a device connection.
/// Debug builds only, started with the launch argument `-demo map|search|recents|live|favorites`.
enum Demo {
    enum Screen: String {
        case map, search, recents, live, favorites
    }

    #if DEBUG
    static let screen = UserDefaults.standard.string(forKey: "demo").flatMap(Screen.init(rawValue:))
    #else
    static let screen: Screen? = nil
    #endif

    static var isOn: Bool { screen != nil }

    private static let language = Bundle.main.preferredLocalizations.first ?? "en"

    private static func text(_ values: [String: String]) -> String {
        values[language] ?? values["en"] ?? ""
    }

    // Typical test locations instead of landmarks; public places only.
    private static let places: [(names: [String: String], latitude: Double, longitude: Double)] = [
        (["en": "Office, Amsterdam", "de": "Büro, Amsterdam", "fr": "Bureau, Amsterdam",
          "es": "Oficina, Ámsterdam", "it": "Ufficio, Amsterdam"], 52.37020, 4.88620),
        (["en": "Client, Munich", "de": "Kunde, München", "fr": "Client, Munich",
          "es": "Cliente, Múnich", "it": "Cliente, Monaco di Baviera"], 48.13230, 11.60310),
        (["en": "Airport, Frankfurt", "de": "Flughafen, Frankfurt", "fr": "Aéroport, Francfort",
          "es": "Aeropuerto, Fráncfort", "it": "Aeroporto, Francoforte"], 50.05110, 8.57060),
        (["en": "Train station, Zurich", "de": "Bahnhof, Zürich", "fr": "Gare, Zurich",
          "es": "Estación, Zúrich", "it": "Stazione, Zurigo"], 47.37820, 8.54020),
        (["en": "Hotel, Lisbon", "de": "Hotel, Lissabon", "fr": "Hôtel, Lisbonne",
          "es": "Hotel, Lisboa", "it": "Hotel, Lisbona"], 38.71100, -9.13700),
        (["en": "Conference, San Francisco", "de": "Konferenz, San Francisco", "fr": "Conférence, San Francisco",
          "es": "Congreso, San Francisco", "it": "Conferenza, San Francisco"], 37.78410, -122.40130),
        (["en": "Test drive, Berlin", "de": "Teststrecke, Berlin", "fr": "Essai routier, Berlin",
          "es": "Prueba de ruta, Berlín", "it": "Percorso di prova, Berlino"], 52.47330, 13.40150),
    ]

    static var favorites: [Favorite] {
        places.map { Favorite(name: text($0.names), latitude: $0.latitude, longitude: $0.longitude) }
    }

    static var place: Favorite { favorites[0] }

    /// The search field's recent list: a few favorites and one coordinate without a name.
    static var recents: [RecentLocation] {
        guard screen == .recents else { return [] }
        let named = [favorites[1], favorites[3], favorites[4]]
            .map { RecentLocation(name: $0.name, latitude: $0.latitude, longitude: $0.longitude) }
        return named + [RecentLocation(name: nil, latitude: 51.50330, longitude: -0.11950)]
    }

    static var query: String {
        UserDefaults.standard.string(forKey: "demoQuery") ?? text([
            "en": "Central Station", "de": "Hauptbahnhof", "fr": "Gare", "es": "Estación", "it": "Stazione",
        ])
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
        let rows: [(String, String, Double, Double)]
        switch language {
        case "de":
            rows = [
                ("Berlin Hauptbahnhof", "Europaplatz, Berlin, Deutschland", 52.52510, 13.36940),
                ("Hamburg Hauptbahnhof", "Hachmannplatz, Hamburg, Deutschland", 53.55300, 10.00670),
                ("München Hauptbahnhof", "Bayerstraße, München, Deutschland", 48.14020, 11.55870),
                ("Köln Hauptbahnhof", "Trankgasse, Köln, Deutschland", 50.94300, 6.95870),
                ("Frankfurt (Main) Hauptbahnhof", "Am Hauptbahnhof, Frankfurt am Main, Deutschland", 50.10700, 8.66380),
            ]
        case "fr":
            rows = [
                ("Gare de Lyon", "Place Louis-Armand, Paris, France", 48.84430, 2.37430),
                ("Gare du Nord", "Rue de Dunkerque, Paris, France", 48.88090, 2.35530),
                ("Gare de Lyon-Part-Dieu", "Place Charles Béraudier, Lyon, France", 45.76060, 4.85960),
                ("Gare de Marseille-Saint-Charles", "Square Narvik, Marseille, France", 43.30270, 5.38040),
                ("Gare de Bordeaux-Saint-Jean", "Rue Charles Domercq, Bordeaux, France", 44.82580, -0.55620),
            ]
        case "es":
            rows = [
                ("Estación de Madrid Atocha", "Plaza del Emperador Carlos V, Madrid, España", 40.40650, -3.68920),
                ("Estación de Barcelona Sants", "Plaça dels Països Catalans, Barcelona, España", 41.37910, 2.14000),
                ("Estación de València Joaquín Sorolla", "Carrer de Sant Vicent Màrtir, Valencia, España", 39.45950, -0.38250),
                ("Estación de Sevilla Santa Justa", "Avenida de Kansas City, Sevilla, España", 37.39200, -5.97540),
                ("Estación de Málaga María Zambrano", "Explanada de la Estación, Málaga, España", 36.71160, -4.43170),
            ]
        case "it":
            rows = [
                ("Stazione di Roma Termini", "Piazza dei Cinquecento, Roma, Italia", 41.90100, 12.50200),
                ("Stazione di Milano Centrale", "Piazza Duca d'Aosta, Milano, Italia", 45.48610, 9.20470),
                ("Stazione di Napoli Centrale", "Piazza Giuseppe Garibaldi, Napoli, Italia", 40.85270, 14.27270),
                ("Stazione di Firenze Santa Maria Novella", "Piazza della Stazione, Firenze, Italia", 43.77630, 11.24770),
                ("Stazione di Torino Porta Nuova", "Corso Vittorio Emanuele II, Torino, Italia", 45.06200, 7.67880),
            ]
        default:
            rows = [
                ("Amsterdam Centraal", "Stationsplein, Amsterdam, Netherlands", 52.37890, 4.90060),
                ("Rotterdam Centraal", "Stationsplein, Rotterdam, Netherlands", 51.92490, 4.46890),
                ("Antwerpen-Centraal", "Koningin Astridplein, Antwerp, Belgium", 51.21720, 4.42110),
                ("Zürich HB", "Bahnhofplatz, Zurich, Switzerland", 47.37820, 8.54020),
                ("Brussels Central", "Carrefour de l'Europe, Brussels, Belgium", 50.84540, 4.35700),
            ]
        }
        return rows.map { Suggestion(title: $0.0, subtitle: $0.1, coordinate: .init(latitude: $0.2, longitude: $0.3)) }
    }

    /// A bit closer than the normal start view, over the canal ring.
    static var camera: MapCameraPosition? {
        guard isOn else { return nil }
        return .camera(MapCamera(centerCoordinate: place.coordinate, distance: 3600, heading: 0, pitch: 0))
    }

    /// Matches the 9:41 status bar of the screenshots.
    static var sentTime: Date {
        Calendar.current.date(bySettingHour: 9, minute: 41, second: 0, of: Date()) ?? Date()
    }

    /// 25 minutes before the 9:41 of the screenshots.
    static var activityStart: Date { sentTime.addingTimeInterval(-25 * 60) }
}
