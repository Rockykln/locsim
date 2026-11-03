import Foundation

/// Latitude and longitude in degrees, independent of CoreLocation.
public struct Coordinate: Equatable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    public var isValid: Bool { (-90...90).contains(latitude) && (-180...180).contains(longitude) }
}

public enum CoordinateFormat: String, CaseIterable, Identifiable, Sendable {
    case decimal
    case dms

    public var id: String { rawValue }
}

/// Accepts decimal degrees ("48.8566, 2.3522", "48,8566 2,3522", "N 48.8566 E 2.3522",
/// "48,85660° N, 2,35220° O") and degrees, minutes, seconds ("48°51'23.8"N 2°21'07.9"E").
/// Hemisphere letters may lead or trail; longitude-first input is swapped.
/// Apple Maps and Google Maps links and geo: URIs with coordinates are read as well.
/// Decimal output always uses a period, so it can be pasted anywhere.
public enum CoordinateText {
    public static func parse(_ text: String) -> Coordinate? {
        if let link = mapLink(text) { return link }
        let input = normalize(text)
        if input.rangeOfCharacter(from: CharacterSet(charactersIn: "'′’\"″”")) != nil {
            return parseDMS(input)
        }
        return parseDecimal(input)
    }

    /// `precision` is the number of decimal places, clamped to 3...7.
    public static func format(_ c: Coordinate, as format: CoordinateFormat, precision: Int = 5) -> String {
        switch format {
        case .decimal:
            let digits = min(max(precision, 3), 7)
            let lat = String(format: "%.\(digits)f", c.latitude)
            let lon = String(format: "%.\(digits)f", c.longitude)
            return "\(unsignedZero(lat)), \(unsignedZero(lon))"
        case .dms:
            return "\(dms(c.latitude, positive: "N", negative: "S")) \(dms(c.longitude, positive: "E", negative: "W"))"
        }
    }

    // MARK: - Parsing

    private static func mapLink(_ text: String) -> Coordinate? {
        guard let url = MapLink.url(in: text) else { return nil }
        if url.scheme?.lowercased() == "geo" {
            let body = url.absoluteString.dropFirst(4).split(whereSeparator: { $0 == "?" || $0 == ";" }).first ?? ""
            let base = pair(String(body))
            // Android puts the place into q when the base is 0,0: geo:0,0?q=48.85,2.35(Label)
            if base == Coordinate(latitude: 0, longitude: 0), let q = MapLink.value("q", in: url),
               let c = pair(String(q.prefix { $0 != "(" })) {
                return c
            }
            return base
        }
        guard MapLink.isMap(url) else { return nil }
        // Not "sll": in Apple's links that is only the center of the search area.
        for key in ["ll", "coordinate", "q", "query", "daddr"] {
            if let value = MapLink.value(key, in: url), let c = pair(value) { return c }
        }
        // Google Maps puts the map center into the path: /maps/@48.85,2.35,15z
        if let range = url.path.range(of: #"@-?\d+(\.\d+)?,-?\d+(\.\d+)?"#, options: .regularExpression) {
            return pair(String(url.path[range].dropFirst()))
        }
        return nil
    }

    private static func pair(_ text: String) -> Coordinate? {
        let parts = text.split(whereSeparator: { $0 == "," || $0 == " " }).prefix(2).map { Double($0) }
        guard parts.count == 2, let lat = parts[0], let lon = parts[1] else { return nil }
        let c = Coordinate(latitude: lat, longitude: lon)
        return c.isValid ? c : nil
    }

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

    private static func parseDecimal(_ text: String) -> Coordinate? {
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

    private static func parseDMS(_ text: String) -> Coordinate? {
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

    private static func coordinate(_ values: [Value]) -> Coordinate? {
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
            ? Coordinate(latitude: signed[1], longitude: signed[0])
            : Coordinate(latitude: signed[0], longitude: signed[1])
        return c.isValid ? c : nil
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
