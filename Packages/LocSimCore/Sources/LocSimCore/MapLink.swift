import Foundation

/// Links shared from Apple Maps and Google Maps, also inside text such as "Name\nhttps://…".
public enum MapLink {
    public static func url(in text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("geo:") { return URL(string: trimmed) }
        guard let range = trimmed.range(of: #"https?://[^\s<>"]+"#, options: [.regularExpression, .caseInsensitive])
        else { return nil }
        // Chats put links in sentences or brackets: "see https://…)." should not keep ")."
        var link = String(trimmed[range])
        while let last = link.last, ".,;:!?)]}'\"".contains(last) { link.removeLast() }
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
            guard let value = value(key, in: url)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { continue }
            if CoordinateText.parse(value) != nil { continue }
            return value
        }
        return nil
    }
}
