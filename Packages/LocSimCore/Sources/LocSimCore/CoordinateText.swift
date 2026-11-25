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
/// "48,85660° N, 2,35220° O") and degrees, minutes, seconds ("48°51'23.8"N 2°21'07.9"E"),
/// also degrees and decimal minutes as GPS devices write them ("N 48° 51.397 E 002° 21.132").
/// Hemisphere letters may lead or trail; longitude-first input is swapped.
/// Apple Maps, Google Maps, OpenStreetMap, Waze and Bing links and geo: URIs are read as well.
/// Decimal output always uses a period, so it can be pasted anywhere.
public enum CoordinateText {
    /// The device language, which decides whether "O" means east or west. Not the app's: LocSim
    /// has no Catalan, so on a Catalan iPhone the app runs in English while "O" means Oest.
    public static var currentLanguage: String? {
        guard let first = Locale.preferredLanguages.first else { return Locale.current.language.languageCode?.identifier }
        return Locale.Language(identifier: first).languageCode?.identifier
    }

    /// `language` is an ISO 639 code such as "de" or "fr": "O" is west (Ouest, Oeste, Ovest) in
    /// Romance languages and east (Ost, Oost, Öst) otherwise.
    /// `allowWholeNumbers`: "52, 13" counts. The search field rejects it, since it is often only
    /// typed halfway; a shortcut that is given coordinates on purpose does not need that.
    public static func parse(_ text: String, language: String? = currentLanguage,
                             allowWholeNumbers: Bool = false) -> Coordinate? {
        let oIsWest = isWestO(language)
        let links = MapLink.links(in: text)
        let maps = links.filter { MapLink.isPlaceLink($0.url) }
        if let c = maps.lazy.compactMap({ mapLink($0.url, oIsWest: oIsWest) }).first { return c }
        // A Maps link without coordinates names the place and is followed or searched instead.
        // Google's short links cannot be followed, so coordinates written next to them count.
        if !maps.isEmpty, !maps.allSatisfy({ MapLink.isGoogleShortLink($0.url) }) { return nil }
        // Coordinates written next to other links, "48.85, 2.35 https://…": only the links are
        // removed, so numbers inside a link, e.g. a place ID, never count.
        var rest = text
        for link in links.reversed() { rest.replaceSubrange(link.range, with: " ") }
        rest = rest.replacingOccurrences(of: #"\(\s*\)|\[\s*\]|<\s*>"#, with: " ", options: .regularExpression)
        // Labels in front decide the order for every part, also "Lng / Lat: 2.35, 48.85".
        let swap = isLongitudeFirst(rest)
        // Wikipedia writes the same place several ways: "48°51′24″N 2°21′08″E / 48.85667°N … / 48.85667; 2.35222".
        if rest.contains(" / ") {
            for part in rest.components(separatedBy: " / ") {
                if let c = parseText(part, oIsWest: oIsWest, allowWholeNumbers: allowWholeNumbers, longitudeFirst: swap) {
                    return c
                }
            }
        }
        return parseText(rest, oIsWest: oIsWest, allowWholeNumbers: allowWholeNumbers, longitudeFirst: swap)
    }

    static func isWestO(_ language: String?) -> Bool {
        let code = language?.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init)
        return ["fr", "es", "it", "pt", "ca", "ro", "gl"].contains(code ?? "")
    }

    // "Latitude: 48.85, Longitude: 2.35", "lat 48.85 lon 2.35", "Lat/Long:", also in the app's languages: labels
    // are dropped. Not general words such as "Location": "Location 1.5 2.5" stays a name.
    private static let labels = try! NSRegularExpression(
        pattern: #"(?<!\p{L})(?:coordinates?|coords?|coordonnées|coordenadas|koordinaten|coördinaten|gps|📍"#
            + #"|lat(?:itud(?:e|ine)?)?|lon(?:g(?:itud(?:e|ine)?)?)?|lng"#
            + #"|breite(?:ngrad)?|länge(?:ngrad)?|breedte(?:graad)?|lengte(?:graad)?)(?!\p{L})\s*[:=/]?"#,
        options: [.caseInsensitive])

