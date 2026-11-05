import AppIntents
import SwiftUI
import WidgetKit

/// Opens LocSim and sets the location that was simulated last.
@available(iOS 18.0, *)
struct SetLastLocationControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.rockykln.locsim.control.set") {
            ControlWidgetButton(action: SetLastLocationIntent()) {
                Label("Set Last Location", systemImage: "location.fill")
            }
        }
        .displayName("Set Last Location")
        .description("Opens LocSim and simulates the last location again.")
    }
}

/// Ends the simulated location without opening LocSim. The intent is a Live Activity intent,
/// which the system runs in the app's process, where the connection to the device is.
@available(iOS 18.0, *)
struct ClearLocationControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.rockykln.locsim.control.clear") {
            ControlWidgetButton(action: StopSimulationIntent()) {
                Label("Clear Location", systemImage: "location.slash")
            }
        }
        .displayName("Clear Location")
        .description("Ends the simulated location and restores the real one.")
    }
}
