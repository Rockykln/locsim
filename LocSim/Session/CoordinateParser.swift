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
        CoordinateText.parse(text, language: Locale.current.language.languageCode?.identifier)
            .map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    /// Decimal places from the settings, 3...7.
    static var precision: Int {
        let stored = UserDefaults.standard.integer(forKey: SettingsKey.precision)
        return min(max(stored == 0 ? 5 : stored, 3), 7)
    }

    static func format(_ c: CLLocationCoordinate2D) -> String {
        CoordinateText.format(Coordinate(latitude: c.latitude, longitude: c.longitude), as: .current, precision: precision)
    }

    /// For VoiceOver, which reads degree, minute and second symbols poorly.
    static func spoken(_ c: CLLocationCoordinate2D) -> String {
        let digits = precision
        let style = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(digits))
        // A value that rounds to zero has no hemisphere, as in format().
        func isNegative(_ value: Double) -> Bool {
            value < 0 && (abs(value) * pow(10, Double(digits))).rounded() != 0
        }
        let lat = abs(c.latitude).formatted(style)
        let lon = abs(c.longitude).formatted(style)
        let latitude = isNegative(c.latitude)
            ? String(localized: "\(lat) degrees south") : String(localized: "\(lat) degrees north")
        let longitude = isNegative(c.longitude)
            ? String(localized: "\(lon) degrees west") : String(localized: "\(lon) degrees east")
        return "\(latitude), \(longitude)"
    }
}
