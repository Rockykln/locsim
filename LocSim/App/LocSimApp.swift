import SwiftUI
import UIKit

@main
struct LocSimApp: App {
    // Shared with App Intents, which run in this process without the UI.
    @StateObject private var session = SimulationSession.shared
    @StateObject private var favorites = FavoriteList.shared
    @Environment(\.scenePhase) private var scenePhase
    // Receives the Home Screen quick actions, which SwiftUI has no hook for.
    @UIApplicationDelegateAdaptor(QuickActionAppDelegate.self) private var appDelegate

    init() {
        LocSimShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            MapScreen()
                .environmentObject(session)
                .environmentObject(favorites)
                .environmentObject(session.recents)
                // Favorites tapped in the Home Screen widget.
                .onOpenURL { url in WidgetSync.open(url) }
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
