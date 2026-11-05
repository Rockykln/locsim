import AppIntents
import Foundation

/// Behind the Control Center button: setting a location needs LocSim in the foreground,
/// so the system opens it and runs this in the app's process.
struct SetLastLocationIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Last Location"
    static let description = IntentDescription("Opens LocSim and simulates the last location again.")
    static let openAppWhenRun = true
    // Only for the control; Shortcuts already offers Set Coordinates and Set Location to Favorite.
    static let isDiscoverable = false

    @available(iOS 26.0, *)
    static var supportedModes: IntentModes { .foreground }

    @MainActor
    func perform() async throws -> some IntentResult {
        #if LOCSIM_APP
        try await LocationIntentRunner.set(LastCoordinate.load(), name: LastCoordinate.loadName())
        #endif
        return .result()
    }
}
