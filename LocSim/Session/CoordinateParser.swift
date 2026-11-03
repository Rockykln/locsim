import CoreLocation
import Foundation
import LocSimCore

extension CoordinateFormat {
    var title: String {
        switch self {
        case .decimal: return String(localized: "Decimal")
        case .dms: return String(localized: "Degrees, Minutes, Seconds")
        }
    }

    static var current: CoordinateFormat {
        CoordinateFormat(rawValue: UserDefaults.standard.string(forKey: SettingsKey.coordinateFormat) ?? "") ?? .decimal
    }
}

/// The app's view of `CoordinateText`, with CoreLocation types and the user's format settings.
enum CoordinateParser {
    static func parse(_ text: String) -> CLLocationCoordinate2D? {
        CoordinateText.parse(text).map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    static func format(_ c: CLLocationCoordinate2D) -> String {
        let stored = UserDefaults.standard.integer(forKey: SettingsKey.precision)
        return CoordinateText.format(
            Coordinate(latitude: c.latitude, longitude: c.longitude),
            as: .current, precision: stored == 0 ? 5 : stored)
    }

    /// For VoiceOver, which reads degree, minute and second symbols poorly.
    static func spoken(_ c: CLLocationCoordinate2D) -> String {
        let style = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(5))
        let lat = abs(c.latitude).formatted(style)
        let lon = abs(c.longitude).formatted(style)
        let latitude = c.latitude < 0
            ? String(localized: "\(lat) degrees south") : String(localized: "\(lat) degrees north")
        let longitude = c.longitude < 0
            ? String(localized: "\(lon) degrees west") : String(localized: "\(lon) degrees east")
        return "\(latitude), \(longitude)"
    }
}
