import SwiftUI
import UIKit

@main
struct LocSimApp: App {
    @StateObject private var session: SpoofSession
    @StateObject private var favorites = FavoriteList()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        Defaults.register()
        _session = StateObject(wrappedValue: SpoofSession())
    }

    var body: some Scene {
        WindowGroup {
            MapScreen()
                .environmentObject(session)
                .environmentObject(favorites)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            switch phase {
            case .active: session.hasBeenActive = true
            case .background: Task { await session.enteredBackground() }
            default: break
            }
        }
    }
}
