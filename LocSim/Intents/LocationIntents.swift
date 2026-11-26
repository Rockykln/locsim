import AppIntents
import CoreLocation
import Foundation
import LocSimCore

/// Setting a location needs the app in the foreground: the first connection may ask for the
/// VPN configuration, and the background keep-alive can only start from there.
struct SetFavoriteIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Location to Favorite"
    static let description = IntentDescription("Opens LocSim and simulates the location of a saved favorite.")
    static let openAppWhenRun = true

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground }

    @Parameter(title: "Favorite", description: "A place the person saved as a favorite in LocSim")
    var favorite: FavoriteEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Set location to \(\.$favorite)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let c = CLLocationCoordinate2D(latitude: favorite.latitude, longitude: favorite.longitude)
        try await LocationIntentRunner.set(c, name: favorite.name)
        return .result(dialog: "LocSim simulates \(favorite.name).")
    }
}

struct SetCoordinatesIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Coordinates"
    static let description = IntentDescription(
        // App Intent texts must not name Apple products: "Apple Maps" fails the upload check.
        "Opens LocSim and simulates a location from coordinates or a map link that contains them.")
    static let openAppWhenRun = true

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground }

    @Parameter(title: "Coordinates", description: "For example 48.8566, 2.3522")
    var coordinates: String

    static var parameterSummary: some ParameterSummary {
        Summary("Set location to \(\.$coordinates)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Whole numbers count here: "0, 0" is meant as coordinates, not typed halfway.
        guard let c = CoordinateParser.parse(coordinates, allowWholeNumbers: true) else {
            throw LocationIntentError(String(localized: "No coordinates found in “\(coordinates)”."))
        }
        // The same names as in the app: from a map link, else a favorite or recent place at this spot.
        let name = CoordinateParser.linkName(in: coordinates) ?? SimulationSession.shared.knownName(for: c)
        try await LocationIntentRunner.set(c, name: name)
        // Siri reads degree symbols poorly; the coordinate is spoken in words and shown as usual.
        return .result(dialog: IntentDialog(
            full: "LocSim simulates \(CoordinateParser.spoken(c)).",
            supporting: "LocSim simulates \(CoordinateParser.format(c))."))
    }
}

/// Clearing needs no UI, so it runs in the background.
struct ClearLocationIntent: AppIntent {
    static let title: LocalizedStringResource = "Clear Location"
    static let description = IntentDescription("Ends the simulated location and restores the real one.")
    static let openAppWhenRun = false

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .background }

    static var parameterSummary: some ParameterSummary {
        Summary("Clear the simulated location")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let session = SimulationSession.shared
        // A location only lasts as long as this process, so a fresh launch has nothing to clear.
        // After a Clear that did not finish, the device may still simulate it: try again.
        let unfinished = session.state.error?.code == AppError.clearFailedCode || session.unclearedPlace != nil
        guard session.canClear || unfinished else {
            return .result(dialog: "No location is simulated.")
        }
        // The preview only moved the pin; the device never had a location to give back.
        let wasPreview = session.isPreview
        // Also waits for the Live Activity to end: iOS may suspend LocSim as soon as this returns.
        await session.clear()
        if wasPreview { return .result(dialog: "No location is simulated.") }
        if let error = session.state.error { throw LocationIntentError(error.summary) }
        return .result(dialog: "The real location is back.")
    }
}

@MainActor
enum LocationIntentRunner {
    static func set(_ c: CLLocationCoordinate2D, name: String?) async throws {
        let session = SimulationSession.shared
        // Without the one-time setup there is nothing to connect to; say so instead of failing later.
        // The preview only moves the pin; a Shortcut must not report a location as simulated.
        // A file the setup script copied in is taken in when the connection starts.
        guard PairingStore.exists || PairingStore.hasDroppedFile || Demo.isOn else {
            throw LocationIntentError(String(localized: "LocSim is not set up yet. Open LocSim and follow the setup steps."))
        }
        if session.isPreview { session.endPreview() }
        // Waits also while this Set is queued behind another one, so Shortcuts hear how it ended.
        switch await session.setAndWait(c, name: name) {
        case .set:
            return
        case .failed(let error) where AppError.questionCodes.contains(error.code):
            // The question waits in LocSim, and the answer there sets this place. Running the
            // Shortcut again would only ask again.
            throw LocationIntentError(String(localized: "LocSim needs an answer first. Open LocSim and answer the question there; then it sets the location. (\(error.code))"))
        case .failed(let error):
            throw LocationIntentError(session.summary(for: error))
        case .notSet:
            throw LocationIntentError(String(localized: "The location was not set."))
        }
    }
}

struct LocationIntentError: Error, CustomLocalizedStringResourceConvertible {
    let message: String

    init(_ message: String) { self.message = message }

    var localizedStringResource: LocalizedStringResource { "\(message)" }
}

/// A place by name or address, found with the same search as the map. Coordinates and map
/// links work too, so one action covers everything a person might say or paste.
struct SetPlaceIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Location to Place"
    static let description = IntentDescription(
        "Opens LocSim, finds a place by its name or address and simulates its location. Coordinates and map links work too.")
    static let openAppWhenRun = true

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground }

    @Parameter(title: "Place", description: "A place name or address, for example Eiffel Tower or Alexanderplatz, Berlin")
    var place: String

    static var parameterSummary: some ParameterSummary {
        Summary("Set location to \(\.$place)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let found: PlaceSearch.Place
        if let c = CoordinateParser.parse(place) {
            // A map link keeps the place name it carries, as when pasted into the search field.
            let name = CoordinateParser.linkName(in: place) ?? SimulationSession.shared.knownName(for: c)
            found = .init(name: name ?? CoordinateParser.format(c), coordinate: c)
        } else {
            let search = PlaceSearch()
            do {
                if let linked = try await search.place(fromLink: place) {
                    found = linked
                } else {
                    search.query = place
                    found = try await search.search()
                }
            } catch {
                throw LocationIntentError(error.localizedDescription)
            }
        }
        try await LocationIntentRunner.set(found.coordinate, name: found.name)
        return .result(dialog: "LocSim simulates \(found.name).")
    }
}

struct LocSimShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SetFavoriteIntent(),
            phrases: [
                "Set \(.applicationName) to \(\.$favorite)",
                "Simulate \(\.$favorite) with \(.applicationName)",
                "Set a favorite in \(.applicationName)",
            ],
            shortTitle: "Set Favorite",
            systemImageName: "star")
        AppShortcut(
            intent: ClearLocationIntent(),
            phrases: [
                "Clear the location in \(.applicationName)",
                "Stop \(.applicationName)",
            ],
            shortTitle: "Clear Location",
            systemImageName: "arrow.uturn.backward")
    }
}
