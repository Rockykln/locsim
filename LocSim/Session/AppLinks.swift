import Foundation

enum AppLinks {
    static let repository = URL(string: "https://github.com/Rockykln/locsim")!

    /// Website paths by app localization, besides English, which lives at the root.
    private static let sitePaths = [
        "de": "de", "fr": "fr", "es": "es", "it": "it", "nl": "nl", "pt-BR": "pt", "pt": "pt",
    ]

    private static var sitePrefix: String {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        return sitePaths[code].map { "\($0)/" } ?? ""
    }

    /// Separate host that redirects to the site, so its opens show up on their own in Cloudflare's metrics.
    static var website: URL { URL(string: "https://locsim-app.rockykln.com/" + sitePrefix)! }
    static var setupGuide: URL { URL(string: "https://locsim.rockykln.com/" + sitePrefix + "setup/")! }
    static var privacy: URL { URL(string: "https://locsim.rockykln.com/" + sitePrefix + "privacy/")! }
    static var support: URL { URL(string: "https://locsim.rockykln.com/" + sitePrefix + "support/")! }

    static var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    /// Language the app currently runs in; changed in the system's per-app settings.
    static var languageName: String {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        let name = Locale.current.localizedString(forLanguageCode: code) ?? code
        return name.capitalized(with: .current)
    }

    static var commit: String {
        let value = Bundle.main.infoDictionary?["LocSimCommit"] as? String ?? ""
        return value.isEmpty ? String(localized: "unknown") : value
    }
}
