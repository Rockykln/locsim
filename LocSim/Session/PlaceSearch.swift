import CoreLocation
import LocSimCore
import MapKit

struct SearchError: LocalizedError {
    let query: String
    var errorDescription: String? { String(localized: "No results for “\(query)”") }
}

struct UnsupportedMapLink: LocalizedError {
    var errorDescription: String? {
        String(localized: "Short Google Maps links are not supported. Open the link and copy the full address from the browser.")
    }
}

struct SearchUnavailable: LocalizedError {
    var errorDescription: String? { String(localized: "Search is unavailable. Check the internet connection.") }
}

@MainActor
final class PlaceSearch: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    struct Place {
        let name: String
        let coordinate: CLLocationCoordinate2D
    }

    @Published var query = "" {
        didSet {
            // Parsed once per change; views read it many times per redraw.
            if query != oldValue { coordinate = CoordinateParser.parse(query) }
            update()
        }
    }
    private(set) var coordinate: CLLocationCoordinate2D?
    @Published private(set) var completions: [MKLocalSearchCompletion] = []
    /// The query the completer last answered, so an empty list can be told apart from a pending one.
    @Published private(set) var answeredQuery: String?

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    var hasNoMatches: Bool {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && coordinate == nil && completions.isEmpty && answeredQuery == trimmed
    }

    func bias(to region: MKCoordinateRegion) {
        completer.region = region
    }

    func resolve(_ completion: MKLocalSearchCompletion) async throws -> Place {
        try await run(MKLocalSearch.Request(completion: completion), fallbackName: completion.title)
    }

    func search() async throws -> Place {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.region = completer.region
        return try await run(request, fallbackName: query)
    }

    /// Places from Maps links: coordinates in the link itself, a short Apple Maps link that has to be
    /// followed first, or only a name or address to search for.
    func place(fromLink text: String) async throws -> Place? {
        guard let url = MapLink.url(in: text), MapLink.isMap(url) else { return nil }
        if MapLink.isGoogleShortLink(url) { throw UnsupportedMapLink() }
        var link = url
        if MapLink.isAppleShortLink(url) {
            let steps = RedirectSteps()
            do {
                let (_, response) = try await Self.linkSession.data(from: url, delegate: steps)
                link = MapLink.bestStep(steps.urls + [response.url].compactMap { $0 }) ?? url
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard let step = MapLink.bestStep(steps.urls) else { throw SearchUnavailable() }
                link = step
            }
        }
        let name = MapLink.placeName(link)
        if let c = CoordinateText.coordinate(inLink: link) {
            return Place(name: name ?? CoordinateParser.format(.init(latitude: c.latitude, longitude: c.longitude)),
                         coordinate: .init(latitude: c.latitude, longitude: c.longitude))
        }
        guard let name else { throw SearchError(query: url.absoluteString) }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = name
        request.region = completer.region
        return try await run(request, fallbackName: name)
    }

    // Follows the redirect only; nothing is stored.
    private static let linkSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        return URLSession(configuration: config)
    }()

    /// Notes each redirect and stops at the first one with coordinates.
    private final class RedirectSteps: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        private let lock = NSLock()
        private var visited: [URL] = []

        var urls: [URL] { lock.withLock { visited } }

        func urlSession(
            _ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest
        ) async -> URLRequest? {
            guard let url = request.url else { return request }
            lock.withLock { visited.append(url) }
            return MapLink.hasCoordinates(url) ? nil : request
        }
    }

    func reset() {
        query = ""
        completions = []
        answeredQuery = nil
    }

    private func run(_ request: MKLocalSearch.Request, fallbackName: String) async throws -> Place {
        let response: MKLocalSearch.Response
        do {
            response = try await MKLocalSearch(request: request).start()
        } catch let error as MKError where error.code == .placemarkNotFound {
            throw SearchError(query: fallbackName)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // MapKit's own messages for network and server errors are technical.
            throw SearchUnavailable()
        }
        guard let item = response.mapItems.first else {
            throw SearchError(query: fallbackName)
        }
        return Place(name: item.name ?? fallbackName, coordinate: Self.coordinate(of: item))
    }

    private static func coordinate(of item: MKMapItem) -> CLLocationCoordinate2D {
        #if compiler(>=6.2)
        if #available(iOS 26, *) { return item.location.coordinate }
        #endif
        return item.placemark.coordinate
    }

    private func update() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty || coordinate != nil {
            completer.cancel()
            completions = []
        } else {
            completer.queryFragment = trimmed
        }
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let results = Array(completer.results.prefix(6))
        let fragment = completer.queryFragment
        Task { @MainActor in
            // Ignore results for an outdated query.
            guard fragment == self.query.trimmingCharacters(in: .whitespaces) else { return }
            self.completions = results
            self.answeredQuery = fragment
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        let fragment = completer.queryFragment
        Task { @MainActor in
            self.completions = []
            self.answeredQuery = fragment
        }
    }
}

extension MKLocalSearchCompletion {
    var id: String { "\(title)|\(subtitle)" }
}
