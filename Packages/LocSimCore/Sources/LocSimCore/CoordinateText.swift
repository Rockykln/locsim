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
        if let url = MapLink.url(in: text) {
            // Numbers in a Maps link without coordinates, e.g. in a place ID, are no coordinates.
            if MapLink.isMap(url) { return nil }
            // Coordinates written next to another link: "Meet at 48.85, 2.35 https://…"
            let rest = text.replacingOccurrences(of: url.absoluteString, with: " ")
            return rest == text ? parseText(text) : parseText(rest)
        }
        return parseText(text)
    }

    private static func parseText(_ text: String) -> Coordinate? {
        let input = normalize(text)
        // "48.85, W 2.35": each half has its own letter, wherever it stands.
        if let c = parseHalves(input) { return c }
        if isDMS(input) { return parseDMS(input) }
        return parseDecimal(input)
    }

    private static func isDMS(_ text: String) -> Bool {
        text.rangeOfCharacter(from: CharacterSet(charactersIn: "'′’\"″”")) != nil
    }

    private static let hemisphereRegex = try! NSRegularExpression(pattern: hemisphere)
    private static let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;."))
    private static let singleNumber = try! NSRegularExpression(pattern: "^\(number)\\s*°?$")

    /// Two halves split by a comma or semicolon, each with one value and at most one letter.
    /// nil when the text is not like that, e.g. with decimal commas ("48,85 2,35").
    private static func parseHalves(_ text: String) -> Coordinate? {
        let halves = text.split(whereSeparator: { $0 == "," || $0 == ";" }).map {
            String($0).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard halves.count == 2 else { return nil }
        var values: [Value] = []
        for half in halves {
            let range = NSRange(half.startIndex..., in: half)
            let letters = hemisphereRegex.matches(in: half, range: range)
            guard letters.count <= 1 else { return nil }
            let letter = letters.first.flatMap { Range($0.range, in: half) }.map { String(half[$0]) }
            let rest = hemisphereRegex.stringByReplacingMatches(in: half, range: range, withTemplate: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = singleValue(rest) else { return nil }
            values.append(Value(magnitude: value.magnitude, negative: value.negative, hemisphere: letter))
        }
        return coordinate(values)
    }

    private static func singleValue(_ text: String) -> (magnitude: Double, negative: Bool)? {
        if isDMS(text) || text.contains("°") && text.range(of: #"\d\s+\d"#, options: .regularExpression) != nil {
            let range = NSRange(text.startIndex..., in: text)
            let matches = dmsTrailing.matches(in: text, range: range)
            guard matches.count == 1, let match = matches.first, match.range == range,
                  match.range(at: 4).location == NSNotFound else { return nil }
            return dmsValue(match, in: text, offset: 0)
        }
        guard singleNumber.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil,
              let value = Double(text.replacingOccurrences(of: "°", with: "")
                  .trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
        else { return nil }
        return (abs(value), text.hasPrefix("-"))
    }

    /// Coordinates from a Maps link or geo: URI only, never from other numbers in the URL.
    public static func coordinate(inLink url: URL) -> Coordinate? {
        mapLink(url.absoluteString)
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
            // Android puts the place into q when the base is 0,0: geo:0,0?q=48.85,2.35(Label).
            // With a name or address there, geo:0,0?q=Cafe, it is no coordinate but a search.
            if base == Coordinate(latitude: 0, longitude: 0), let q = MapLink.value("q", in: url) {
                return pair(String(q.prefix { $0 != "(" }))
            }
            return base
        }
        guard MapLink.isMap(url) else { return nil }
        // Not "sll": in Apple's links that is only the center of the search area.
        for key in ["ll", "coordinate", "q", "query", "daddr", "destination"] {
            guard let value = MapLink.value(key, in: url) else { continue }
            // "48.85,2.35 (Cafe)": the label in brackets is not part of the coordinates.
            let bare = String(value.prefix { $0 != "(" }).trimmingCharacters(in: .whitespaces)
            if let c = pair(bare) { return c }
            // Coordinates written out, e.g. q=48°51'23.8"N 2°21'07.9"E.
            if bare.range(of: #"\d"#, options: .regularExpression) != nil, let c = parseText(bare) { return c }
        }
        // Google's map URL API: /maps/@?api=1&map_action=map&center=48.85,2.35
        if MapLink.value("map_action", in: url) == "map", let center = MapLink.value("center", in: url),
           let c = pair(center) {
            return c
        }
        // Google Maps: the place itself is in the data part, !3d<lat>!4d<lon>.
        let path = url.path
        if let lat = number(after: "!3d", in: path), let lon = number(after: "!4d", in: path) {
            let c = Coordinate(latitude: lat, longitude: lon)
            if c.isValid { return c }
        }
        let parts = url.pathComponents
        let maps = parts.firstIndex(of: "maps")
        let kind = maps.flatMap { parts.indices.contains($0 + 1) ? parts[$0 + 1] : nil }
        // Directions: only the destination counts, the last stop. A named one is searched instead.
        if kind == "dir" {
            let stops = parts.dropFirst((maps ?? 0) + 2).filter { !$0.hasPrefix("@") && !$0.hasPrefix("data=") }
            return stops.last.flatMap { pair($0.replacingOccurrences(of: "+", with: " ")) }
        }
        // /maps/search/48.85,+2.35/… and /maps/place/48.85,+2.35/…: the term itself is the place.
        if kind == "search" || kind == "place", let maps, parts.indices.contains(maps + 2),
           let c = pair(parts[maps + 2].replacingOccurrences(of: "+", with: " ")) {
            return c
        }
        // The map center, /maps/@48.85,2.35,15z, is only the place for a plain map or a place
        // link; in a search it is just the area that was shown.
        guard kind == nil || kind?.hasPrefix("@") == true || kind == "place" else { return nil }
        if let range = path.range(of: #"@-?\d+(\.\d+)?,-?\d+(\.\d+)?"#, options: .regularExpression) {
            return pair(String(path[range].dropFirst()))
        }
        return nil
    }

    private static func number(after marker: String, in text: String) -> Double? {
        guard let range = text.range(of: marker + #"-?\d+(\.\d+)?"#, options: .regularExpression) else { return nil }
        return Double(text[range].dropFirst(marker.count))
    }

    /// "48.85,2.35", "48.85 2.35" or "loc:48.85,2.35"; a third number (altitude in geo:) may follow.
    /// Anything else, e.g. "10 20 Main Street", is no coordinate.
    private static func pair(_ text: String) -> Coordinate? {
        var text = text.trimmingCharacters(in: .whitespaces)
        if text.lowercased().hasPrefix("loc:") { text.removeFirst(4) }
        let parts = text.split(whereSeparator: { $0 == "," || $0 == " " })
        guard parts.count == 2 || parts.count == 3,
              parts.allSatisfy({ $0.range(of: #"^[-+]?\d+(\.\d+)?$"#, options: .regularExpression) != nil }),
              let lat = Double(parts[0]), let lon = Double(parts[1]) else { return nil }
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
            // Minus written as a dash or hyphen character, e.g. copied from a document.
            .replacingOccurrences(of: "[\u{2010}-\u{2014}\u{2212}\u{FE63}\u{FF0D}]", with: "-", options: .regularExpression)
            .replacingOccurrences(of: "[\u{2000}-\u{200A}\u{202F}\u{205F}]", with: " ", options: .regularExpression)
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
        // A letter that belongs to no number, "48.85 2.35 E N", makes the input ambiguous.
        let letterCount = tokens.filter(\.isLetter).count
        var assigned = 0
        var values: [Value] = []
        for (index, token) in tokens.enumerated() where !token.isLetter {
            let neighbour = leading ? index - 1 : index + 1
            let hemisphere = tokens.indices.contains(neighbour) && tokens[neighbour].isLetter
                ? tokens[neighbour].text : nil
            guard let value = Double(token.text.replacingOccurrences(of: ",", with: ".")) else { return nil }
            if hemisphere != nil { assigned += 1 }
            values.append(Value(magnitude: abs(value), negative: token.text.hasPrefix("-"), hemisphere: hemisphere))
        }
        guard assigned == letterCount else { return nil }
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

        // Anything outside the two values, "… 12" or a letter on the other side, is not a coordinate.
        let leftover = NSMutableString(string: text)
        for match in matches.reversed() { leftover.replaceCharacters(in: match.range, with: " ") }
        // Separators, line breaks and a closing period ("… 2°21'07.9\"E.") may remain.
        guard (leftover as String).trimmingCharacters(in: Self.separators).isEmpty else { return nil }

        var values: [Value] = []
        for match in matches {
            guard let value = dmsValue(match, in: text, offset: leading ? 1 : 0) else { return nil }
            let letter = Range(match.range(at: leading ? 1 : 4), in: text).map { String(text[$0]) }
            values.append(Value(magnitude: value.magnitude, negative: value.negative, hemisphere: letter))
        }
        return coordinate(values)
    }

    private static func dmsValue(_ match: NSTextCheckingResult, in text: String, offset: Int) -> (magnitude: Double, negative: Bool)? {
        func group(_ index: Int) -> String? {
            Range(match.range(at: index), in: text).map { String(text[$0]) }
        }
        guard let degreesText = group(1 + offset),
              let degrees = Double(degreesText.replacingOccurrences(of: ",", with: ".")) else { return nil }
        let minutesText = group(2 + offset)
        let secondsText = group(3 + offset)
        let isFractional = degreesText.contains(".") || degreesText.contains(",")
        if isFractional, minutesText != nil || secondsText != nil { return nil }

        let minutes = minutesText.flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) } ?? 0
        let seconds = secondsText.flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) } ?? 0
        guard minutes < 60, seconds < 60 else { return nil }
        return (abs(degrees) + minutes / 60 + seconds / 3600, degreesText.hasPrefix("-"))
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
