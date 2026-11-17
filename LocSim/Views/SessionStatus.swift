import SwiftUI

/// The state as the map and Settings both show it, so the two never differ.
extension SimulationSession {
    /// Until the device answers a Clear, the state still says active although the location is going.
    var statusTitle: String {
        if isClearing { return String(localized: "Clearing") }
        switch state {
        case .idle: return String(localized: "Not active")
        case .connecting: return String(localized: "Connecting")
        case .active: return isPreview ? String(localized: "Preview") : String(localized: "Active")
        case .reconnecting: return String(localized: "Reconnecting")
        case .failed(let error): return error.title
        }
    }

    var statusColor: Color {
        if isClearing { return .orange }
        switch state {
        case .active: return .green
        case .failed: return .red
        case .connecting, .reconnecting: return .orange
        case .idle: return .gray
        }
    }
}
