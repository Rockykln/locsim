import SwiftUI
import UIKit

@main
struct LocSimApp: App {
    // Shared with App Intents, which run in this process without the UI.
    @StateObject private var session = SimulationSession.shared
    @StateObject private var favorites = FavoriteList.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        LocSimShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            MapScreen()
                .environmentObject(session)
                .environmentObject(favorites)
                .environmentObject(session.recents)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: Task { await session.becameActive() }
            case .background: Task { await session.enteredBackground() }
            default: break
            }
        }
    }
}
