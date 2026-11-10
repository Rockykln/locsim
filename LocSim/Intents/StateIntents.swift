import AppIntents
import Contacts
import CoreLocation
import Foundation

// Read-only actions for automations that check what LocSim does. They run in the background:
// a location only lasts as long as LocSim runs, so a fresh launch means nothing is simulated.

struct IsLocationSimulatedIntent: AppIntent {
    static let title: LocalizedStringResource = "Is Location Simulated"
    static let description = IntentDescription("Returns true while LocSim simulates a location, otherwise false.")
    static let openAppWhenRun = false

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .background }

    static var parameterSummary: some ParameterSummary {
        Summary("Check whether a location is simulated")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        let simulated = SimulationSession.shared.simulatedPlace != nil
        return .result(value: simulated, dialog: simulated ? "A location is simulated." : "No location is simulated.")
    }
}

struct GetSimulatedLocationIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Simulated Location"
    static let description = IntentDescription(
        "Returns the place LocSim simulates, with its name and coordinates. Fails when no location is simulated.")
    static let openAppWhenRun = false

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .background }

    static var parameterSummary: some ParameterSummary {
        Summary("Get the simulated location")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<CLPlacemark> & ProvidesDialog {
        guard let place = SimulationSession.shared.simulatedPlace else {
            throw LocationIntentError(String(localized: "No location is simulated."))
        }
        let c = place.coordinate
        let name = place.name ?? CoordinateParser.format(c)
        // A placemark, so Shortcuts treats it as a location: latitude, longitude, name, maps.
        let placemark = CLPlacemark(
            location: CLLocation(latitude: c.latitude, longitude: c.longitude), name: name, postalAddress: nil)
        return .result(value: placemark, dialog: "LocSim simulates \(name).")
    }
}
