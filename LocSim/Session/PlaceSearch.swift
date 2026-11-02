import CoreLocation
import MapKit

struct SearchError: LocalizedError {
    let query: String
    var errorDescription: String? { String(localized: "No results for \"\(query)\"") }
}

@MainActor
final class PlaceSearch: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    struct Place {
        let name: String
        let coordinate: CLLocationCoordinate2D
    }

    @Published var query = "" {
        didSet { update() }
    }
    @Published private(set) var completions: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    var coordinate: CLLocationCoordinate2D? { CoordinateParser.parse(query) }

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

    func reset() {
        query = ""
        completions = []
    }

    private func run(_ request: MKLocalSearch.Request, fallbackName: String) async throws -> Place {
        let response: MKLocalSearch.Response
        do {
            response = try await MKLocalSearch(request: request).start()
        } catch let error as MKError where error.code == .placemarkNotFound {
            throw SearchError(query: fallbackName)
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
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in self.completions = [] }
    }
}

extension MKLocalSearchCompletion {
    var id: String { "\(title)|\(subtitle)" }
}