    /// "Longitude: 2.35, Latitude: 48.85": the labels give the order. A longitude label alone does
    /// not, "Long Beach 12" is a name.
    private static func isLongitudeFirst(_ text: String) -> Bool {
        let axes = labels.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match -> Bool? in
            guard let range = Range(match.range, in: text) else { return nil }
            let label = text[range].lowercased()
            if ["lat", "breite", "breedte"].contains(where: label.hasPrefix) { return false }
            if ["lon", "lng", "länge", "lengte"].contains(where: label.hasPrefix) { return true }
            return nil
        }
        return axes.first == true && axes.contains(false)
    }

    // A lowercase "e" between two numbers is "and" in Italian and Portuguese, "41.90 e 12.49", not east.
    private static let andE = try! NSRegularExpression(pattern: #"\d\s+e\s+[-+]?\d"#)

    /// `longitudeFirst`: from the labels of the whole text; nil reads them from this text.
    private static func parseText(
        _ text: String, oIsWest: Bool, allowWholeNumbers: Bool = false, longitudeFirst: Bool? = nil
    ) -> Coordinate? {
        let range = NSRange(text.startIndex..., in: text)
        let unlabeled = labels.stringByReplacingMatches(in: text, range: range, withTemplate: " ")
        let input = unwrap(normalize(unlabeled, oIsWest: oIsWest))
        guard !isRejectedNumber(input, allowWholeNumbers: allowWholeNumbers) else { return nil }
        // Read as east, the first value would silently become the longitude.
        if andE.firstMatch(in: unlabeled, range: NSRange(unlabeled.startIndex..., in: unlabeled)) != nil,
           hemisphereRegex.numberOfMatches(in: input, range: NSRange(input.startIndex..., in: input)) == 1 {
            return nil
        }
        let swap = longitudeFirst ?? isLongitudeFirst(text)
        // "48.85, W 2.35": each half has its own letter, wherever it stands.
        if let c = parseHalves(input, longitudeFirst: swap) { return c }
        if isDMS(input) { return parseDMS(input, longitudeFirst: swap) }
        return parseDecimal(input, longitudeFirst: swap) ?? parseDegreesMinutes(input, degreesMinutes, letter: 1)
            ?? parseDegreesMinutes(input, degreesMinutesTrailing, letter: 3)
    }

    private static let wrappers: [Character: Character] = [
        "(": ")", "[": "]", "{": "}", "\"": "\"", "'": "'", "“": "”", "„": "“", "«": "»",
    ]

    /// "(48.85, 2.35)", "\"48.85, 2.35\"" or "48.85, 2.35.": punctuation around the text is no word.
    private static func unwrap(_ text: String) -> String {
        var s = text
        func trimEnd() {
            while let last = s.last, ".,;:!".contains(last) || last.isWhitespace { s.removeLast() }
        }
        trimEnd()
        if s.count >= 2, let first = s.first, let close = wrappers[first], s.last == close {
            s = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            trimEnd()
        }
        return s
    }

    private static let bareIntegers = try! NSRegularExpression(pattern: #"^[-+]?\d+(?:\s*[,;]\s*|\s+)[-+]?\d+$"#)
    private static let thousands = try! NSRegularExpression(
        pattern: #"^[-+]?\d{1,3}(?:(?:,\d{3})+(?:\.\d+)?|(?:\.\d{3})+(?:,\d{1,2})?)$"#)
    private static let exponent = try! NSRegularExpression(pattern: #"\dE[-+]?\d"#)
    // "7-11" or "24-7" is a name or a range; a negative second value needs a space or comma before it.
    private static let joinedByDash = try! NSRegularExpression(pattern: "\\d[-+\u{2013}\u{2212}]\\d")
    private static let latitudeLetter = try! NSRegularExpression(pattern: #"(?<![A-Z])[NS](?![A-Z])"#)

    /// Numbers typed into the search field that are not meant as coordinates: "1,5" or "48,8" on the
    /// way to "48,8566 2,3522", "3 4", prices like "1.000,50" and "1,000", and "4.88566E1".
    private static func isRejectedNumber(_ text: String, allowWholeNumbers: Bool) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        if !allowWholeNumbers, bareIntegers.firstMatch(in: text, range: range) != nil { return true }
        if thousands.firstMatch(in: text, range: range) != nil { return true }
        if joinedByDash.firstMatch(in: text, range: range) != nil { return true }
        // "N48.85E2.35" has a letter for the latitude, so its E is a hemisphere, not an exponent.
        return exponent.firstMatch(in: text, range: range) != nil
            && latitudeLetter.firstMatch(in: text, range: range) == nil
    }

    // Minute and second marks as keyboards and documents write them, also the "smart" ones.
    private static func isDMS(_ text: String) -> Bool {
        text.rangeOfCharacter(from: CharacterSet(charactersIn: "'′’‘ʹ\"″”“ʺ")) != nil
    }

    private static let hemisphereRegex = try! NSRegularExpression(pattern: hemisphere)
    private static let separators = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;."))
    private static let singleNumber = try! NSRegularExpression(pattern: "^\(number)\\s*°?$")

    /// Two halves split by a comma or semicolon, each with one value and at most one letter.
    /// nil when the text is not like that, e.g. with decimal commas ("48,85 2,35").
    private static func parseHalves(_ text: String, longitudeFirst: Bool) -> Coordinate? {
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
        return coordinate(values, longitudeFirst: longitudeFirst)
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
    public static func coordinate(inLink url: URL, language: String? = currentLanguage) -> Coordinate? {
        guard MapLink.isPlaceLink(url) else { return nil }
        return mapLink(url, oIsWest: isWestO(language))
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

    private static func mapLink(_ url: URL, oIsWest: Bool) -> Coordinate? {
        if url.scheme?.lowercased() == "geo" {
            let decoded = url.absoluteString.removingPercentEncoding ?? url.absoluteString
            let body = decoded.dropFirst(4).split(whereSeparator: { $0 == "?" || $0 == ";" }).first ?? ""
            let base = pair(String(body))
            // Android puts the place into q when the base is 0,0: geo:0,0?q=48.85,2.35(Label).
            // With a name or address there, geo:0,0?q=Cafe, it is no coordinate but a search.
            if base == Coordinate(latitude: 0, longitude: 0), let q = MapLink.value("q", in: url) {
                return pair(String(q.prefix { $0 != "(" }))
            }
            return base
        }
        guard MapLink.isMap(url) else { return nil }
        // OpenStreetMap: the marker, else the map view in the fragment, #map=15/48.85/2.35.
        if let lat = MapLink.value("mlat", in: url).flatMap(Double.init),
           let lon = MapLink.value("mlon", in: url).flatMap(Double.init) {
            let c = Coordinate(latitude: lat, longitude: lon)
            if c.isValid { return c }
        }
        if let lat = MapLink.value("lat", in: url).flatMap(Double.init),
           let lon = (MapLink.value("lon", in: url) ?? MapLink.value("lng", in: url)).flatMap(Double.init) {
            let c = Coordinate(latitude: lat, longitude: lon)
            if c.isValid { return c }
        }
        // Waze: to=ll.48.85,2.35
        if let to = MapLink.value("to", in: url), to.hasPrefix("ll."), let c = pair(String(to.dropFirst(3))) {
            return c
        }
        // OpenStreetMap directions: the destination is the last stop of route=52.52,13.40;48.85,2.35.
        // The map view in the fragment can be anywhere between the stops.
        let osmHost = url.host?.lowercased() ?? ""
        if ["openstreetmap.org", "www.openstreetmap.org", "osm.org"].contains(osmHost), url.path.hasPrefix("/directions") {
            if let route = MapLink.value("route", in: url) {
                return route.split(separator: ";").last.flatMap { pair(String($0)) }
            }
            // A form filled in but not yet routed: to=48.85,2.35.
            return MapLink.value("to", in: url).flatMap { pair($0) }
        }
        // Not "sll": in Apple's links that is only the center of the search area. In Google's,
        // "ll" is only the map view too, so the place in q or the destination comes first.
        let host = url.host?.lowercased() ?? ""
        let google = host.contains("google.") || host.hasSuffix("goo.gl")
        let keys = google
            ? ["q", "query", "daddr", "destination", "coordinate", "ll"]
            : ["ll", "coordinate", "q", "query", "daddr", "destination"]
        for key in keys {
            guard let value = MapLink.value(key, in: url) else { continue }
            // "48.85,2.35 (Cafe)": the label in brackets is not part of the coordinates.
            let bare = String(value.prefix { $0 != "(" }).trimmingCharacters(in: .whitespaces)
            // A search term such as "7 11" is a name; only a view or pin may be whole numbers.
            if let c = pair(bare, decimalRequired: !["ll", "coordinate"].contains(key)) { return c }
            // Coordinates written out, e.g. q=48°51'23.8"N 2°21'07.9"E.
            if bare.range(of: #"\d"#, options: .regularExpression) != nil, let c = parseText(bare, oIsWest: oIsWest) {
                return c
            }
        }
        // Bing: cp=48.85~2.35
        if let cp = MapLink.value("cp", in: url), let c = pair(cp.replacingOccurrences(of: "~", with: ",")) {
            return c
        }
        if let fragment = url.fragment, fragment.hasPrefix("map=") {
            let parts = fragment.dropFirst(4).split(separator: "/")
            // OSM appends the chosen layer: #map=15/48.85/2.35&layers=C.
            let lon = parts.count == 3 ? parts[2].prefix { $0 != "&" } : ""
            if parts.count == 3, let c = pair("\(parts[1]),\(lon)") { return c }
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
            return MapLink.routeDestination(url).flatMap { pair($0.replacingOccurrences(of: "+", with: " "), decimalRequired: true) }
        }
        // /maps/search/48.85,+2.35/… and /maps/place/48.85,+2.35/…: the term itself is the place.
        if kind == "search" || kind == "place", let maps, parts.indices.contains(maps + 2) {
            let term = parts[maps + 2].replacingOccurrences(of: "+", with: " ")
            if let c = pair(term, decimalRequired: true) { return c }
            // Written out, /maps/place/48°51'23.8"N+2°21'07.9"E
            if term.range(of: #"\d"#, options: .regularExpression) != nil, let c = parseText(term, oIsWest: oIsWest) {
                return c
            }
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
    /// `decimalRequired`: search terms such as "7 11" or "24 7" are names, not coordinates.
    private static func pair(_ text: String, decimalRequired: Bool = false) -> Coordinate? {
        var text = text.trimmingCharacters(in: .whitespaces)
        if text.lowercased().hasPrefix("loc:") { text.removeFirst(4) }
        let parts = text.split(whereSeparator: { $0 == "," || $0 == " " })
        guard parts.count == 2 || parts.count == 3,
              parts.allSatisfy({ $0.range(of: #"^[-+]?\d+(\.\d+)?$"#, options: .regularExpression) != nil }),
              !decimalRequired || parts.prefix(2).contains(where: { $0.contains(".") }),
              let lat = Double(parts[0]), let lon = Double(parts[1]) else { return nil }
        let c = Coordinate(latitude: lat, longitude: lon)
        return c.isValid ? c : nil
    }

    private struct Value {
        let magnitude: Double
        let negative: Bool
        let hemisphere: String?
    }

    // "O" is replaced by E or W in normalize().
    private static let hemisphere = #"(?<![A-Z])[NSEW](?![A-Z])"#
    private static let number = #"[-+]?\d+(?:[.,]\d+)?"#

    private static func normalize(_ text: String, oIsWest: Bool) -> String {
        // Degree look-alikes first: the compatibility mapping turns º and ⁰ into "o" and "0",
        // and the acute accent, used as a minute mark, into a space and a combining accent.
        text.replacingOccurrences(of: "[º˚⁰∘]", with: "°", options: .regularExpression)
            .replacingOccurrences(of: "´", with: "'")
            .replacingOccurrences(of: "[\u{FEFF}\u{200B}-\u{200D}\u{2060}]", with: "", options: .regularExpression)
            // Fullwidth digits and punctuation from CJK input methods.
            .precomposedStringWithCompatibilityMapping
            .replacingOccurrences(of: "\u{060C}", with: ",")
            // Minus written as a dash or hyphen character, e.g. copied from a document.
            .replacingOccurrences(of: "[\u{2010}-\u{2014}\u{2212}\u{FE63}\u{FF0D}]", with: "-", options: .regularExpression)
            .replacingOccurrences(of: "[\u{2000}-\u{200A}\u{202F}\u{205F}\u{3000}\u{00A0}]", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: #"(?<!\p{L})(?:OUEST|OESTE|OVEST|OEST|VEST|WEST)(?!\p{L})"#, with: "W", options: .regularExpression)
            .replacingOccurrences(of: #"(?<!\p{L})(?:OOST|OST|LESTE|ESTE|EST|EAST)(?!\p{L})"#, with: "E", options: .regularExpression)
            .replacingOccurrences(of: #"(?<!\p{L})(?:NOORD|NORD|NORTE|NORTH)(?!\p{L})"#, with: "N", options: .regularExpression)
            .replacingOccurrences(of: #"(?<!\p{L})(?:ZUID|SÜD|SUD|SUL|SUR|SOUTH)(?!\p{L})"#, with: "S", options: .regularExpression)
            .replacingOccurrences(of: #"(?<![A-Z])O(?![A-Z])"#, with: oIsWest ? "W" : "E", options: .regularExpression)
    }

    private static let decimalToken = try! NSRegularExpression(pattern: "(\(hemisphere))|(\(number))")
    private static let decimalLeftover = try! NSRegularExpression(pattern: "\(hemisphere)|\(number)|[\\s,;°]")

    private static func parseDecimal(_ text: String, longitudeFirst: Bool) -> Coordinate? {
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
        return coordinate(values, longitudeFirst: longitudeFirst)
    }

    // The degrees never start inside a run of digits: trying every position of a long one took seconds.
    private static let dmsCore = #"([-+]?(?<!\d)\d+(?:[.,]\d+)?)\s*°\s*"#   // degrees
        + #"(?:(\d+(?:[.,]\d+)?)\s*['′’‘ʹ]\s*)?"#                         // minutes
        + #"(?:(\d+(?:[.,]\d+)?)\s*(?:["″”“ʺ]|''|′′|’’)\s*)?"#             // seconds
    private static let dmsLeading = try! NSRegularExpression(pattern: "(?:(\(hemisphere))\\s*)?" + dmsCore)
    private static let dmsTrailing = try! NSRegularExpression(pattern: dmsCore + "(?:(\(hemisphere)))?")

    private static func parseDMS(_ text: String, longitudeFirst: Bool) -> Coordinate? {
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
        return coordinate(values, longitudeFirst: longitudeFirst)
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
        if let minutesText, minutesText.contains(where: { $0 == "." || $0 == "," }), secondsText != nil { return nil }

        let minutes = minutesText.flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) } ?? 0
        let seconds = secondsText.flatMap { Double($0.replacingOccurrences(of: ",", with: ".")) } ?? 0
        guard minutes < 60, seconds < 60 else { return nil }
        return (abs(degrees) + minutes / 60 + seconds / 3600, degreesText.hasPrefix("-"))
    }

    // Garmin and geocaching notation, the minute mark is optional: "N 48° 51.397 E 002° 21.132".
    // Possessive spaces: with backtracking, a long run of them before a mismatch took seconds.
    private static let degreesMinutes = try! NSRegularExpression(pattern:
        #"^([NSEW])\s*+(\d{1,3})(?:\s*+°\s*+|\s++)(\d{1,2}(?:[.,]\d+)?)\s*+['′’‘ʹ]?\s*+[,;]?\s*+"#
            + #"([NSEW])\s*+(\d{1,3})(?:\s*+°\s*+|\s++)(\d{1,2}(?:[.,]\d+)?)\s*+['′’‘ʹ]?$"#)
    // The same with the letter after each value: "48° 51.397 N 2° 21.132 E".
    private static let degreesMinutesTrailing = try! NSRegularExpression(pattern:
        #"^(\d{1,3})(?:\s*+°\s*+|\s++)(\d{1,2}(?:[.,]\d+)?)\s*+['′’‘ʹ]?\s*+([NSEW])\s*+[,;]?\s*+"#
            + #"(\d{1,3})(?:\s*+°\s*+|\s++)(\d{1,2}(?:[.,]\d+)?)\s*+['′’‘ʹ]?\s*+([NSEW])$"#)

    /// `letter` is the group of the hemisphere letter within each value: 1 before, 3 after.
    private static func parseDegreesMinutes(_ text: String, _ regex: NSRegularExpression, letter: Int) -> Coordinate? {
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }
        func group(_ index: Int) -> String { Range(match.range(at: index), in: text).map { String(text[$0]) } ?? "" }
        let degreesGroup = letter == 1 ? 2 : 1
        var values: [Value] = []
        for offset in [0, 3] {
            guard let degrees = Double(group(degreesGroup + offset)),
                  let minutes = Double(group(degreesGroup + 1 + offset).replacingOccurrences(of: ",", with: ".")),
                  minutes < 60
            else { return nil }
            values.append(Value(magnitude: degrees + minutes / 60, negative: false, hemisphere: group(letter + offset)))
        }
        return coordinate(values)
    }

    private static func coordinate(_ values: [Value], longitudeFirst: Bool = false) -> Coordinate? {
        guard values.count == 2 else { return nil }
        // "-48.85 N": the sign and the letter contradict or repeat each other.
        guard !values.contains(where: { $0.negative && $0.hemisphere != nil }) else { return nil }
        let signed = values.map { v -> Double in
            let negative = v.negative || v.hemisphere == "S" || v.hemisphere == "W"
            return negative ? -v.magnitude : v.magnitude
        }
        func isLatitude(_ h: String?) -> Bool { h == "N" || h == "S" }
        func isLongitude(_ h: String?) -> Bool { h == "E" || h == "W" }

        let (first, second) = (values[0].hemisphere, values[1].hemisphere)
        if first != nil, second != nil, isLatitude(first) == isLatitude(second) { return nil }
        // Letters decide; without them, labels such as "Longitude: …, Latitude: …" do.
        let swapped = isLongitude(first) || (first == nil && isLatitude(second))
            || (first == nil && second == nil && longitudeFirst)
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
