import Foundation

/// Links shared from Apple Maps and Google Maps, also inside text such as "Name\nhttps://…".
public enum MapLink {
    public static func url(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // geo: URIs, full links, and Maps links typed or copied without the scheme
        // ("maps.apple/p/…", "google.com/maps/@…"), which are taken as https.
        let pattern = #"(?<![\w])geo:[^\s<>"]+|https?://[^\s<>"]+"#
            + #"|(?<![\w./@])(?:maps\.apple(?:\.com)?|(?:www\.)?google\.[a-z.]{2,6}/maps|maps\.google\.[a-z.]{2,6})[/?][^\s<>"]*"#
        guard let range = trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive])
        else { return nil }
        var link = String(trimmed[range])
        let isGeo = link.lowercased().hasPrefix("geo:")
        if !isGeo, !link.lowercased().hasPrefix("http") { link = "https://" + link }
        // Chats put links in sentences or brackets: "see https://…)." should not keep ")."
        // A geo: label in brackets, "geo:0,0?q=48.85,2.35(Cafe)", keeps its closing bracket.
        let trailing = isGeo && link.contains("(") ? ".,;:!?]}'\"" : ".,;:!?)]}'\""
        while let last = link.last, trailing.contains(last) { link.removeLast() }
        return URL(string: link)
    }

    public static func isMap(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        if host == "maps.apple" || host.hasSuffix(".maps.apple") || host == "maps.apple.com" { return true }
        if host == "maps.app.goo.gl" || isGoogleShortLink(url) { return true }
        // google.com/maps, google.de/maps, maps.google.com, but not docs.google.com.
        let google = host.hasPrefix("google.") || host.hasPrefix("www.google.")
        return host.hasPrefix("maps.google.") || (google && url.path.hasPrefix("/maps"))
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
        return items.first(where: { $0.name == name })?.value?.replacingOccurrences(of: "+", with: " ")
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
