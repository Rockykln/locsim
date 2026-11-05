import Foundation

/// Links shared from Apple Maps and Google Maps, also inside text such as "Name\nhttps://…".
public enum MapLink {
    public static func url(in text: String) -> URL? {
        let found = links(in: text).map(\.url)
        let maps = found.filter { $0.scheme?.lowercased() == "geo" || isMap($0) }
        // A Maps link wins over other links in the same text, one with coordinates over one without.
        return maps.first(where: hasCoordinates) ?? maps.first ?? found.first
    }

    // geo: URIs (a label in brackets may contain spaces), full links, and Maps links typed or
    // copied without the scheme ("maps.apple/p/…", "google.com/maps/@…"), which are taken as https.
    // A space after the comma of "ll=48.85, 2.35" or "geo:48.85, 2.35" continues the link.
    private static let spacedPair = #"(?:(?<=[=:,][-+]?\d{1,3}(?:\.\d{1,20})?,)\s+[-+]?\d[^\s<>"(]*)?"#
    private static let linkRegex = try! NSRegularExpression(
        pattern: #"(?<![\w])geo:[^\s<>"(]+"# + spacedPair + #"(?:\([^)<>"]*\))?|https?://[^\s<>"]+"# + spacedPair
            + #"|(?<![\w./@])(?:maps\.apple(?:\.com)?|(?:www\.)?google\.[a-z.]{2,6}/maps|maps\.google\.[a-z.]{2,6})[/?][^\s<>"]*"#
            + spacedPair,
        options: [.caseInsensitive])

    /// Every link in the text with the part of the text it was read from, in order.
    static func links(in text: String) -> [(url: URL, range: Range<String.Index>)] {
        linkRegex.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text), let (url, dropped) = clean(String(text[range])) else {
                return nil
            }
            // The trailing punctuation that was dropped stays in the text.
            return (url, range.lowerBound..<text.index(range.upperBound, offsetBy: -dropped))
        }
    }

    /// The URL and how many characters were dropped from the end of the match.
    private static func clean(_ found: String) -> (URL, Int)? {
        var link = found
        let isGeo = link.lowercased().hasPrefix("geo:")
        // Chats put links in sentences or brackets: "see https://…)." should not keep ")."
        // A closing bracket stays only if it closes one in the link, e.g. a geo: label.
        let opening: [Character: Character] = [")": "(", "]": "[", "}": "{"]
        while let last = link.last {
            if ".,;:!?'\"".contains(last) {
                link.removeLast()
            } else if let open = opening[last], link.filter({ $0 == last }).count > link.filter({ $0 == open }).count {
                link.removeLast()
            } else {
                break
            }
        }
        let dropped = found.count - link.count
        if !isGeo, !link.lowercased().hasPrefix("http") { link = "https://" + link }
        guard let url = URL(string: link)
            ?? URL(string: link.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed) ?? link)
        else { return nil }
        return (url, dropped)
    }

    public static func isMap(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if host == "maps.apple" || host.hasSuffix(".maps.apple") { return true }
        if host == "maps.apple.com" || host.hasSuffix(".maps.apple.com") { return true }
        if host == "maps.app.goo.gl" || isGoogleShortLink(url) { return true }
        let bare = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        if ["openstreetmap.org", "osm.org", "waze.com"].contains(bare) { return true }
        if bare == "bing.com", url.path.hasPrefix("/maps") { return true }
        // google.com/maps, google.de/maps, maps.google.com, but not docs.google.com.
        return host.hasPrefix("maps.google.") || (bare.hasPrefix("google.") && url.path.hasPrefix("/maps"))
    }

    /// A short Apple Maps link (maps.apple/p/…) carries no coordinates; they are in the page it
    /// redirects to. Only Apple's links are resolved, since Apple already serves the map.
    public static func isAppleShortLink(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return (host == "maps.apple" || host.hasSuffix(".maps.apple")) && url.path.hasPrefix("/p/")
    }

    /// The last redirect of a short link can be a page without the place (maps.apple.com/unsupported),
    /// so every step is looked at.
    public static func hasCoordinates(_ url: URL) -> Bool {
        CoordinateText.coordinate(inLink: url) != nil
    }

    /// The most useful of the URLs a short link passed through: one with coordinates, else one with a name.
    public static func bestStep(_ urls: [URL]) -> URL? {
        urls.first(where: hasCoordinates)
            ?? urls.first { isMap($0) && !isAppleShortLink($0) && placeName($0) != nil }
    }

    public static func isGoogleShortLink(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host == "maps.app.goo.gl" || (host == "goo.gl" && url.path.hasPrefix("/maps"))
    }

    /// Query values with "+" for spaces, as Google writes them.
    static func value(_ name: String, in url: URL) -> String? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return items.first(where: { $0.name.lowercased() == name })?.value?.replacingOccurrences(of: "+", with: " ")
    }

    /// The place name in a link, to label the pin or to search for when there are no coordinates.
    public static func placeName(_ url: URL) -> String? {
        for key in ["name", "q", "query", "address"] {
            guard var value = value(key, in: url)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { continue }
            // geo: labels: "geo:0,0?q=Cafe(Label)" or "q=48.85,2.35(Cafe)"
            if url.scheme?.lowercased() == "geo", let open = value.firstIndex(of: "("), value.hasSuffix(")") {
                let label = String(value[value.index(after: open)..<value.index(before: value.endIndex)])
                let base = String(value[..<open]).trimmingCharacters(in: .whitespaces)
                value = CoordinateText.parse(base) != nil || base.isEmpty ? label : base
            }
            if CoordinateText.parse(value) != nil { continue }
            return value
        }
        // Google Maps: /maps/place/<name>/… and /maps/search/<name>/…
        let parts = url.pathComponents
        if let maps = parts.firstIndex(of: "maps"), parts.indices.contains(maps + 2),
           ["place", "search"].contains(parts[maps + 1]) {
            let name = parts[maps + 2].replacingOccurrences(of: "+", with: " ")
            if !name.hasPrefix("@"), CoordinateText.parse(name) == nil { return name }
        }
        return nil
    }
}
