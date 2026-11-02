import CoreLocation
import Foundation

enum CoordinateFormat: String, CaseIterable, Identifiable {
    case decimal
    case dms

    var id: String { rawValue }

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

/// Accepts decimal degrees ("48.8566, 2.3522", "48,8566 2,3522", "N 48.8566 E 2.3522",
/// "48,85660° N, 2,35220° O") and degrees, minutes, seconds ("48°51'23.8"N 2°21'07.9"E").
/// Hemisphere letters may lead or trail; longitude-first input is swapped.
enum CoordinateParser {
    static func parse(_ text: String) -> CLLocationCoordinate2D? {
        let input = normalize(text)
        if input.rangeOfCharacter(from: CharacterSet(charactersIn: "'′’\"″”")) != nil {
            return parseDMS(input)
        }
        return parseDecimal(input)
    }

    static func format(_ c: CLLocationCoordinate2D) -> String {
        switch CoordinateFormat.current {
        case .decimal:
            let stored = UserDefaults.standard.integer(forKey: SettingsKey.precision)
            let digits = min(max(stored == 0 ? 5 : stored, 3), 7)
            let lat = String(format: "%.\(digits)f", c.latitude)
            let lon = String(format: "%.\(digits)f", c.longitude)
            return "\(unsignedZero(lat)), \(unsignedZero(lon))"
        case .dms:
            return "\(dms(c.latitude, positive: "N", negative: "S")) \(dms(c.longitude, positive: "E", negative: "W"))"
        }
    }

    // MARK: - Parsing

    private struct Value {
        let magnitude: Double
        let negative: Bool
        let hemisphere: String?
    }

    private static let hemisphere = #"(?<![A-Z])[NSEWO](?![A-Z])"#
    private static let number = #"[-+]?\d+(?:[.,]\d+)?"#

    private static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "º", with: "°")
            .replacingOccurrences(of: "\u{2212}", with: "-")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    private static let decimalToken = try! NSRegularExpression(pattern: "(\(hemisphere))|(\(number))")
    private static let decimalLeftover = try! NSRegularExpression(pattern: "\(hemisphere)|\(number)|[\\s,;°]")

    private static func parseDecimal(_ text: String) -> CLLocationCoordinate2D? {
        let full = NSRange(text.startIndex..., in: text)
        // Anything besides numbers, hemisphere letters and separators is a place name.
        guard decimalLeftover.stringByReplacingMatches(in: text, range: full, withTemplate: "").isEmpty else {
            return nil
        }
        let tokens = decimalToken.matches(in: text, range: full).map { match -> (isLetter: Bool, text: String) in
            let letter = Range(match.range(at: 1), in: text)
            let range = letter ?? Range(match.range(at: 2), in: text)!
            return (letter != nil, String(text[range]))
        }
        guard let first = tokens.first else { return nil }

        let leading = first.isLetter
        var values: [Value] = []
        for (index, token) in tokens.enumerated() where !token.isLetter {
            let neighbour = leading ? index - 1 : index + 1
            let hemisphere = tokens.indices.contains(neighbour) && tokens[neighbour].isLetter
                ? tokens[neighbour].text : nil
            guard let value = Double(token.text.replacingOccurrences(of: ",", with: ".")) else { return nil }
            values.append(Value(magnitude: abs(value), negative: token.text.hasPrefix("-"), hemisphere: hemisphere))
        }
        return coordinate(values)
    }

    private static let dmsCore = #"([-+]?\d+(?:[.,]\d+)?)\s*°\s*"#   // degrees
        + #"(?:(\d+(?:[.,]\d+)?)\s*['′’]\s*)?"#                     // minutes
        + #"(?:(\d+(?:[.,]\d+)?)\s*(?:["″”]|''|′′|’’)\s*)?"#         // seconds
    private static let dmsLeading = try! NSRegularExpression(pattern: "(?:(\(hemisphere))\\s*)?" + dmsCore)
    private static let dmsTrailing = try! NSRegularExpression(pattern: dmsCore + "(?:(\(hemisphere)))?")

    private static func parseDMS(_ text: String) -> CLLocationCoordinate2D? {
        let leading = text.range(of: "^\(hemisphere)", options: .regularExpression) != nil
        let pattern = leading ? dmsLeading : dmsTrailing
        let matches = pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
        guard matches.count == 2 else { return nil }

        var values: [Value] = []
        for match in matches {
            func group(_ index: Int) -> String? {
                Range(match.range(at: index), in: text).map { String(text[$0]) }
            }
            let offset = leading ? 1 : 0
            guard let degreesText = group(1 + offset),
                  let degrees = Double(degreesText.replacingOccurrences(of: ",", with: ".")) else { return nil }
            let minutesText = group(2 + offset)
            let secondsText = group(3 + offset)
            let isFractional = degreesText.contains(".") || degreesText.contains(",")
            if isFractional, minutesText != nil || secondsText != nil { return nil }

            let minutes = minutesText.flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) } ?? 0
            let seconds = secondsText.flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) } ?? 0
            guard minutes < 60, seconds < 60 else { return nil }

            values.append(Value(
                magnitude: abs(degrees) + minutes / 60 + seconds / 3600,
                negative: degreesText.hasPrefix("-"),
                hemisphere: group(leading ? 1 : 4)))
        }
        return coordinate(values)
    }

    private static func coordinate(_ values: [Value]) -> CLLocationCoordinate2D? {
        guard values.count == 2 else { return nil }
        let signed = values.map { v -> Double in
            let negative = v.negative || v.hemisphere == "S" || v.hemisphere == "W"
            return negative ? -v.magnitude : v.magnitude
        }
        func isLatitude(_ h: String?) -> Bool { h == "N" || h == "S" }
        func isLongitude(_ h: String?) -> Bool { h == "E" || h == "W" || h == "O" }

        let (first, second) = (values[0].hemisphere, values[1].hemisphere)
        if first != nil, second != nil, isLatitude(first) == isLatitude(second) { return nil }
        let swapped = isLongitude(first) || (first == nil && isLatitude(second))
        let c = swapped
            ? CLLocationCoordinate2D(latitude: signed[1], longitude: signed[0])
            : CLLocationCoordinate2D(latitude: signed[0], longitude: signed[1])
        return CLLocationCoordinate2DIsValid(c) ? c : nil
    }

    // MARK: - Formatting

    private static func dms(_ value: Double, positive: String, negative: String) -> String {
        let total = (abs(value) * 36000).rounded() / 10
        let degrees = Int(total / 3600)
        let minutes = Int(total.truncatingRemainder(dividingBy: 3600) / 60)
        let seconds = total.truncatingRemainder(dividingBy: 60)
        let hemisphere = value < 0 && total > 0 ? negative : positive
        return "\(degrees)°\(String(format: "%02d", minutes))′\(String(format: "%04.1f", seconds))″\(hemisphere)"
    }

    private static func unsignedZero(_ text: String) -> String {
        text.hasPrefix("-") && text.dropFirst().allSatisfy({ $0 == "0" || $0 == "." }) ? String(text.dropFirst()) : text
    }
}
