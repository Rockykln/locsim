import ActivityKit
import AppIntents
import Foundation

/// Shown on the Lock Screen and in the Dynamic Island while a location is simulated,
/// so it is always clear that the location is not real.
struct SimulationActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var name: String
        var coordinate: String
        var reconnecting: Bool
        // Part of the state, not of the attributes: a new Set updates the activity in place.
        var startedAt: Date
    }
}

/// The Stop button of the Live Activity. The system runs it in the app's process,
/// which holds the connection to the device.
struct StopSimulationIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Clear Location"
    static let description = IntentDescription("Ends the simulated location and restores the real one.")
    // Only for the button; Shortcuts already offers Clear Location.
    static let isDiscoverable = false

    @MainActor
    func perform() async throws -> some IntentResult {
        #if LOCSIM_APP
        await SimulationSession.shared.clear()
        // iOS may suspend LocSim as soon as this returns; the activity must be gone by then.
        for activity in Activity<SimulationActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        #endif
        return .result()
    }
}
